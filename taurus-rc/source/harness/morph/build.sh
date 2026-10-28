#!/bin/sh
set -e
SRC=/Users/vojta/Documents/quick/custom_spotify/custom_spotify/tweak/Sources
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/MorphHarness.app"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Player/PlayerMorph.x" > "$OUT/gen/PlayerMorph.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Player" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$OUT/gen/PlayerMorph.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$OUT/MorphHarness.app/MorphHarness"
cat > "$OUT/MorphHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MorphHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.morphharness</string>
<key>CFBundleName</key><string>MorphHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign -f -s - "$OUT/MorphHarness.app" >/dev/null 2>&1
echo "built $OUT/MorphHarness.app"
