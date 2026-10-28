#!/usr/bin/env python3
"""Generate extension identity/version from the containing app, including a pipeline ID override."""
import plistlib
import sys
from pathlib import Path


def make_plist(host, bundle_override=""):
    bundle = bundle_override or host["CFBundleIdentifier"]
    return {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleDisplayName": "Open in Spotify",
        "CFBundleExecutable": "PwEeveeOpenSpotify",
        "CFBundleIdentifier": bundle + ".PwEeveeOpenSpotify",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "PwEeveeOpenSpotify",
        "CFBundlePackageType": "XPC!",
        "CFBundleShortVersionString": host["CFBundleShortVersionString"],
        "CFBundleVersion": host["CFBundleVersion"],
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "MinimumOSVersion": "16.1",
        "UIDeviceFamily": [1, 2],
        "NSExtension": {
            "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
            "NSExtensionPrincipalClass": "PwEeveeSafariWebExtensionHandler",
        },
    }


if __name__ == "__main__":
    with Path(sys.argv[1]).open("rb") as source:
        host = plistlib.load(source)
    with Path(sys.argv[2]).open("wb") as target:
        plistlib.dump(make_plist(host, sys.argv[3] if len(sys.argv) > 3 else ""), target)
