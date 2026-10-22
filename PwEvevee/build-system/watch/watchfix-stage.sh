#!/usr/bin/env bash
# ============================================================================
# watchfix-stage.sh — in-pipeline adapter for watchfix.sh
#
#   PwEvevee/build-system/watch/watchfix-stage.sh <staged .app dir>
#
# unified.sh stages the app tree on disk (merged/injected) and calls this
# mid-pipeline. watchfix.sh itself transforms whole IPA files, so this adapter
# zips the staged tree to a temp IPA, runs watchfix on it with --base-id taken
# from the staged app's own current CFBundleIdentifier (preserving the build's
# identity rather than forcing one), unzips the result back over the staged
# tree, and verifies the round-trip did not damage anything above app scope.
#
# Hard-fails on any error. Never modifies the input IPA file; only the staged
# tree in $WORK.
# ============================================================================
# NOTE on Sideloadly/free-account renaming: current Sideloadly renames the
# outer app to a unique id (historically '<name>.<10-char suffix>') on free
# Apple accounts and re-signs nested bundles "with updated bundle IDs" — but
# propagation to nested .appex Info.plists has been shown buggy
# (AppexBundleIDNotPrefixed install failure on this repo's build). Since the
# final suffix is only announced by Sideloadly at install time, the shape we
# pre-bake must be chosen HERE: default keeps the blend-in scheme below; a
# user-announced base id via PWEEVEE_WATCH_BASE_ID prebakes that exact id so
# every nested id agrees with what the installer will expect.
# NOTE on Sideloadly/free-account renaming: current Sideloadly renames the
# outer app to a unique id on free Apple accounts and re-signs nested bundles
# "with updated bundle IDs" — but propagation to nested .appex Info.plists has
# been observed buggy (the real AppexBundleIDNotPrefixed failure on this
# repo's build). The final suffix is announced by Sideloadly at install time,
# so the shape we pre-bake must be chosen HERE: default keeps the derived
# scheme below; a user-announced target via PWEEVEE_WATCH_BASE_ID pre-bakes
# that exact id so every nested id agrees with what the installer expects.
set -euo pipefail

STAGED="$1"
[ -d "$STAGED" ] || { echo "usage: watchfix-stage.sh <staged .app dir>" >&2; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/watchfix-stage.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

APP_NAME="$(basename "$STAGED")"          # e.g. Spotify.app
OUTER_ID="$(head -1 "$STAGED/Info.plist" >/dev/null 2>&1; \
  perl "$DIR/../lib/plist-value.pl" "$STAGED/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
[ -n "$OUTER_ID" ] || { echo "!! FAIL: staged app has no readable CFBundleIdentifier" >&2; exit 1; }
echo "    watchfix-stage: outer id = $OUTER_ID"

# 1. Package the staged tree exactly as an IPA (Payload/<name>).
# No `zip` binary is assumed: use the repo packager (make-ipa.pl), the same
# deterministic store-only archiver the pipeline itself uses in step 8.
mkdir -p "$TMP/payload"
cp -a "$STAGED" "$TMP/payload/$APP_NAME"
perl "$DIR/../package/make-ipa.pl" "$TMP/payload/$APP_NAME" "$TMP/stage.ipa" \
  || { echo "!! FAIL: could not package staged tree" >&2; exit 1; }

# 2. Run the committed watchfix against the temp IPA at the (possibly
#    overridden) base id.
BASE_ID="$OUTER_ID"
if [ -n "${PWEEVEE_WATCH_BASE_ID:-}" ]; then
  BASE_ID="$PWEEVEE_WATCH_BASE_ID"
  echo "    watchfix-stage: PWEEVEE_WATCH_BASE_ID override = $BASE_ID"
fi
bash "$DIR/watchfix.sh" "$TMP/stage.ipa" \
     --out "$TMP/fixed.ipa" \
     --base-id "$BASE_ID" \
     --skip-sign \
  || { echo "!! FAIL: watchfix transform failed" >&2; exit 1; }

# 3. Replace the staged tree with the fixed Payload/<name>
rm -rf "$TMP/fixed-payload"; mkdir -p "$TMP/fixed-payload"
unzip -q "$TMP/fixed.ipa" -d "$TMP/fixed-payload" \
  || { echo "!! FAIL: fixed IPA unreadable" >&2; exit 1; }
[ -d "$TMP/fixed-payload/Payload/$APP_NAME" ] \
  || { echo "!! FAIL: fixed IPA does not contain Payload/$APP_NAME" >&2; exit 1; }

# 4. Post-transform namespace check: with an override, the validator must
#    confirm outer id == override AND all descendants derive from it — this
#    gate is what makes a Sideloadly-announced prefix trustworthy before any
#    device install is attempted.
if [ -n "${PWEEVEE_WATCH_BASE_ID:-}" ]; then
  perl "$DIR/validate-watchfix.pl" "$TMP/fixed-payload/Payload/$APP_NAME" "$BASE_ID" --catch-double-prefix \
    || { echo "!! FAIL: overridden namespace validation failed" >&2; exit 1; }
fi

rm -rf "$STAGED"
mv "$TMP/fixed-payload/Payload/$APP_NAME" "$STAGED"
echo "    watchfix-stage: staged tree replaced with Watch-normalized copy"
