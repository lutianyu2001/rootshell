#!/usr/bin/env python3
"""Rename the macOS-only libSystem imports of a thin x86_64 Mach-O file (a
static archive's members, or a dylib) to the names the iOS Simulator has.

usage: macho_imports.py <FILE> <libSystem.B.tbd>

x86_64 macOS headers select variants such as _opendir$INODE64. Code built
for Mac Catalyst imports them, but the iOS Simulator's libSystem exports only
_opendir (64-bit inodes are the iOS default, so it is the same function). An
undefined symbol "<base>$<suffix>" the tbd does not list, whose <base> it does
list, is renamed to <base>. Variants the tbd lists (_realpath$DARWIN_EXTSN)
stay. Names are shortened in place, so the file keeps its size:

- symbol tables: the string is cut short with NULs;
- chained fixups: the import's name in the symbol pool, likewise;
- dyld info bind opcodes, which hold names inline: each stream is re-encoded
  with the shorter names; a regular or weak stream is padded with DONE at its
  end, a lazy stream after the DONE of each shortened record, because the stub
  helpers point at each lazy record's start.

Prints each rename.
"""
import re
import struct
import sys

LC_SYMTAB, LC_DYLD_INFO, LC_DYLD_INFO_ONLY, LC_DYLD_CHAINED_FIXUPS = 0x2, 0x22, 0x80000022, 0x80000034
MH_MAGIC_64 = 0xFEEDFACF


def cstring(buf, off):
    end = buf.index(0, off)
    return buf[off:end].decode("latin-1"), end + 1


def uleb(buf, off):
    while buf[off] & 0x80:
        off += 1
    return off + 1


class Fixer:
    def __init__(self, tbd_text):
        self.exported = set(re.findall(r"_[A-Za-z0-9_$.]+", tbd_text))
        self.renames = {}

    def target(self, name):
        if name in self.renames:
            return self.renames[name]
        new = None
        cut = name.find("$", 1)
        if name.startswith("_") and cut > 1 and name not in self.exported and name[:cut] in self.exported:
            new = name[:cut]
        self.renames[name] = new
        return new

    def shorten(self, buf, off):
        """Cut the NUL-terminated name at off short, if it needs renaming."""
        name, end = cstring(buf, off)
        new = self.target(name)
        if new:
            buf[off:end - 1] = new.encode() + bytes(len(name) - len(new))

    def macho(self, buf, base):
        magic, = struct.unpack_from("<I", buf, base)
        if magic != MH_MAGIC_64:
            return
        ncmds, = struct.unpack_from("<I", buf, base + 16)
        off = base + 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", buf, off)
            if cmd == LC_SYMTAB:
                self.symtab(buf, base, *struct.unpack_from("<IIII", buf, off + 8))
            elif cmd == LC_DYLD_CHAINED_FIXUPS:
                self.chained(buf, base + struct.unpack_from("<I", buf, off + 8)[0])
            elif cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
                f = struct.unpack_from("<10I", buf, off + 8)
                for (o, n), lazy in (((f[2], f[3]), False), ((f[4], f[5]), False), ((f[6], f[7]), True)):
                    if n:
                        buf[base + o:base + o + n] = self.opcodes(bytes(buf[base + o:base + o + n]), lazy)
            off += size

    def symtab(self, buf, base, symoff, nsyms, stroff, strsize):
        for i in range(nsyms):
            strx, ntype = struct.unpack_from("<IB", buf, base + symoff + 16 * i)
            if ntype & 0xE0 == 0 and ntype & 0x0E == 0 and ntype & 0x01 and strx:  # no stab, N_UNDF, N_EXT
                self.shorten(buf, base + stroff + strx)

    def chained(self, buf, header):
        _, _, imports, symbols, count, fmt, sym_fmt = struct.unpack_from("<7I", buf, header)
        if sym_fmt != 0:
            sys.exit("compressed chained-fixup symbols are not handled")
        for i in range(count):
            if fmt == 1:
                name_off = struct.unpack_from("<I", buf, header + imports + 4 * i)[0] >> 9
            elif fmt == 2:
                name_off = struct.unpack_from("<I", buf, header + imports + 8 * i)[0] >> 9
            elif fmt == 3:
                name_off = struct.unpack_from("<Q", buf, header + imports + 16 * i)[0] >> 32
            else:
                sys.exit(f"unknown chained-fixup import format {fmt}")
            self.shorten(buf, header + symbols + name_off)

    def opcodes(self, stream, lazy):
        out, pad, i = bytearray(), 0, 0
        while i < len(stream):
            op = stream[i] & 0xF0
            if op == 0x40:  # SET_SYMBOL_TRAILING_FLAGS_IMM
                name, nxt = cstring(stream, i + 1)
                new = self.target(name) or name
                out += stream[i:i + 1] + new.encode() + b"\0"
                pad += len(name) - len(new)
                i = nxt
                continue
            if op in (0x20, 0x60, 0x70, 0x80, 0xA0):  # one (S/U)LEB operand
                end = uleb(stream, i + 1)
            elif op == 0xC0:  # two ULEBs
                end = uleb(stream, uleb(stream, i + 1))
            elif op == 0xD0 and stream[i] & 0x0F == 0:  # THREADED, SET_BIND_ORDINAL_TABLE_SIZE_ULEB
                end = uleb(stream, i + 1)
            else:
                end = i + 1
            out += stream[i:end]
            if lazy and op == 0x00:
                out += bytes(pad)
                pad = 0
            i = end
        out += bytes(pad)
        assert len(out) == len(stream)
        return bytes(out)


def main():
    path, tbd = sys.argv[1], sys.argv[2]
    with open(tbd) as f:
        fixer = Fixer(f.read())
    with open(path, "rb") as f:
        buf = bytearray(f.read())
    if buf.startswith(b"!<arch>\n"):
        off = 8
        while off + 60 <= len(buf):
            name = buf[off:off + 16].decode("ascii").strip()
            size = int(buf[off + 48:off + 58].decode("ascii").strip())
            name_len = int(name[3:]) if name.startswith("#1/") else 0
            fixer.macho(buf, off + 60 + name_len)
            off += 60 + size + (size & 1)
    else:
        fixer.macho(buf, 0)
    with open(path, "wb") as f:
        f.write(buf)
    for old, new in sorted(fixer.renames.items()):
        if new:
            print(f"  {old} -> {new}")


main()
