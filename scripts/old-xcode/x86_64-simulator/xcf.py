#!/usr/bin/env python3
"""Helpers for sim-x86_64-frameworks.sh.

  xcf.py plan <XCFRAMEWORK>
      Prints "<kind> <sim id> <sim binary> <catalyst binary>" (paths relative to
      the xcframework, kind "static" or "framework") when the xcframework lacks
      an x86_64 iOS Simulator slice but has an x86_64 Mac Catalyst one;
      otherwise "skip <reason>".
  xcf.py addx86 <XCFRAMEWORK> <SIM ID>
      Renames the simulator slice to ios-arm64_x86_64-simulator and lists x86_64
      among its architectures in Info.plist.
  xcf.py package <PACKAGE.SWIFT> <TARGET>...
      Points each named binary target at xcframeworks/<TARGET>.xcframework.
  xcf.py workspace <OUT.xcworkspace> <PROJECT> <PACKAGE DIR>...
      Writes a workspace holding the project and the local packages that
      override the remote ones of the same name.
"""
import plistlib
import re
import sys
from pathlib import Path


def entries(xcf):
    with open(xcf / "Info.plist", "rb") as f:
        info = plistlib.load(f)
    return info, info["AvailableLibraries"]


def binary(entry):
    if "BinaryPath" in entry:
        return entry["BinaryPath"]
    lib = entry["LibraryPath"]
    if lib.endswith(".framework"):
        return f"{lib}/{lib[:-len('.framework')]}"
    return lib


def plan(xcf):
    _, libs = entries(xcf)
    ios = [e for e in libs if e["SupportedPlatform"] == "ios"]
    sim = [e for e in ios if e.get("SupportedPlatformVariant") == "simulator"]
    cat = [e for e in ios if e.get("SupportedPlatformVariant") == "maccatalyst"]
    if not sim or not cat:
        return "skip no-simulator-or-catalyst-slice"
    sim, cat = sim[0], cat[0]
    if "x86_64" in sim["SupportedArchitectures"]:
        return "skip has-x86_64-simulator"
    if "x86_64" not in cat["SupportedArchitectures"]:
        return "skip no-x86_64-catalyst"
    kind = "framework" if sim["LibraryPath"].endswith(".framework") else "static"
    sim_bin = f"{sim['LibraryIdentifier']}/{binary(sim)}"
    cat_bin = f"{cat['LibraryIdentifier']}/{binary(cat)}"
    return f"{kind} {sim['LibraryIdentifier']} {sim_bin} {cat_bin}"


def addx86(xcf, sim_id):
    info, libs = entries(xcf)
    new_id = "ios-arm64_x86_64-simulator"
    for e in libs:
        if e["LibraryIdentifier"] == sim_id:
            e["LibraryIdentifier"] = new_id
            e["SupportedArchitectures"] = ["arm64", "x86_64"]
    (xcf / sim_id).rename(xcf / new_id)
    with open(xcf / "Info.plist", "wb") as f:
        plistlib.dump(info, f)


def package(manifest, targets):
    text = manifest.read_text()
    for name in targets:
        # url and checksum may be literals or expressions (helix-rootshell interpolates its version).
        pattern = re.compile(
            r'\.binaryTarget\(\s*name:\s*"' + re.escape(name)
            + r'",\s*url:.*?,\s*checksum:[^)]*\)', re.DOTALL)
        text, n = pattern.subn(
            f'.binaryTarget(name: "{name}", path: "xcframeworks/{name}.xcframework")', text)
        if n != 1:
            sys.exit(f"{manifest}: found binary target {name} {n} times")
    manifest.write_text(text)


def workspace(out, project, packages):
    refs = "".join(f'   <FileRef location = "absolute:{p}"></FileRef>\n' for p in [project, *packages])
    out.mkdir(parents=True, exist_ok=True)
    (out / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n' + refs + "</Workspace>\n")


cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "plan":
    print(plan(Path(args[0])))
elif cmd == "addx86":
    addx86(Path(args[0]), args[1])
elif cmd == "package":
    package(Path(args[0]), args[1:])
elif cmd == "workspace":
    workspace(Path(args[0]), args[1], args[2:])
else:
    sys.exit(f"unknown command {cmd}")
