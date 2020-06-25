"""consistent command line interface for all scripts"""

import time
import sys
from pathlib import Path
import traceback


def forever():
    """It is useful to be able to force a pod to live

    Even in the face of terminal error"""

    while True:
        print("forever loop ...")
        time.sleep(5)


def print_exc():
    """Compact representation of current exception

    Single line tracebacks are individually a little confusing but prevent
    other useful output from being obscured"""

    exc_info = sys.exc_info()
    trace = [
        f"{Path(fn).name}[{ln}].{fun}:\"{txt}\""
        for (fn, ln, fun, txt) in traceback.extract_tb(exc_info[2])
    ] + [f"{exc_info[0].__name__}:{exc_info[1]}"]

    print("->".join(trace), file=sys.stderr)


def run_and_exit(arg_parser, runner, args=None):
    """Standard run wrapper with --succeede and --forever support"""
    args = arg_parser(args=None)
    status = 0
    try:
        status = runner(args)
    except Exception:
        status = 1
        print_exc()
        if getattr(args, "succeede", False):
            sys.exit(status)
        if not getattr(args, "forever", False):
            sys.exit(status)
    if getattr(args, "forever", False):
        try:
            forever()
        except KeyboardInterrupt:
            sys.exit(0 if status is None else status)
