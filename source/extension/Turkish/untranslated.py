#!/usr/bin/env python3
"""Lists the English strings in the tweak's dylibs that tr.json does not translate yet.

    extension/Turkish/untranslated.py <spotifyglass.dylib> [SpotifyAudioProbe.dylib ...]

The strings are read out of the built binaries (__TEXT,__cstring and __ustring), so the list
matches what the build really shows. It is a candidate list: log lines and identifiers are filtered
out by shape, and whatever is left that is not on screen simply stays out of tr.json.
"""
import json
import os
import re
import struct
import sys

TABLE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tr.json")


def sections(path):
    data = open(path, "rb").read()
    if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
        sys.exit(f"{path}: not a thin arm64 Mach-O")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off, found = 32, {}
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            s = off + 72
            for _ in range(nsects):
                name = data[s:s + 16].rstrip(b"\0").decode()
                seg = data[s + 16:s + 32].rstrip(b"\0").decode()
                _, sz, fileoff = struct.unpack_from("<QQI", data, s + 32)
                found[(seg, name)] = data[fileoff:fileoff + sz]
                s += 80
        off += size
    return found


def strings(path):
    sect = sections(path)
    for raw in sect.get(("__TEXT", "__cstring"), b"").split(b"\0"):
        try:
            yield raw.decode("utf-8")
        except UnicodeDecodeError:
            pass
    yield from sect.get(("__TEXT", "__ustring"), b"").decode("utf-16-le", "replace").split("\0")


NOT_TEXT = re.compile(r"^(https?:|/|_|@|\$|\^|\{|\[|<|com\.|spotify|SG[A-Z]|SPT|UI[A-Z]|NS[A-Z]|T@)"
                      r"|\.(png|json|plist|dylib|m4a|wav|mp3|bnk|ttf)$|::|->|==|\w+\.\w+\.\w+"
                      r"|^[a-z]+[A-Z]\w*:?$|^[a-z_]+$|^[A-Za-z]+:([A-Za-z]+:)*$")
LOG_LINE = re.compile(r"^[a-z][\w \-/]{0,30}: ")


def looks_like_text(s):
    t = s.strip()
    if len(t) < 2 or not re.search(r"[A-Za-z]{2}", t) or NOT_TEXT.search(t) or LOG_LINE.match(t):
        return False
    if re.fullmatch(r"[A-Z][a-z]+[A-Z]\w+", t):  # CamelCase identifier
        return False
    return " " in t or bool(re.fullmatch(r"[A-Z][a-zA-Z]+[.!?…]?", t))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.strip())
    table = json.load(open(TABLE, encoding="utf-8"))
    seen = set()
    for path in sys.argv[1:]:
        seen.update(s for s in strings(path) if looks_like_text(s))
    missing = sorted(s for s in seen if s not in table)
    for s in missing:
        print(json.dumps(s, ensure_ascii=False))
    print(f"{len(missing)} of {len(seen)} candidate strings are not in tr.json", file=sys.stderr)


if __name__ == "__main__":
    main()
