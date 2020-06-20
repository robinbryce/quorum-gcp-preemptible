#!/usr/bin/env python3
"""Commands to create and store the various kinds of secrets we need.

Uses google secretsmanager api.

See: https://cloud.google.com/secret-manager/docs
"""
# python -m tools.secrets

from pathlib import Path
from sha3 import keccak_256
import argparse
import coincurve
import google.oauth2.credentials
import json
import os
import secrets  # standard lib!
import subprocess as sp
import sys
import tempfile
import warnings

# This warning to discorage use of user auth to run automation or service code.
# This is a script for interactive use
from google.auth._default import _CLOUD_SDK_CREDENTIALS_WARNING
from google.api_core import exceptions as ge
from google.cloud import secretmanager as sm

from .clicommon import run_and_exit

# macos, and possibly other hypervisor docker envs, don't like sharing /tmp
SCRIPTDIR = Path(__file__).parent.resolve()
TEMPDIR = SCRIPTDIR.parent.joinpath(".tmp")


class Error(Exception):
    """General script error"""

def get_defaults(args, scopes=None, request=None):
    """returns credentials and project based on environment.

    Typically, used with gcloud auth application-default login
    """

    warnings.filterwarnings("ignore", message=_CLOUD_SDK_CREDENTIALS_WARNING)
    return google.auth.default(scopes=scopes, request=request)


def labels_from_args(args):
    """Turn the argparse option for collecting labels into a dict"""
    labels = {}
    for labelstring in args.labels:
        for l in labelstring.split(","):
            try:
                k, v = l.split(":", 1)
            except ValueError:
                raise Error(f"bad label: `{l}'")
            labels[k] = v
    return labels


def create_secret(args, name, data, **labels):
    """create a secret and set its initial version"""

    creds, project = get_defaults(args)
    c = sm.SecretManagerServiceClient(credentials=creds)
    parent = c.project_path(project)

    try:
        s = c.create_secret(parent, name, dict(
            replication=dict(automatic={}), labels=labels))
    except ge.AlreadyExists:
        resourcename = f"projects/{project}/secrets/{name}"
        print(f"secret {args.name} exists, get: {resourcename}")
        s = c.get_secret(resourcename)
    v = c.add_secret_version(s.name, dict(data=data))
    return s, v


def cmd_create_wallet(args):
    """Create an ethereum wallet key"""

    labels = labels_from_args(args)

    key = keccak_256(secrets.token_bytes(32)).digest()

    # Ethereum YP requires public keys to be 64 bytes. coincurve generates the
    # 64 byte public key and includes the bitcoin standard prefix byte which
    # denotes the 'un-compressed or compressed' EC point representation. For
    # eth, we just strip that byte.
    pub = coincurve.PublicKey.from_valid_secret(key).format(compressed=False)[1:]

    # The last 20 bytes of the keccak is the address
    addr = keccak_256(pub).digest()[-20:]

    # We store the key, the public key and the address as seperate secrets. SO
    # that we can deliver the material to any container using the same
    # delivery mechanism. We also store the wallet address on a label on both
    # the public key and the private.

    labels["address"] = "0x" + addr.hex()

    # lastly, locking and unlocking accounts requires the account to be
    # imported and that needs a password. For clients that are sending raw
    # transactions, import/lock/unlock is both un-necessary and only serves to
    # expand the attack surface (clef not withstanding). For clients that do
    # want the geth node to manage accounts, we generate a 'password'
    passwd = keccak_256(secrets.token_bytes(32)).digest()

    for name, data in [
            (args.name + "key", key),
            (args.name + "pub", pub),
            (args.name + "address", addr),
            (args.name + "password", passwd)]:
            s, v = create_secret(args, name, data, **labels)
        print(f"secret: {s.name}, version: {v.name}")


def cmd_create_nodekey(args):
    """Create a geth node key"""

    labels = labels_from_args(args)

    key = sp.run(
        f"docker run --rm -u {os.getuid()}:{os.getgid()}"
        " --entrypoint=/usr/local/bin/bootnode"
        " quorumengineering/quorum:2.6.0 --genkey=/dev/stdout".split(),
        check=True, stdout=sp.PIPE, stderr=sp.PIPE).stdout

    enodeaddr = sp.run(
        f"docker run --rm -i -u {os.getuid()}:{os.getgid()}"
        " --entrypoint=/usr/local/bin/bootnode"
        " quorumengineering/quorum:2.6.0 --nodekey=/dev/stdin --writeaddress".split(),
        input=key, check=True, stdout=sp.PIPE, stderr=sp.PIPE).stdout.strip()
    print(f"enodeaddr: {enodeaddr}")

    for name, data in [
            (args.name + "key", key),
            (args.name + "enode", enodeaddr)]:
        s, v = create_secret(args, name, data, **labels)
        print(f"secret: {s.name}, version: {v.name}")


def cmd_create_tesserakey(args):
    """Create a tessera key"""

    labels = labels_from_args(args)

    with tempfile.TemporaryDirectory(prefix=f"{TEMPDIR.name}-", dir=TEMPDIR.parent) as tmp:

        sp.run(
            f"docker run --rm -v {tmp}:{tmp} -w {tmp}"
            f" -u {os.getuid()}:{os.getgid()}"
            f" quorumengineering/tessera:0.11 -keygen -filename {tmp}/tessera".split(),
            check=True)

        # flatten the private key, because that causes some consumers problems...
        key = json.dumps(json.load(open(Path(tmp).joinpath("tessera.key"), "rb"))).encode()
        pub = open(Path(tmp).joinpath("tessera.pub"), "rb").read()

        for name, data in [
                (args.name + "key", key),
                (args.name + "pub", pub)]:
            s, v = create_secret(args, name, data, **labels)
            print(f"secret: {s.name}, version: {v.name}")


def run(args=None):
    if args is None:
        args = sys.argv[1:]

    top = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    top.set_defaults(func=lambda a, b: print("See sub commands in help"))

    subcmd = top.add_subparsers(title="Availalbe commands")
    p = subcmd.add_parser("wallet", help=cmd_create_wallet.__doc__)
    p.set_defaults(func=cmd_create_wallet)
    p.add_argument("name")
    p.add_argument("-l", "--labels", default=[], action="append", help="key:val,key2:val2 .. and repeated options are combined")

    p = subcmd.add_parser("nodekey", help=cmd_create_nodekey.__doc__)
    p.set_defaults(func=cmd_create_nodekey)
    p.add_argument("name")
    p.add_argument("-l", "--labels", default=[], action="append", help="key:val,key2:val2 .. and repeated options are combined")

    p = subcmd.add_parser("tesserakey", help=cmd_create_tesserakey.__doc__)
    p.set_defaults(func=cmd_create_tesserakey)
    p.add_argument("name")
    p.add_argument("-l", "--labels", default=[], action="append", help="key:val,key2:val2 .. and repeated options are combined")

    args = top.parse_args()
    args.func(args)


if __name__ == "__main__":
    run_and_exit(run, Error)
