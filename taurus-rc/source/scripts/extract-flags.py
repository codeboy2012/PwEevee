#!/usr/bin/env python3
"""Write tweak/Sources/Shared/Flags/SGFlagList.m, the table of Spotify's remote-config flags, from a decrypted IPA.

Every generated SPT*ImplProperties class reads its flags in initWithConfigurationProvider: through
boolValueForId:defaultValue:, intValueForId:lower:upper:defaultValue: or
enumValueForId:values:defaultValue:. The keys are cstrings, the defaults are immediates in the
initializer (or in the small outlined helpers it calls), so a linear walk over the arm64 code with
the leaf calls inlined recovers key, type and default for nearly every flag.

    scripts/extract-flags.py ipa/com.spotify.client-9.1.78-Decrypted.ipa
"""
import plistlib, re, struct, subprocess, sys, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = 0x100000000
SELS = {'boolValueForId:defaultValue:': 'Bool', 'intValueForId:lower:upper:defaultValue:': 'Int',
        'enumValueForId:values:defaultValue:': 'Enum'}


def extract_binary(ipa):
    tmp = Path(tempfile.mkdtemp())
    with zipfile.ZipFile(ipa) as z:
        name = next(n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Spotify', n))
        z.extract(name, tmp)
    return tmp / name


def segments(binary):
    text = subprocess.run(['otool', '-l', binary], capture_output=True, text=True).stdout
    segs = []
    for m in re.finditer(r'segname (\S+)\n\s+vmaddr 0x([0-9a-f]+)\n\s+vmsize 0x[0-9a-f]+\n\s+fileoff (\d+)\n\s+filesize (\d+)', text):
        segs.append((int(m.group(2), 16), int(m.group(3)), int(m.group(4))))
    return segs


class Binary:
    def __init__(self, path):
        self.data = open(path, 'rb').read()
        self.segs = segments(path)
        self.keys = {}
        for line in subprocess.run(['strings', '-t', 'x', '-n', '8', path], capture_output=True, text=True).stdout.splitlines():
            m = re.match(r'\s*([0-9a-f]+) (ios-[a-z0-9-]+\.[A-Za-z0-9_.-]+)$', line)
            if m:
                self.keys[BASE + int(m.group(1), 16)] = m.group(2)
        self.thunks = []
        for line in subprocess.run(['nm', '-n', path], capture_output=True, text=True).stdout.splitlines():
            m = re.match(r'^([0-9a-f]+) [tT] -\[\S+ initWithConfigurationProvider:\]$', line)
            if m:
                self.thunks.append(int(m.group(1), 16))

    def offset(self, addr):
        for vm, off, size in self.segs:
            if vm <= addr < vm + size:
                return addr - vm + off
        return None

    def insn(self, addr):
        return struct.unpack_from('<I', self.data, addr - BASE)[0]

    def cstring(self, addr):
        off = self.offset(addr)
        if off is None:
            return None
        end = self.data.find(b'\0', off, off + 256)
        s = self.data[off:end] if end > 0 else b''
        return s.decode('ascii') if s and all(32 <= c < 127 for c in s) else None

    # A selector reference is a chained-fixup pointer: the low 36 bits hold the target.
    def selector(self, addr):
        off = self.offset(addr)
        if off is None:
            return None
        target = struct.unpack_from('<Q', self.data, off)[0] & 0xFFFFFFFFF
        return self.cstring(target + BASE if target < BASE else target)


def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def bitmask(i):
    n, immr, imms, sf = (i >> 22) & 1, (i >> 16) & 0x3f, (i >> 10) & 0x3f, (i >> 31) & 1
    if n:
        length = 6
    else:
        ni = (~imms) & 0x3f
        length = ni.bit_length() - 1
        if length < 0:
            return None
    esize = 1 << length
    levels = esize - 1
    s, r = imms & levels, immr & levels
    welem = (1 << (s + 1)) - 1
    elem = ((welem >> r) | (welem << (esize - r))) & ((1 << esize) - 1)
    v = 0
    for _ in range((64 if sf else 32) // esize):
        v = (v << esize) | elem
    return v


def decode(i, pc):
    if (i & 0x9F000000) == 0x90000000:
        return ('adrp', i & 31, (pc & ~0xfff) + (sext((((i >> 5) & 0x7FFFF) << 2) | ((i >> 29) & 3), 21) << 12))
    if (i & 0x7F800000) in (0x11000000, 0x51000000):
        imm = ((i >> 10) & 0xfff) << (12 if (i >> 22) & 1 else 0)
        return ('add', i & 31, (i >> 5) & 31, imm if (i & 0x7F800000) == 0x11000000 else -imm)
    width = 0xffffffffffffffff if i >> 31 else 0xffffffff
    if (i & 0x7F800000) == 0x52800000:
        return ('movz', i & 31, (((i >> 5) & 0xffff) << (((i >> 21) & 3) * 16)) & width)
    if (i & 0x7F800000) == 0x12800000:
        return ('movz', i & 31, ~(((i >> 5) & 0xffff) << (((i >> 21) & 3) * 16)) & width)
    if (i & 0x7F800000) == 0x72800000:
        return ('movk', i & 31, ((i >> 5) & 0xffff) << (((i >> 21) & 3) * 16), ((i >> 21) & 3) * 16)
    if (i & 0x7FE0FFE0) == 0x2A0003E0:
        return ('mov', i & 31, (i >> 16) & 31)
    if (i & 0x7F800000) == 0x32000000:
        return ('orri', i & 31, (i >> 5) & 31, bitmask(i))
    if (i & 0xFFC00000) == 0xF9400000:
        return ('ldr', i & 31, (i >> 5) & 31, ((i >> 10) & 0xfff) << 3)
    if (i & 0xFC000000) == 0x94000000:
        return ('bl', pc + sext(i & 0x3FFFFFF, 26) * 4)
    if (i & 0xFC000000) == 0x14000000:
        return ('b', pc + sext(i & 0x3FFFFFF, 26) * 4)
    if i == 0xD65F03C0:
        return ('ret',)
    if (i & 0xFFFFFC1F) == 0xD61F0000:
        return ('br',)
    return ('other',)


class Walker:
    def __init__(self, binary):
        self.bin = binary
        self.regs = {}
        self.pending = None
        self.found = []
        self.steps = 0

    def is_leaf(self, addr):
        for _ in range(40):
            i = self.bin.insn(addr)
            d = decode(i, addr)
            if (i & 0xFFC07FFF) in (0xA9007BFD, 0xA9807BFD) or d[0] == 'br':
                return False
            if d[0] in ('ret', 'b'):
                return True
            addr += 4
        return False

    def call(self):
        regs, keys = self.regs, self.bin.keys
        sel = regs.get(1)
        if isinstance(sel, tuple) and sel[1] in SELS:
            nums = [v if isinstance(v, int) else None for v in (regs.get(3), regs.get(4), regs.get(5))]
            if self.pending:
                self.found.append((self.pending, SELS[sel[1]], *nums))
            self.pending = None
        else:
            # Swift passes the key to the bridge as (string address - 0x20) | immortal bit.
            for v in regs.values():
                if isinstance(v, int) and (v in keys or v + 0x20 in keys):
                    self.pending = keys.get(v) or keys.get(v + 0x20)
                    break
        self.regs = {r: v for r, v in regs.items() if r >= 19}

    def run(self, pc, depth=0):
        regs = self.regs
        while self.steps < 8000:
            self.steps += 1
            d = decode(self.bin.insn(pc), pc)
            op = d[0]
            if op == 'adrp':
                regs[d[1]] = d[2]
            elif op == 'add':
                v = regs.get(d[2])
                regs[d[1]] = v + d[3] if isinstance(v, int) else None
            elif op == 'movz':
                regs[d[1]] = d[2]
            elif op == 'movk':
                v = regs.get(d[1])
                if isinstance(v, int):
                    regs[d[1]] = (v & ~(0xffff << d[3])) | d[2]
            elif op == 'mov':
                regs[d[1]] = 0 if d[2] == 31 else regs.get(d[2])
            elif op == 'orri':
                regs[d[1]] = d[3] if d[2] == 31 else regs.get(d[2])
            elif op == 'ldr':
                v = regs.get(d[2])
                name = self.bin.selector(v + d[3]) if isinstance(v, int) else None
                regs[d[1]] = ('sel', name) if name else None
            elif op in ('bl', 'b'):
                if op == 'b' and depth == 0:
                    return
                if depth < 3 and self.is_leaf(d[1]):
                    self.run(d[1], depth + 1)
                    regs = self.regs
                else:
                    self.call()
                    regs = self.regs
                if op == 'b':
                    return
            elif op == 'ret':
                return
            elif op == 'br':
                self.call()
                return
            pc += 4


def signed(v):
    return v - (1 << 64) if v >= 1 << 63 else v


def swift_init(binary, thunk):
    target = None
    for _ in range(40):
        d = decode(binary.insn(thunk), thunk)
        if d[0] == 'bl':
            target = d[1]
        if d[0] == 'ret':
            break
        thunk += 4
    return target


def main():
    ipa = Path(sys.argv[1])
    binary = Binary(extract_binary(ipa))
    flags = {}
    for thunk in binary.thunks:
        target = swift_init(binary, thunk)
        if not target:
            continue
        walker = Walker(binary)
        walker.run(target)
        for key, kind, a, b, c in walker.found:
            if kind == 'Bool':
                flags[key] = ('Bool', a or 0, 0, 0)
            elif kind == 'Int':
                flags[key] = ('Int', c or 0, a or 0, b or 0)
            else:
                flags[key] = ('Enum', 0, 0, 0)
    for key in binary.keys.values():
        flags.setdefault(key, ('Unknown', 0, 0, 0))
    with zipfile.ZipFile(ipa) as z:
        info = next(n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n))
        version = plistlib.loads(z.read(info))['CFBundleShortVersionString']
    lines = [f'// Generated by scripts/extract-flags.py from Spotify {version}. Do not edit.',
             '#import "Flags.h"', '', 'const SGFlagDef SGFlagTable[] = {']
    for key in sorted(flags):
        kind, value, lower, upper = flags[key]
        lines.append(f'    {{"{key}", SGFlag{kind}, {signed(value)}, {signed(lower)}, {signed(upper)}}},')
    lines += ['};', 'const NSUInteger SGFlagCount = sizeof(SGFlagTable) / sizeof(*SGFlagTable);', '']
    out = ROOT / 'tweak/Sources/Shared/Flags/SGFlagList.m'
    out.write_text('\n'.join(lines))
    typed = sum(1 for f in flags.values() if f[0] != 'Unknown')
    print(f'{out.relative_to(ROOT)}: {len(flags)} flags, {typed} with a type and default')


if __name__ == '__main__':
    main()
