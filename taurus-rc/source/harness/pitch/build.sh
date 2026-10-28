#!/bin/sh
# Builds the pitch harness for the Mac: SGTimePitch.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
mkdir -p build
xcrun clang -fobjc-arc -O2 -I ../../tweak/Sources -framework Foundation -framework AudioToolbox \
    main.m ../../tweak/Sources/Shared/Player/SGTimePitch.m -o build/pitch
