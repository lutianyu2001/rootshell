#!/usr/bin/env python3
"""Tap simulator UI elements by accessibility label through idb.

usage: simtap.py <LABEL> [<LABEL>...]     tap each, in order (exact AXLabel)
       simtap.py --list [<SUBSTRING>]     print visible elements' labels and frames

Needs an idb_companion for the booted simulator (IDB_COMPANION, default
localhost:10882; build-idb.sh builds one for an Intel Mac) and the idb client
(`pip install fb-idb`), taken from IDB or PATH.
"""
import json
import os
import shutil
import subprocess
import sys
import time

IDB = os.environ.get("IDB") or shutil.which("idb") or sys.exit("idb not found: set IDB or put it on PATH")
BASE = [IDB, "--companion", os.environ.get("IDB_COMPANION", "localhost:10882")]


def elements():
    out = subprocess.run(BASE + ["ui", "describe-all"], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def main():
    args = sys.argv[1:]
    if args and args[0] == "--list":
        needle = args[1] if len(args) > 1 else ""
        for e in elements():
            label = e.get("AXLabel") or ""
            if needle in label:
                f = e["frame"]
                print(f"{label!r:40} {e.get('type')} x={f['x']:.0f} y={f['y']:.0f} w={f['width']:.0f} h={f['height']:.0f}")
        return
    for label in args:
        matches = [e for e in elements() if e.get("AXLabel") == label]
        if not matches:
            sys.exit(f"no element labelled {label!r}")
        f = matches[0]["frame"]
        x, y = f["x"] + f["width"] / 2, f["y"] + f["height"] / 2
        subprocess.run(BASE + ["ui", "tap", str(round(x)), str(round(y))], check=True)
        print(f"tapped {label!r} at {x:.0f},{y:.0f}")
        time.sleep(0.6)


main()
