#!/usr/bin/env python3
"""Adds an LC_LOAD_WEAK_DYLIB to a thin 64-bit Mach-O, in place, if it is not there yet.

  scripts/insert-dylib.py <binary> <install name, e.g. @rpath/X.dylib>

The command goes into the free space between the load commands and the first section, which
every Xcode-linked binary leaves. The signature is invalidated; the IPA is signed again later.
"""
import struct
import sys

LC_LOAD_WEAK_DYLIB = 0x80000018
LC_SEGMENT_64 = 0x19

path, name = sys.argv[1:3]
with open(path, "r+b") as f:
    data = bytearray(f.read())
    magic, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != 0xFEEDFACF:
        sys.exit(f"{path}: not a thin 64-bit Mach-O")

    first_section = len(data)
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd in (0xC, 0x18, 0x1F) and data[off + 24:off + cmdsize].split(b"\0")[0] == name.encode():
            print(f"    {name} already loaded")
            sys.exit(0)
        if cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            for s in range(nsects):
                sect_off = struct.unpack_from("<I", data, off + 72 + s * 80 + 48)[0]
                if sect_off:
                    first_section = min(first_section, sect_off)
        off += cmdsize

    raw = name.encode() + b"\0"
    cmdsize = (24 + len(raw) + 7) & ~7
    end = 32 + sizeofcmds
    if end + cmdsize > first_section or any(data[end:end + cmdsize]):
        sys.exit(f"{path}: no room for another load command")

    cmd = struct.pack("<IIIIII", LC_LOAD_WEAK_DYLIB, cmdsize, 24, 2, 0x10000, 0x10000) + raw
    data[end:end + cmdsize] = cmd.ljust(cmdsize, b"\0")
    struct.pack_into("<II", data, 16, ncmds + 1, sizeofcmds + cmdsize)
    f.seek(0)
    f.write(data)
print(f"    {name} added")
