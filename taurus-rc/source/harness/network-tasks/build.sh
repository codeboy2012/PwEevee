#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
THEOS=${THEOS:-$HOME/theos}
mkdir -p "$HERE/build"
"$THEOS/bin/logos.pl" -c generator=internal "${ADNETWORK_SOURCE:-$SRC/Shared/AdBlock/AdNetwork.x}" > "$HERE/build/AdNetwork.m"
python3 - "$HERE/build/AdNetwork.m" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1])
s, count = re.subn(r'static __attribute__\(\(constructor\)\) void _logosLocalCtor_\w+\([^)]*\)',
                  'static void SGTestInstallHooks(void)', p.read_text())
assert count == 1
p.write_text(s)
PY
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -target arm64-apple-ios26.0-simulator -fobjc-arc -isysroot "$SDK" \
    -I"$SRC" -I"$SRC/Shared/AdBlock" -I"$HERE/build" \
    -framework Foundation -framework UIKit -framework AVFoundation \
    "$HERE/main.m" -o "$HERE/build/network-tasks"
xcrun simctl spawn booted "$HERE/build/network-tasks"
