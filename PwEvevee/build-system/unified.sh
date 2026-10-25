#!/usr/bin/env bash
# ============================================================
# unified.sh — the ONE authoritative build pipeline
# ============================================================
#
#   decrypted Spotify IPA (input)
#        ↓  prepare          unzip, drop stale output, read version
#        ↓  merge            spoti.pw + EeveeSpotify payloads into Spotify.app
#        ↓  resolve          dependency resolution (duplicates = hard failure)
#        ↓  inject           LC_LOAD_DYLIB for every declared load command
#        ↓  validate         Mach-O + filesystem structure
#        ↓  package          deterministic store-only IPA
#        ↓  manifest         build-manifest.json next to the output IPA
#
#   PwEvevee/build-system/unified.sh <decrypted.ipa> [-o dist/out.ipa] [--watch]
#
# No manual file editing between steps; rerunnable; stale-output safe.
#
# Environment:
#   PWEEVEE_KEEP_WORK=1    keep the per-run _work workspace after exit (debug)
#   PWEEVEE_WORK_TENANT=N  tenant id under _work (default: this shell's PID)
set -euo pipefail
umask 022

ORIG_PWD="$(pwd)"
BS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REPO="$(cd "$BS/../.." && pwd)"
cd "$REPO"

IN="" OUT="" OUT_GIVEN=0 WATCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; OUT_GIVEN=1; shift 2 ;;
    --watch) WATCH=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { echo "usage: PwEvevee/build-system/unified.sh <decrypted Spotify .ipa> [-o dist/out.ipa] [--watch]" >&2; exit 1; }
