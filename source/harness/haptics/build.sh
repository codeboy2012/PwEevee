#!/bin/sh
# Builds the Music Haptics analyzer harness for the Mac: SGMusicAnalyzer.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation -framework AudioToolbox \
    main.m ../../tweak/Sources/Shared/Haptics/SGMusicAnalyzer.m -o build/haptics
echo "built build/haptics"
