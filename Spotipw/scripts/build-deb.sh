#!/usr/bin/env bash
# ============================================================
# build-deb.sh — the unified PwEevee Debian package
# ============================================================
#
#   PwEevee_0.22.0-alpha.2_iphoneos-arm.deb
#
# Contents (the proven jailbreak layout, audited in docs/UNIFICATION-AUDIT.md §3):
#   var/jb/Library/MobileSubstrate/DynamicLibraries/
#       spotifyglass.dylib          the unified tweak (SpoTi.pw v0.22.0 + the PwEevee Eevee
#                                   integration; EeveeSpotify v6.6.8 rides in the host IPA — see
#                                   docs/DEB.md for how the customization workflow pairs the two)
#       spotifyglass.plist          MobileSubstrate filter: com.spotify.client
#   var/jb/Library/Application Support/EeveeSpotify.bundle/
#                                   Eevee's localized strings + resolveconfiguration.bnk (the payload's
#                                   BundleHelper searches this path first; the IPA-injection route
#                                   puts the same bundle inside the app instead)
#   DEBIAN/control                  generated from tweak/pweevee-control
#
# The 142 app-icon PNGs deliberately do NOT ship: Eevee's icon picker (and the PwEevee integration's
# SGEeveeIconsPage) reads CFBundleAlternateIcons from the app's Info.plist and applies icons with
# setAlternateIconName — iOS loads the PNGs from the app root of the installed app, never from
# var/jb/share. The host IPA already carries all 142 (see docs/DEB.md, customization workflow).
#
# Nothing else ships: the iOS system frameworks spotifyglass links are on the device. Orion and
# EeveeSwiftProtobuf stay where the audited components put them: frameworks of the host app, placed by
# the customization workflow (docs/DEB.md), not by this deb — installing them under var/jb would leave
# Spotify's dyld without a path that resolves.
#
# Prerequisites (the same ones scripts/pipeline.sh needs):
#   Theos in $THEOS (default ~/theos) with an iPhoneOS 26+ SDK, gmake, ldid, xz, perl,
#   and tweak/Sources/Shared/Flags/SGFlagList.m (generated from Spotify's binary; the release
#   workflow restores it from the SG_FLAG_LIST secret, Spotipw/.github/workflows/release.yml).
#
#   scripts/build-deb.sh [-o out.deb]
set -euo pipefail
umask 022

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

VERSION="$(tr -d '\r\n' < version.txt)-alpha.2"
OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
OUT="${OUT:-dist/PwEevee_${VERSION}_iphoneos-arm.deb}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing $1 -> $2" >&2; exit 1; }; }
need gmake "gmake"
need ldid "ldid"
need xz "xz"
need perl "perl"

THEOS="${THEOS:-$HOME/theos}"
[ -d "$THEOS" ] || { echo "no Theos at $THEOS (set THEOS=...)" >&2; exit 1; }
[ -f tweak/Sources/Shared/Flags/SGFlagList.m ] || {
  echo "tweak/Sources/Shared/Flags/SGFlagList.m is missing; generate it from the Spotify IPA:" >&2
  echo "  ./scripts/extract-flags.py <decrypted Spotify 9.1.76 .ipa>" >&2
  exit 1
}

WORK="PwEvevee/build-system/_work/deb"
STAGE="$WORK/stage"
rm -rf "$WORK"
mkdir -p "$STAGE/DEBIAN" \
         "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries" \
         "$STAGE/var/jb/Library/Application Support/EeveeSpotify.bundle"

# ---------------- 1. build the unified tweak ----------------
echo "==> building the unified tweak (Theos)"
MAKELEVEL=0 gmake -C tweak clean package FINALPACKAGE=1 > /dev/null
TWEAK_DEB="$(ls -t tweak/packages/com.spotipw_*.deb 2>/dev/null | head -1 || true)"
[ -n "$TWEAK_DEB" ] || { echo "the tweak build produced no .deb in tweak/packages/" >&2; exit 1; }
echo "    tweak deb: $TWEAK_DEB"

