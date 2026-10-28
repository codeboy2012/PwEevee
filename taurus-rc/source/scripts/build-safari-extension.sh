#!/usr/bin/env bash
# Build the Safari web extension from source. No downloaded executable is reused.
# Usage: scripts/build-safari-extension.sh <host Info.plist> <output directory>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_PLIST="${1:?usage: $0 <host Info.plist> <output directory>}"
OUT="${2:?usage: $0 <host Info.plist> <output directory>}"
NAME=PwEeveeOpenSpotify
APPEX="$OUT/$NAME.appex"
xcrun --sdk iphoneos --find clang >/dev/null 2>&1 || {
  echo "Safari extension requires full Xcode with an iPhoneOS SDK. Select it with xcode-select or DEVELOPER_DIR." >&2
  exit 1
}
mkdir -p "$OUT"
# Only remove this script's generated bundle, never the caller's output directory.
rm -rf "$APPEX"
mkdir -p "$APPEX"
cp -R "$ROOT/extension/OpenSpotify/Resources/." "$APPEX/"
python3 "$ROOT/scripts/safari-extension-plist.py" "$HOST_PLIST" "$APPEX/Info.plist" "${BUNDLE_ID:-}"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.1 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -fobjc-arc -fapplication-extension -Os -framework Foundation -framework SafariServices -framework UIKit \
  -Wl,-e,_NSExtensionMain -o "$APPEX/$NAME" "$ROOT/extension/OpenSpotify/SafariWebExtensionHandler.m"
codesign --force --sign - "$APPEX"
echo "    $APPEX (ad-hoc signed; the IPA signer must re-sign the embedded extension)"
