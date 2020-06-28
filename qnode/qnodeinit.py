"""quorum node initialisaion"""



from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
import argparse
import base64
import json
import os
import random
import requests
import subprocess as sp
import sys
from urllib.parse import urlparse, parse_qs

import commoncli


GENERAL_CONNECTION_EXEPTIONS = (
    requests.exceptions.Timeout,
    requests.exceptions.ConnectionError,
    ConnectionAbortedError,
    ConnectionRefusedError,
    ConnectionResetError)


class Error(Exception):
    """General, detected error condition"""


def json_response(resp):

    if not resp:
        raise Error(f"error: status {resp.status_code}")

    j = resp.json()
    if "error" not in j:
        return j

    if "message" in j["error"]:
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

        if args.address is not None:
            self._node["address"] = args.address

        if args.bind is not None:
            self._node["bind"] = args.bind

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
    """ensure geth node configuration


    first node

    disk reset

    join

    """

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

        # There is no network, we are the first. use generation=0 pre-condition
        # to break the creation race. RAFT_ID is 1.
        static_nodes = []
        gethinit = True
    else:
        print("Ensuring configuration of existing network")
        static_nodes = json_response(resp)

    if not conf.nodedir.exists():
        # Automatic node recovery
        gethinit = True
        conf.nodedir.mkdir(parents=True)

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

    # Is this a new network or are we recovering after losing/deleting a pv ?
    if gethinit:
        sp.check_call(
            f"{args.geth} --datadir={conf.nodedir} init {conf.nodedir}/genesis.json".split())

    # As far as possible we un-conditionaly write the local disc state
    # according to what we find in the blob. But RAFT_ID and static-nodes.json
    # are dependent on registration state. And in the face of (development
    # driven) ad-hoc node creation & destruction this takes a few extra steps.
    def write_local_nodeconf(static_nodes, raftid):
        with open(conf.nodedir.joinpath("static-nodes.json"), "w") as f:
            json.dump(static_nodes, f, indent=2, sort_keys=True)
        with open(conf.nodedir.joinpath("RAFT_ID"), "w") as f:
            f.write(str(raftid))

    enode_url = (
        f"enode://{enode}@{conf.address}:{conf.port}"
        f"?discport=0&raftport={conf.raftport}")

    if not static_nodes:

        static_nodes = [enode_url]

        data = json.dumps(static_nodes, indent=2, sort_keys=True)
        post_blob(token, conf.bucket, conf.static_nodes_blob, data=data, generation=generation)
        write_local_nodeconf(static_nodes, 1)
        # first node, nothing more to do.
        return

    # we can only reach here when adding a new node or when recovering a lost
    # disc / nodedir. We specifically support reseting a node by deleting is
    # persitent volume with this setup.

    peers = {}
    iregistered = None
    for i, peer in enumerate(static_nodes):

        if peer.startswith(f"enode://{enode}"):
            iregistered = i
            continue  # registered, only need to ensure local disc contents

        o = urlparse(peer)
        peer_enode, peer_addr = o.netloc.split("@", 1)

        # TODO: the rpcport for the established nodes is not in static_nodes,
        # we will need to get that from elsewhere. For now assuming they are
        # all the same. a blob named after the enode address is the ultimate
        # intent.
        peers[peer_enode] = dict(enode=peer_enode, host=peer_addr.split(":", 1)[0])

    if iregistered == 0:
        # this node is the first entry in static nodes and registration all
        # good.  if we are starting up *in order* as part of a stateful set,
        # the subsequent peers will not have started yet. the first member of
        # static nodes never registers with anyone - it established the
        # network.
        write_local_nodeconf(static_nodes, 1)
        return

    # Chose one at random. We shouldn't need to care which one serves the
    # following requests, stateful set configuration can start sequentially if
    # we like but we specifically accomodate random/parallel startup. k8s
    # exponential (and un configuraable) backof makes an explicit retry policy
    # here worth considering.
    peer = peers[random.choice(list(peers))]
    peer_url = f"http://{peer['host']}:{conf.rpcport}/"

    # Check the current cluster membership and ensure the local copy of RAFT_ID
    # if we are members.
    data = dict(jsonrpc="2.0", method="raft_cluster", id="1")
    print(peer_url)
    resp = requests.post(
        peer_url, json=data, headers={"Content-Type": "application/json"}, timeout=9.1)

    for m in json_response(resp)["result"]:

        if m["nodeId"] == enode:

            if not iregistered:
                # this indicates we registered and failed to update the
                # static-nodes blob. just error out. tlc on the blob can sort
                # this out more safely than anything we could do here
                raise Error("static-nodes.json not consistent with raft.cluster")

            print(f"Wrote {conf.nodedir}/RAFT_ID: {m['raftId']}")
            write_local_nodeconf(static_nodes, m["raftId"])
            return

    # Definitely not registered in the raft acording to the raft.cluster result
    # we just got. And we can count on raft_addPeer failure to resolve any race
    # with other workloads.
    data = dict(
        jsonrpc="2.0", method="raft_addPeer", params=[enode_url], id="1")

    raftid = json_response(
        requests.post(
            peer_url, json=data, headers={"Content-Type": "application/json"},
            timeout=9.1))["result"]

    # add ourselves to static-nodes.json, update the blob, and only if all of
    # that goes ok, update the local disc state.
    static_nodes.append(enode_url)

    data = json.dumps(static_nodes, indent=2, sort_keys=True)
    post_blob(token, conf.bucket, conf.static_nodes_blob, data=data, generation=generation)

    write_local_nodeconf(static_nodes, raftid)


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


def cmd_init(args):
    """ensure the node is initialised

    runs genesis and then nodeinit"""
    cmd_genesis(args)
    cmd_nodeinit(args)


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
    top.add_argument("--address", default="127.0.0.1")
    top.add_argument("--bind", default=None)
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

    p = subgroup.add_parser("init", help=cmd_init.__doc__)
    p.add_argument(
        "-o", "--genesis", default="genesis.conf", help="where to write genesis doc")
    p.add_argument(
        "-G", "--genesisconf", default="genesisconf.json", help="genesis configuration")
    p.set_defaults(func=cmd_init)

    return top.parse_args()


def run(args):
    return args.func(args)


if __name__ == "__main__":
    commoncli.run_and_exit(arg_parser, run)
