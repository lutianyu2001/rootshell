#!/usr/bin/env python3
"""Rewrite the platform of every LC_BUILD_VERSION in a thin x86_64 Mach-O
file, or in each Mach-O member of a static archive, in place.

usage: macho_platform.py <FILE> <FROM> <TO>   (6 = Mac Catalyst, 7 = iOS Simulator)

The field keeps its size, so archive offsets and symbol tables stay valid.
Prints how many load commands it changed; exits 1 when it changed none.
"""
import struct
import sys

LC_BUILD_VERSION = 0x32
MH_MAGIC_64 = 0xFEEDFACF


def patch_macho(buf, base, old, new):
    if len(buf) < base + 32:
        return 0
    magic, = struct.unpack_from("<I", buf, base)
    if magic != MH_MAGIC_64:
        return 0
    ncmds, = struct.unpack_from("<I", buf, base + 16)
    off = base + 32
    changed = 0
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", buf, off)
        if cmd == LC_BUILD_VERSION:
            platform, = struct.unpack_from("<I", buf, off + 8)
            if platform == old:
                struct.pack_into("<I", buf, off + 8, new)
                changed += 1
            elif platform != new:
                sys.exit(f"unexpected platform {platform} at offset {off}")
        off += size
    return changed


def patch_archive(buf, old, new):
    off, changed = 8, 0
    while off + 60 <= len(buf):
        header = buf[off:off + 60]
        name = header[:16].decode("ascii").strip()
        size = int(header[48:58].decode("ascii").strip())
        data = off + 60
        name_len = int(name[3:]) if name.startswith("#1/") else 0
        changed += patch_macho(buf, data + name_len, old, new)
        off = data + size + (size & 1)
    return changed


def main():
    path, old, new = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    with open(path, "rb") as f:
        buf = bytearray(f.read())
    if buf.startswith(b"!<arch>\n"):
        changed = patch_archive(buf, old, new)
    else:
        changed = patch_macho(buf, 0, old, new)
    with open(path, "wb") as f:
        f.write(buf)
    print(f"{path}: {changed} load commands")
    sys.exit(0 if changed else 1)


main()
