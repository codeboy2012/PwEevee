#!/bin/sh
# Runs Shared/LyricsSources/SpicyLyrics.m against replies packed by Spicy Lyrics' own packer.
# Needs bun, and clones the extension the first time to borrow that packer.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../../tweak/Sources
OUT=$HERE/build
mkdir -p "$OUT"

[ -d "$OUT/spicy-lyrics" ] || git clone --depth 1 https://github.com/Spikerko/spicy-lyrics.git "$OUT/spicy-lyrics"
(cd "$HERE" && bun run pack.ts > "$OUT/fixtures.json")

clang -fobjc-arc -g -O0 -o "$OUT/spicytest" \
    "$HERE/main.m" "$HERE/stubs.m" "$SRC/Shared/LyricsSources/SpicyLyrics.m" \
    -I"$HERE/include" -I"$SRC" -I"$SRC/Shared/LyricsSources" \
    -framework Foundation

cd "$OUT" && ./spicytest
