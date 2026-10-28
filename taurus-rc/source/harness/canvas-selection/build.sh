#!/bin/sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../../tweak/Sources
mkdir -p "$HERE/build"
THEOS=${THEOS:-$HOME/theos}
"$THEOS/bin/logos.pl" -c generator=internal "${PLAYER_STATE_SOURCE:-$SRC/Shared/Player/PlayerState.x}" > "$HERE/build/PlayerState.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -target arm64-apple-ios26.0-simulator -fobjc-arc -isysroot "$SDK" \
    -I"$SRC" -I"$SRC/Shared/AnimatedArtwork" -framework Foundation -framework UIKit \
    "$HERE/main.m" "${LOCK_SCREEN_STYLE_SOURCE:-$SRC/Shared/AnimatedArtwork/LockScreenStyle.m}" "$SRC/Core/SGPrefs.m" \
    -o "$HERE/build/canvas-selection"
xcrun simctl spawn booted "$HERE/build/canvas-selection"

xcrun clang -target arm64-apple-ios26.0-simulator -fobjc-arc -isysroot "$SDK" \
    -I"$SRC" -I"$HERE/build" -I"$SRC/Shared/Player" -framework Foundation -framework UIKit -framework AVFoundation \
    -framework CoreGraphics -framework CoreMedia -framework CoreVideo \
    "$HERE/motion.m" "$SRC/Shared/AnimatedArtwork/MotionSources.m" \
    "$SRC/Shared/AnimatedArtwork/SGMotionFollower.m" "$SRC/Shared/AnimatedArtwork/SGMotionClip.m" \
    "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Core/SGPrefs.m" \
    -o "$HERE/build/canvas-motion"
xcrun simctl spawn booted "$HERE/build/canvas-motion"
