"""quorum node initialisaion"""



from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
import argparse
import base64
import json
import os
import requests
import subprocess as sp
import sys

import commoncli

class Error(Exception):
    """General, detected error condition"""


def json_response(resp):
    if resp:
        return resp.json()
    j = resp.json()
    if "error" in j and "message" in j["error"]:
        raise Error(j["error"]["message"])
    raise Error(f"error: status {resp.status_code}")


def text_response(resp):
    if resp:
        return resp.text
    raise Error(f"error: status {resp.status_code}")


def get_workload_token():
    """Get token from metadata service

    Which is available at a well known url or not at all"""
    resp = requests.get(
        f"http://metadata/computeMetadata/v1/instance/service-accounts/default/token",
        headers={"metadata-flavor": "Google"})
    return json_response(resp)["access_token"]


def get_secret(token, project, secret, version):
    resp = requests.get(
        f"https://secretmanager.googleapis.com/v1/projects/"
        f"{project}/secrets/{secret}/versions/{version}:access",
        headers={
            "authorization": f"Bearer {token}",
            "content-type": "application/json"})
    return base64.decodebytes(json_response(resp)["payload"]["data"].encode())


def get_object(
        token, bucket, objectname,
        check_response=True, isjson=True, generation=None):
    """Get the named object from the bucket

    If requested, get the generation from the metadata"""

    # blob storage names look heirarchial but arent. need to quote '/'
    objectname = requests.utils.quote(objectname, safe="")
    qs = f"https://storage.googleapis.com/storage/v1/b/{bucket}/o/{objectname}"

    if generation:
        resp = requests.get(qs, headers={"authorization": f"Bearer {token}"})
        if not resp and not check_response:
            return resp, 0
        generation = json_response(resp)["generation"]

    qs += "?alt=media"
    resp = requests.get(qs, headers={"authorization": f"Bearer {token}"})

    if not check_response:
        return resp, generation

    if isjson:
        return json_response(resp), generation
    return text_response(resp), generation


def get_blob(
        token, bucket, objectname, check_response=True, isjson=False):
    """convenience that doesn't do generation"""

    return get_object(
        token,  bucket, objectname, check_response=check_response, isjson=isjson)[0]


def post_blob(
        token, bucket, objectname, data,
        check_response=True, content_type="application/json", generation=None):
    """post the named object to the bucket"""

    qs = (
        f"https://storage.googleapis.com/upload/storage/v1/b/"
        f"{bucket}/o?uploadType=media&name={objectname}")

    if generation is not None:
        qs += f"&ifGenerationMatch={generation}"

    resp = requests.post(
        qs, data=data,
        headers={"authorization": f"Bearer {token}", "content-type": content_type})

    if not check_response:
        return resp

    return json_response(resp)


def derive_node_pubkey(bootnode, key):
    """Generate the enode address using the bootnode binary

    bootnode can be a docker run wrapper for use on host"""

    return sp.run(
        [bootnode] + "--nodekey=/dev/stdin --writeaddress".split(),
        input=key, check=True,
        stdout=sp.PIPE, stderr=sp.PIPE).stdout.strip().decode().strip()


class NodeConf:
    """Convenience wrapper for the node configuration file"""

    def __init__(self, args):
        conf = Path(args.nodeconf).absolute()
        self._confdir = conf.parent
        self._node = json.load(open(conf))["node"]
        self._nodenum = getattr(args, "nodenum", 0)

        if args.nodekey is not None:
            self._node["key"] = args.nodekey
        if args.nodedir is not None:
            self._node["dir"] = args.nodedir

        self.nodedir = Path(self._confdir.joinpath(self._node["dir"]))
        self.nodekey = Path(self._confdir.joinpath(self._node["key"]))

    @property
    def key_secretname(self):
        return self._node["secretnames"].format(number=self._nodenum, kind="key")

    def get_member_blobname(self, enode):
        return self._node["node_blob"].format(enode=enode)

    def __getattr__(self, name):
        return self._node[name]