case "$IN" in /*) ;; *) IN="$ORIG_PWD/$IN" ;; esac
[ -f "$IN" ] || { echo "no such input IPA: $IN" >&2; exit 1; }
if [ "$OUT_GIVEN" = 1 ]; then case "$OUT" in /*) ;; *) OUT="$ORIG_PWD/$OUT" ;; esac; fi

DIST="dist"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\n!! FAIL: %s\n' "$*" >&2; exit 1; }

command -v perl >/dev/null || fail "perl is required"
command -v xz    >/dev/null || fail "xz is required (apt/brew install xz)"
command -v unzip >/dev/null || fail "unzip is required"
command -v diff  >/dev/null || fail "diff is required"

# merge_dir: copy a component DIRECTORY over the staged app. The merge runs on any
# input IPA, including decrypt-day bases that already carry these directories, so an
# already-supplied directory must not nest under the old name (what 'cp -a src dst/' does).
# Three outcomes, all logged:
#   * base provides the directory and it is byte-identical to our copy → collapsed;
#   * base provides it and it DIFFERS → the base copy stays authoritative and our
#     copy is skipped (the base's runtime pairing — its own app-group dylib, tweak
#     and substrate — was shipped together, so the pipeline defers to it and
#     records the decision; resolve-deps still enforces one-copy-per-dependency);
#   * base provides nothing → ours is copied in.
merge_dir() {
  local src="${1:-}" dst="${2:-}"
  if [ -d "$dst" ]; then
    # An empty directory at the destination is a placeholder (a decrypt-day base
    # or a fixture staging the bundle structure without contents), not a
    # conflicting supply: fill it with the component's contents.
    if [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
      cp -a "$src"/. "$dst"/
      echo "    merge: $dst was an empty placeholder — filled with $src"
    elif diff -rq "$src" "$dst" >/dev/null 2>&1; then
      echo "    merge: $dst already present and identical — collapsed"
    else
      echo "    merge: $dst differs from $src — BASE-SUPPLIED, keeping the base copy (repo copy skipped)"
    fi
    return 0
  fi
  cp -a "$src" "$dst"
}

# Per-invocation workspace: the legacy $BS/_work is a FIXED path, so parallel
# builds or a crashed run would clobber/cross-del each other's trees. Move the
# per-run workspace under _work with a tenant id (default: PID), and clean it
# with an EXIT trap that preserves the original exit status.
TENANT="${PWEEVEE_WORK_TENANT:-$$}"
WORK="$BS/_work/$TENANT"
KEEP_WORK=0
case "${PWEEVEE_KEEP_WORK:-}" in 1|yes|true) KEEP_WORK=1 ;; esac

# SINGLE EXIT trap: removes ONLY this run's tenant dir. PWEEVEE_KEEP_WORK=1
# preserves it for debugging (prints the path). 'trap x EXIT; exit N' retains
# N, and a trapped INT/TERM causes bash to exit with 130/143 — never hide 1.
another_run() { kill -0 "$1" 2>/dev/null; }
if [ -e "$WORK" ]; then
  if another_run "${TENANT}"; then
    fail "workspace $WORK already exists and tenant PID $TENANT is ALIVE (another build on this tenant id?); bailing out instead of deleting it"
  fi
  rm -rf "$WORK"   # stale tree from a completed/crashed prior run of THIS tenant id
fi
mkdir -p "$WORK"
cleanup_work() { if [ "$KEEP_WORK" = 1 ]; then echo "PWEEVEE_KEEP_WORK: workspace kept at $WORK" >&2; else rm -rf "$WORK"; fi }
trap cleanup_work EXIT

step "0. prepare per-run workspace"
mkdir -p "$WORK/app/Payload" "$DIST"

step "1. prepare input IPA"
APP_REL="$(unzip -Z1 "$IN" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
[ -n "$APP_REL" ] || fail "no Payload/*.app in $IN"
APP_REL="${APP_REL%/}"
echo "    app dir: $APP_REL"
mkdir -p "$WORK/in"
( cd "$WORK/in" && unzip -q "$IN" ) || fail "unzip of $IN failed"
STAGED="$WORK/in/$APP_REL"
[ -d "$STAGED" ] || fail "staged app dir missing: $STAGED"

SPOTIFY_VERSION="$(perl "$BS/lib/plist-value.pl" "$STAGED/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
echo "    Spotify version: $SPOTIFY_VERSION"

step "2. merge components"
# spotipw: tweak dylib → Frameworks/ (a fresh replacement file simply overwrites)
mkdir -p "$STAGED/Frameworks"
cp -a "$BS/../components/spotipw/dylibs/spotifyglass.dylib" "$STAGED/Frameworks/"
# eeveespotify: MobileSubstrate dylib → Frameworks/ (proven IPA layout)
cp -a "Evevee Spotify/component/package/dynamic-libraries/EeveeSpotify.dylib" "$STAGED/Frameworks/"
# eeveespotify v7.0.0: the karaoke music-video shader rides beside the dylib upstream
# (inert data for dyld — validate-macho only parses the main binary — but it is a
# manifest-pinned component, so it is staged like every other payload file)
if [ -f "Evevee Spotify/component/package/dynamic-libraries/KaraokeBackgroundShader.metallib" ]; then
  cp -a "Evevee Spotify/component/package/dynamic-libraries/KaraokeBackgroundShader.metallib" "$STAGED/Frameworks/"
fi
# frameworks (shared resolver below decides which)
merge_dir "Evevee Spotify/component/frameworks/Orion.framework"             "$STAGED/Frameworks/Orion.framework"
merge_dir "Evevee Spotify/component/frameworks/EeveeSwiftProtobuf.framework" "$STAGED/Frameworks/EeveeSwiftProtobuf.framework"
# Eevee resources: bundle + icon PNGs at app root (BundleHelper search order, audit §3)
merge_dir "Evevee Spotify/component/bundles/EeveeSpotify.bundle" "$STAGED/EeveeSpotify.bundle"
find "Evevee Spotify/component/resources" -type f | while read -r r; do
  rel="${r#"Evevee Spotify/component/resources"/}"
  mkdir -p "$STAGED/$(dirname "$rel")"
  cp -a "$r" "$STAGED/$rel"
done
# shared dependency
merge_dir "$BS/../shared-dependencies/cydiasubstrate/CydiaSubstrate.framework" "$STAGED/Frameworks/CydiaSubstrate.framework"
echo "    merged: spotifyglass.dylib, EeveeSpotify.dylib, karaoke shader, 3 frameworks, bundle + $(find "Evevee Spotify/component/resources" -type f | wc -l) resources"

step "3. resolve dependencies"
perl "$BS/package/resolve-deps.pl" "$STAGED" || fail "dependency resolution failed"

step "4. inject load commands"
BIN="$STAGED/Spotify"
[ -f "$BIN" ] || fail "no main executable at $BIN"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  perl "$BS/inject/inject-dylib.pl" "$BIN" "$name"
done < <(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print "$_->{name}\n" for @{$d->{load_commands}}' < "$BS/../dependencies.json")

step "5. validate Mach-O"
perl "$BS/validate/validate-macho.pl" "$BIN" "$STAGED" || fail "Mach-O validation failed"

step "6. --watch: normalize embedded Watch companion (optional)"
# Test hook only (set exclusively by cleanup-tests.pl; unset by default):
# simulate a mid-pipeline failure AFTER the workspace exists, preserving the
# normal failure path end to end.
if [ "${PWEEVEE_FORCE_FAIL:-}" = "1" ]; then fail "FORCE_FAIL: simulated mid-pipeline failure"; fi
if [ "$WATCH" = 1 ]; then
  # With --watch the embedded Watch/ tree is normalized in place on the STAGED
  # app (IDs derived from the input's own outer id — no cross-scheme mixing),
  # followed by its dedicated validator. A Watch fix or validation failure
  # hard-fails the build: no broken Watch IPA ships silently. Without --watch,
  # step 7's structure validator below still REJECTS any Watch/ leftovers
  # (same behaviour as before this stage existed).
  bash "$BS/watch/watchfix-stage.sh" "$STAGED" || fail "Watch fix failed"
  perl "$BS/watch/validate-watchfix.pl" "$STAGED" || fail "Watch validation failed"
  WATCH_ENABLED=1
else
  echo "    (--watch not given; any embedded Watch/ tree will fail structure validation)"
  WATCH_ENABLED=0
fi

step "6b. register PwEevee brand icon (CFBundleAlternateIcons)"
# Idempotent: stages the committed brand icon at the app root and registers it
# under CFBundleIcons (plus CFBundleIcons~ipad when the host declares it).
# A failure hard-fails the build - a half-registered icon must not ship.
perl "$BS/package/patch-alternate-icon.pl" "$STAGED" || fail "alternate icon registration failed"

step "7. validate filesystem structure"
perl "$BS/validate/validate-ipa.pl" "$STAGED" "$WATCH_ENABLED" || fail "structure validation failed"

step "8. package IPA (deterministic, store-only)"
MOD_VERSION="$(sed 's/[^0-9A-Za-z.-]//g' "$REPO/Spotipw/version.txt" 2>/dev/null || echo 0.0.0)"
EEVEE_VERSION="$(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print $d->{version}' < "Evevee Spotify/component/manifest.json")"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
if [ "$OUT_GIVEN" = 0 ]; then
  OUT="$DIST/pweevee-$MOD_VERSION-eevee${EEVEE_VERSION%%-*}-$STAMP.ipa"
fi
mkdir -p "$(dirname "$OUT")"
perl "$BS/package/make-ipa.pl" "$STAGED" "$OUT"
echo "    $(du -h "$OUT" | cut -f1)  $OUT"

step "9. build manifest"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
IPA_SHA256="$(perl -MDigest::SHA -e 'print Digest::SHA::sha256_hex(scalar do { local $/; open(my $f,"<:raw",$ARGV[0]); <$f> })' "$OUT")"
IPA_SIZE="$(wc -c < "$OUT" | tr -d ' ')"
OUT_REL="${OUT#"$REPO"/}"   # repo-relative for the manifest when OUT sits inside the repo
DYLIBS="$(cd "$STAGED/Frameworks" && ls *.dylib 2>/dev/null | sed 's/^/  /' | tr '\n' ' ')"
FRAMEWORKS="$(cd "$STAGED/Frameworks" && ls -d *.framework 2>/dev/null | sed 's/^/  /' | tr '\n' ' ')"
SPOTIPW_VERSION="$(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print $d->{version}' < "$BS/../components/spotipw/manifest.json")"
SPOTIPW_COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
EEVEE_COMMIT="unknown (binary release 6.6.8-selfcontained.1)"
# Manifest travels WITH the output IPA: for default builds OUT lives in dist/
# so this is still dist/build-manifest.json; for an explicit -o elsewhere the
# manifest is colocated and can never overwrite the shared dist/ metadata.
MANIFEST="$(dirname "$OUT")/build-manifest.json"

cat > "$MANIFEST" <<EOF
{
  "project": "pweevee-unified (spoti.pw + EeveeSpotify integration build)",
  "spotify_version": "$SPOTIFY_VERSION",
  "spotipw_version": "$SPOTIPW_VERSION",
  "spotipw_commit": "$SPOTIPW_COMMIT",
  "eevee_version": "$EEVEE_VERSION",
  "eevee_commit": "$EEVEE_COMMIT",
  "build_date": "$BUILD_DATE",
  "ipa_path": "$OUT_REL",
  "ipa_sha256": "$IPA_SHA256",
  "ipa_size": $IPA_SIZE,
  "dylibs": ["spotifyglass.dylib", "EeveeSpotify.dylib"],
  "frameworks": ["CydiaSubstrate.framework", "EeveeSwiftProtobuf.framework", "Orion.framework"],
  "bundles": ["EeveeSpotify.bundle"],
  "brand_icon": "pweevee-icon.png (CFBundleAlternateIcons; original PwEevee artwork, see PwEvevee/brand-icons/manifest.json)",
  "resources": {
    "eevee_icons": $(find "Evevee Spotify/component/resources" -type f | wc -l),
    "load_commands": $(perl -MJSON::PP -e 'local $/; my $d=decode_json(<>); print scalar @{$d->{expected_load_commands}}' < "$BS/../dependencies.json")
  },
  "validation": {
    "archive": true,
    "mach_o": true,
    "dependencies": true,
    "resources": true,
    "ipa": true
  }
}
EOF
echo "    $MANIFEST"

step "10. run packaging tests"
perl "$BS/tests/deb-format-test.pl" >/dev/null && echo "    deb format tests: OK"
perl "$BS/tests/build-tests.pl"    >/dev/null && echo "    build tests: OK"

printf '\n==> DONE: %s\n    sha256 %s\n' "$OUT" "$IPA_SHA256"