# Take the built dylib and its filter out of Theos' deb. The tweak's own control is rootful
# (bare /Library/MobileSubstrate paths), so find the members wherever this Theos scheme put them
# instead of assuming the var/jb rootless prefix.
perl scripts/ar-extract.pl "$TWEAK_DEB" data.tar.lzma "$WORK/data.tar.lzma"
xz -dc --format=lzma "$WORK/data.tar.lzma" > "$WORK/data.tar"
DYLIB_PATH=$(tar tf "$WORK/data.tar" | grep '/spotifyglass\.dylib$' | head -1)
PLIST_PATH=$(tar tf "$WORK/data.tar" | grep '/spotifyglass\.plist$' | head -1)
[ -n "$DYLIB_PATH" ] || { echo "the tweak deb has no spotifyglass.dylib" >&2; exit 1; }
[ -n "$PLIST_PATH" ] || { echo "the tweak deb has no spotifyglass.plist" >&2; exit 1; }
tar xf "$WORK/data.tar" -C "$WORK" "$DYLIB_PATH" "$PLIST_PATH"
rm "$WORK/data.tar" "$WORK/data.tar.lzma"
mkdir -p "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries"
mv "$WORK/$DYLIB_PATH" "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib"
mv "$WORK/$PLIST_PATH" "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist"

# The unified dylib must carry the PwEevee integration: if the built binary lacks the page's symbol
# the sources drifted and the package would ship two separate menus again.
for symbol in SGEeveeSpotifyPage SGEeveeRemoveStandaloneRow SGEeveeRestoreLyricsReplacement; do
  grep -q "$symbol" "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib" \
    || { echo "the built dylib lacks $symbol — the PwEevee integration is not in this build" >&2; exit 1; }
done
echo "    integration symbols verified"

# Fake-sign (the deb's consumer either re-signs in the customization workflow or installs on a
# jailbreak where MobileSubstrate loads it as-is); ldid keeps the pagesha consistent.
ldid -S "$STAGE/var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib"

# ---------------- 2. gather Eevee runtime resources ----------------
echo "==> gathering EeveeSpotify resources"
COMPONENT="Evevee Spotify/component"
[ -f "$COMPONENT/manifest.json" ] || { echo "Eevee component missing: $COMPONENT" >&2; exit 1; }

# The bundle the payload's BundleHelper loads its strings from.
cp -a "$COMPONENT/bundles/EeveeSpotify.bundle/." \
      "$STAGE/var/jb/Library/Application Support/EeveeSpotify.bundle/"
# (resources/ — the 142 icon PNGs — is not copied: see the header note. Icons live in the host IPA.)

# ---------------- 3. control ----------------
{
  cat tweak/pweevee-control
  echo "Installed-Size: $(du -sk "$STAGE" | cut -f1)"
} > "$STAGE/DEBIAN/control"

# ---------------- 4. package (deterministic; the writer the project's deb tests already pin) ----
echo "==> packaging $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
perl PwEvevee/build-system/package/make-deb.pl "$STAGE" "$STAGE/DEBIAN" "$OUT"

# ---------------- 5. validate ----------------
perl PwEvevee/build-system/tests/pweevee-deb-tests.pl "$OUT"

# ---------------- 6. report ----------------
SIZE=$(wc -c < "$OUT" | tr -d ' ')
SHA=$(sha256sum "$OUT" | cut -d' ' -f1)
cat > "${OUT%.deb}.build-report.txt" <<REPORT
PwEevee ${VERSION} build report
  package:   $(basename "$OUT")
  size:      ${SIZE} bytes
  sha256:    ${SHA}
  built:     $(date -u +%Y-%m-%dT%H:%M:%SZ)
  host:      Spotify 9.1.76 only (the DEBIAN/control Description says the same)
  contains:  unified tweak + MobileSubstrate filter + EeveeSpotify.bundle (icons ride the host IPA)
  pairs with: EeveeSpotify v6.6.8 frameworks+dylib in the host IPA (docs/DEB.md)
REPORT
echo "==> done: $OUT"
echo "    size ${SIZE} bytes, sha256 ${SHA}"