def cmd_nodeinit(args):
    """ensure geth node configuration"""

    conf = NodeConf(args)

    token = args.token or get_workload_token()
    genesis = get_blob(token, conf.bucket, conf.genesis_blob, isjson=True)

    # We symlink the nodekey from an emptyDir, that way it never lies around on
    # disc un-necessarily.
    if (conf.nodekey.resolve() == conf.nodedir.joinpath("nodekey")):
        raise Error(
            "The nodekey must be stored outside of the nodedir (symlinked from emptyDir)")

    key = get_secret(token, "quorumpreempt", conf.key_secretname, "latest")
    enode = derive_node_pubkey(args.bootnode, key)

    resp, generation = get_object(
        token, conf.bucket, conf.static_nodes_blob, check_response=False,
        generation=True)

    # Is this a new network ?
    gethinit = False
    if not resp:
        print("Creating new network")

        # Then, regardles of what is on the pv, we are starting from scratch.
        # As this is a little 'bold', archive anything that is hanging around.
        if conf.nodedir.exists():
            backupdir = str(conf.nodedir) + \
                "-" + datetime.utcnow().strftime("%Y-%m-%d.%H-%M-%S-%f")
            print(f"Saving stale network datadir at {backupdir}")
            conf.nodedir.rename(backupdir)
        conf.nodedir.mkdir(parents=True)

        # There is no network, we are the first. use generation=0 pre-condition
        # to break the creation race. RAFT_ID is 1.
        static_nodes = [
            f"enode://{enode}@{conf.ipaddress}:{conf.port}"
            f"?discport=0&raftport={conf.raftport}"]
        gethinit = True
    else:
        if not conf.nodedir.exists():
            # Automatic node recovery
            gethinit = True
        print("Ensuring configuration of existing network")
        static_nodes = json_response(resp)

    # Un-conditionaly write the secrets and blobs to disc. They are the source
    # of truth for the network.

    # emptyDir plus similar arrangements for the main quorum pod can limit the
    # chances of this key being exposed on disc.
    with open(conf.nodekey, "wb") as f:
        f.write(key)

    with open(conf.nodedir.joinpath("enode"), "w") as f:
        f.write(enode)

    # create the symlink, in case someone has been fiddling with the local
    # directory, unlink the target first
    try:
        conf.nodedir.joinpath("nodekey").unlink()
    except FileNotFoundError:
        pass

    os.symlink(conf.nodekey, conf.nodedir.joinpath("nodekey"))

    with open(conf.nodedir.joinpath("genesis.json"), "w") as f:
        json.dump(genesis, f, indent=2, sort_keys=True)

    with open(conf.nodedir.joinpath("static-nodes.json"), "w") as f:
        json.dump(static_nodes, f, indent=2, sort_keys=True)

    # Is this a new network or are we recovering after losing/deleting a pv ?
    if gethinit:
        sp.check_call(
            f"{args.geth} --datadir={conf.nodedir} init {conf.nodedir}/genesis.json".split())

    print(json.dumps(static_nodes, indent=2, sort_keys=True))

    ifound = None
    for ifound, en in enumerate(static_nodes):
        if en.startswith(f"enode://{enode}"):
            return

    # A network exists, but this node is not yet a member.

    raise Error("join not implemented yet")
    # print("Forbidden from updating static-nodes.json blob")
    # resp = post_blob(
    #    token, conf.bucket, conf.static_nodes_blob,
    #    check_response=False,
    #    json.dumps(static_nodes, indent=2, sort_keys=True), generation=0)
    # if not resp:
    #    if resp.status_code == 403:
    #        # This means all is well but we are not a 'bootnode' and so are
    #        # not allowed to update static-nodes json. If there is an
    #        # actual permissions problem this 
    #        return
    #    json_response(resp)


def cmd_genesis(args):
    """ensure chain genesis"""

    conf = NodeConf(args)
    genesisconf = json.load(open(Path(args.genesisconf).absolute()))

    genesis = genesisconf["genesis"]

    token = args.token or get_workload_token()

    resp = get_blob(token, conf.bucket, conf.genesis_blob, check_response=False)
    if resp:
        print(text_response(resp))
        print(f"Found genesis document: {conf.genesis_blob}")
        return

    alloc = genesis.setdefault("alloc", {})
    for wallet in genesisconf["allocwallets"]:
        name, balance = wallet["name"], wallet["balance"]
        address = "0x" + get_secret(token, "quorumpreempt", f"{name}-address", "latest").hex()
        alloc[address] = dict(balance=balance)
        print(f"funding genesis wallet '{name}' at {address} with {balance}")

    genesis = json.dumps(genesis, indent=2, sort_keys=True)
    post_blob(token, conf.bucket, conf.genesis_blob, genesis, content_type="application/json")
    print(genesis)
    print(f"Created genesis document: {conf.genesis_blob}")


def arg_parser(args=None):
    if args is None:
        args = sys.argv[1:]

    top = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)

    top.set_defaults(func=lambda a, b: print("see sub commands in help"))
    top.add_argument(
        "--token", help="provide bearer token for gcp api access")
    top.add_argument(
        "--bootnode", default="bootnode", help="for use on host, refer to docker run sh wrapper")
    top.add_argument(
        "--geth", default="geth", help="for use on host, refer to docker run sh wrapper")
    top.add_argument("--nodedir", help="override nodeconf dir for geth node data")
    top.add_argument("--nodekey", help="override nodeconf key location - must be outside of nodedir")
    top.add_argument("--nodenum", default=0)
    top.add_argument("--nodeconf", default="nodeconf.json", help="node configuration")
    top.add_argument("--succeede", action="store_true", help="exit as though everything is ok")
    top.add_argument("--forever", action="store_true", help="ingore exceptions and run infinite while")

    subgroup = top.add_subparsers(
        title="quorum deployment", description="support for quorum node deployment")

    p = subgroup.add_parser("genesis", help=cmd_genesis.__doc__)
    p.add_argument(
        "-o", "--genesis", default="genesis.conf", help="where to write genesis doc")
    p.add_argument(
        "-G", "--genesisconf", default="genesisconf.json", help="genesis configuration")
    p.set_defaults(func=cmd_genesis)

    p = subgroup.add_parser("nodeinit", help=cmd_nodeinit.__doc__)
    p.set_defaults(func=cmd_nodeinit)
    args = top.parse_args()

    return args


def run(args):

    return args.func(args)

    # print(get_secret(token, "quorumpreempt", "qnode-0-key", "1"))
    # print(get_blob(token, "quorumpreempt-cluster.g.buckets.thaumagen.com", "hello.txt"))
    # print(post_blob_text(token, "quorumpreempt-cluster.g.buckets.thaumagen.com", "qnode-hello.txt", "I am qnode hear me roar"))
    # print(get_blob(token, "quorumpreempt-cluster.g.buckets.thaumagen.com", "qnode-hello.txt"))


if __name__ == "__main__":
    commoncli.run_and_exit(arg_parser, run)
