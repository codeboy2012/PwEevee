#!/bin/sh
# Package the network-tasks runner as a simulator .app, install it on <udid> and launch it
# with its console attached.
#
# build.sh's default path (`simctl spawn booted`) runs the same binary without an app
# container; this is the install/launch path, so a run can be shown to come from an
# installed bundle rather than a bare process.
#
#   sh sim-app.sh <simulator-udid>
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
UDID="${1:?usage: $0 <simulator-udid>}"
BUNDLE=com.pweevee.networktasks
APP="$HERE/build/NetworkTasks.app"

sh "$HERE/build.sh" --no-run
rm -rf "$APP"
mkdir -p "$APP"
cp "$HERE/build/network-tasks" "$APP/NetworkTasks"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>NetworkTasks</string>
    <key>CFBundleIdentifier</key><string>com.pweevee.networktasks</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>NetworkTasks</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>3.1.6.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    <key>MinimumOSVersion</key><string>16.0</string>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>LSRequiresIPhoneOS</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch --console-pty "$UDID" "$BUNDLE"
