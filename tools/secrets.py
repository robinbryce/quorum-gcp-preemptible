#!/usr/bin/env python3
"""Commands to create and store the various kinds of secrets we need.

Uses google secretsmanager api.

See: https://cloud.google.com/secret-manager/docs
"""
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.resolve()))
import subprocess as sp
import warnings

import argparse

import google.oauth2.credentials

# This warning to discorage use of user auth to run automation or service code.
# This is a script for interactive use
from google.auth._default import _CLOUD_SDK_CREDENTIALS_WARNING
from google.api_core import exceptions as ge
from google.cloud import secretmanager as sm

from clicommon import run_and_exit

class Error(Exception): pass

def get_defaults(args, scopes=None, request=None):
    """returns credentials and project based on environment.

    Typically, used with gcloud auth application-default login
    """

    warnings.filterwarnings("ignore", message=_CLOUD_SDK_CREDENTIALS_WARNING)
    return google.auth.default(scopes=scopes, request=request)


def cmd_create_wallet(args):
    """Create an ethereum wallet key"""
    raise Error('nyi')


def cmd_create_nodekey(args):
    """Create a geth node key"""

    labels = {}
    for labelstring in args.labels:
        print(labelstring)
        for l in labelstring.split(","):
            k, v = l.split(":", 1)
            labels[k] = v

    for k, v in labels.items():
        print(f"{k}={v}")

    pwd = Path.cwd()
    key = sp.run(
        f"docker run --rm -v {pwd}:{pwd} -w {pwd}"
        f" -u {os.getuid()}:{os.getgid()}"
        " --entrypoint=/usr/local/bin/bootnode"
        " quorumengineering/quorum:2.6.0 --genkey=/dev/stdout".split(),
        check=True, stdout=sp.PIPE, stderr=sp.PIPE).stdout

    creds, project = get_defaults(args)
    c = sm.SecretManagerServiceClient(credentials=creds)
    parent = c.project_path(project)
    try:
        s = c.create_secret(parent, args.name, dict(
            replication=dict(automatic={}), labels=labels))
        v = c.add_secret_version(s.name, dict(data=key))
        print(f"secret: {s.name}, version: {v.name}")
    except ge.AlreadyExists:
        print(f"{args.name} exists")


def cmd_create_tesserakey(args):
    """Create a tessera key"""
    raise Error('nyi')


def run(args=None):
    if args is None:
        args = sys.argv[1:]

    top = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    top.set_defaults(func=lambda a, b: print("See sub commands in help"))

    subcmd = top.add_subparsers(title="Availalbe commands")
    p = subcmd.add_parser(
        "wallet", help=cmd_create_wallet.__doc__)
    p.set_defaults(func=cmd_create_wallet)

    p = subcmd.add_parser(
        "nodekey", help=cmd_create_nodekey.__doc__)
    p.set_defaults(func=cmd_create_nodekey)
    p.add_argument("name")
    p.add_argument("-l", "--labels", action="append", help="key:val,key2:val2 .. and repeated options are combined")

    p = subcmd.add_parser(
        "tesserakey", help=cmd_create_tesserakey.__doc__)
    p.set_defaults(func=cmd_create_tesserakey)

    args = top.parse_args()
    args.func(args)

if __name__ == "__main__":
    run_and_exit(run)
