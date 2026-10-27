#!/usr/bin/env bash
# ============================================================================
# refresh-site.sh — refresh, validate and publish the website in one command
# ============================================================================
#
#   scripts/refresh-site.sh [options]
#
# The complete cycle, in the order the data dependencies require:
#
#   1. update-releases.pl   GitHub Releases API     -> website/data/releases.json
#   2. update-stats.pl      GitHub repository API   -> website/data/stats.json
#   3. update-altsource.pl  SideloadLabs AltSource  -> website/data/altsource.json
#   4. render-site.pl       the three above + sources -> website/ (every page)
#   5. website-tests.pl     the rendered site must pass its integrity suite
#   6. --publish DIR        swap the validated tree into the live docroot
#
# This is the command both schedulers run: the server-side 15-minute cron that
# serves the live site, and the repository workflow that keeps the committed
# snapshot in step with GitHub.
#
# Steps 1-3 are fail-safe by construction: when GitHub or the upstream source
# cannot be reached they keep the last known-good values, mark them stale and
# exit 0, so a network failure never empties the site. They exit non-zero only
# when there is no data at all to render.
#
# Step 5 is the gate. A tree that fails validation is never published, and the
# live docroot is only ever replaced by a rename, so the served site can only
# move forward to a state that passed, or stay exactly where it is. A failure
# before the swap leaves the previous site untouched and running.
#
# Publishing is skipped when nothing meaningful changed: data-digest.pl hashes
# the staged tree with the volatile bookkeeping fields (generated_at,
# fetched_at, stale_since, verified_at) normalized away, and an unchanged site
# is left alone — no churn, no backup every fifteen minutes, no pointless swap.
#
# Options
#   --publish DIR     publish the rendered site into DIR (atomic swap + backup)
#   --backups DIR     where pre-swap tarballs live (default: <DIR>/../backups)
#   --keep N          backups to keep (default 10)
#   --no-publish      refresh and validate only (the default)
#   --no-test         skip the integrity suite (never use this on a schedule)
#   --tests-cmd CMD   validation command (default: website-tests.pl)
#   --digest-only     print the digest of the current tree and exit
#   --status-file F   write a JSON run record (used by the cron job)
#   --lock FILE       exclusive run lock (default: build-system/_work, if flock
#                     is installed; without a lock the run still works and a
#                     second overlapping run simply re-does the same work)
#   --strict          pass --strict to the updaters (any stale project fails)
#   --offline         do not call the network; revalidate existing data
#   -h, --help
#
# Exit status: 0 the site is refreshed and current; non-zero something failed
# before validation and nothing was published.
#
# Requirements: bash, perl (core modules only), curl or wget, tar. No Node,
# no npm, no Python.
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# The tree the updaters and the renderer write into. They resolve it themselves
# from PWEEVEE_ROOT (the same convention every release script uses), so the
# digest and the publish source have to resolve it identically.
SITE="${PWEEVEE_ROOT:-$REPO}"
OUT=website
RENDER=1
TEST=1
PUBLISH=""
BACKUPS=""
KEEP=10
TESTS_CMD="perl PwEvevee/build-system/tests/website-tests.pl"
STATUS=""
LOCK="PwEvevee/build-system/_work/refresh-site.lock"
STRICT=0
OFFLINE=0
DIGEST_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --publish)     PUBLISH="${2:-}"; shift 2 ;;
    --backups)     BACKUPS="${2:-}"; shift 2 ;;
    --keep)        KEEP="${2:-}";    shift 2 ;;
    --no-publish)  PUBLISH="";       shift ;;
    --no-test)     TEST=0;           shift ;;
    --tests-cmd)   TESTS_CMD="${2:-}"; shift 2 ;;
    --digest-only) DIGEST_ONLY=1;    shift ;;
    --status-file) STATUS="${2:-}";  shift 2 ;;
    --lock)        LOCK="${2:-}";    shift 2 ;;
    --strict)      STRICT=1;         shift ;;
    --offline)     OFFLINE=1;        shift ;;
    -h|--help)     sed -n '3,58p' "$0"; exit 0 ;;
    *)             echo "unknown option: $1 (try --help)" >&2; exit 64 ;;
  esac
done

perl -MDigest::SHA -MJSON::PP -e 1 2>/dev/null || {
  echo "perl with Digest::SHA and JSON::PP (core modules) is required" >&2; exit 1; }

# ---------------------------------------------------------------- digest only

if [ "$DIGEST_ONLY" = 1 ]; then
  perl PwEvevee/build-system/release/data-digest.pl --tree "$SITE/$OUT" --quiet
  exit 0
fi

# ---------------------------------------------------------------- lock

LOCKED=0
if [ -n "$LOCK" ] && command -v flock >/dev/null 2>&1; then
  mkdir -p "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  if flock -n 9; then
    LOCKED=1
  else
    echo "another refresh is already running ($LOCK) — leaving it to finish" >&2
    exit 0
  fi
fi

# ---------------------------------------------------------------- reporting

STEP=0
TOTAL=5
[ -n "$PUBLISH" ] && TOTAL=6

step() { STEP=$((STEP + 1)); printf '\n==> %d/%d  %s\n' "$STEP" "$TOTAL" "$*"; }
say()  { printf '%s\n' "$*"; }

STARTED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
DIGEST_BEFORE="$(perl PwEvevee/build-system/release/data-digest.pl --tree "$SITE/$OUT" --quiet)"
DIGEST_AFTER="$DIGEST_BEFORE"
PUBLISHED=0
CHANGED=0
RELEASE=""

# A JSON run record: the cron job's own health file. Written on every exit
# path, including failures, so "did the last refresh work?" is answerable
# without reading logs (and the site's freshness band shows the same story).
write_status() {
  local state="$1" note="${2:-}"
  [ -n "$STATUS" ] || return 0
  mkdir -p "$(dirname "$STATUS")"
  printf '{"started":"%s","finished":"%s","state":"%s","release":"%s","digest_before":"%s","digest_after":"%s","changed":%s,"published":%s,"note":"%s"}\n' \
    "$STARTED" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$state" "$RELEASE" \
    "$DIGEST_BEFORE" "$DIGEST_AFTER" \
    "$([ "$CHANGED" = 1 ] && echo true || echo false)" \
    "$([ "$PUBLISHED" = 1 ] && echo true || echo false)" \
    "$note" > "$STATUS.tmp"
  mv "$STATUS.tmp" "$STATUS"
}

# ---------------------------------------------------------------- steps

UPDATER_ARGS=()
[ "$STRICT" = 1 ]  && UPDATER_ARGS+=(--strict)
[ "$OFFLINE" = 1 ] && UPDATER_ARGS+=(--offline)

run_step() {
  local label="$1"; shift
  step "$label"
  set +e
  "$@"
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    say ""
    say "!! $label failed (exit $rc) — nothing was published; the live site is unchanged."
    write_status failed "$label failed (exit $rc)"
    exit "$rc"
  fi
}

say "PwEevee website refresh"
say "  repository root : $REPO"
say "  site root       : $SITE"
say "  mode            : $([ "$OFFLINE" = 1 ] && echo offline || echo live GitHub)${PUBLISH:+  ·  publish -> $PUBLISH}"
say "  lock            : $([ "$LOCKED" = 1 ] && echo "$LOCK (held)" || echo none)"

run_step "fetching GitHub release metadata" \
  perl PwEvevee/build-system/release/update-releases.pl ${UPDATER_ARGS[@]+"${UPDATER_ARGS[@]}"}
run_step "refreshing repository statistics" \
  perl PwEvevee/build-system/release/update-stats.pl ${UPDATER_ARGS[@]+"${UPDATER_ARGS[@]}"}
run_step "reading the SideloadLabs AltSource" \
  perl PwEvevee/build-system/release/update-altsource.pl ${UPDATER_ARGS[@]+"${UPDATER_ARGS[@]}"}
run_step "rendering the website" \
  perl PwEvevee/build-system/release/render-site.pl

if [ "$TEST" = 1 ]; then
  run_step "validating the rendered site" bash -c "$TESTS_CMD"
else
  step "validation skipped (--no-test)"
  say "  !! an unvalidated tree must never be published"
fi

# The release the site now presents, read back from what was rendered rather
# than from anything the updater printed.
RELEASE="$(perl -MJSON::PP -0777 -e '
  my $d = eval { decode_json(<STDIN>) } or exit 0;
  for my $p (@{ $d->{projects} || [] }) {
      next unless ($p->{slug} // "") eq "pweevee";
      print(($p->{latest} || {})->{version} // "");         }' < "$SITE/$OUT/data/releases.json" 2>/dev/null || true)"

DIGEST_AFTER="$(perl PwEvevee/build-system/release/data-digest.pl --tree "$SITE/$OUT" --quiet)"

if [ -z "$PUBLISH" ]; then
  say ""
  say "No publish target given (--publish DIR would swap the validated tree into place)."
  [ "$DIGEST_BEFORE" = "$DIGEST_AFTER" ] || CHANGED=1
  say ""
  say "Refreshed. Latest PwEevee release in the rendered data: ${RELEASE:-unknown}"
  write_status ok ""
  exit 0
fi

# ---------------------------------------------------------------- publish

step "publishing to $PUBLISH"

if [ ! -d "$SITE/$OUT" ] || [ ! -f "$SITE/$OUT/index.html" ]; then
  say "!! the rendered tree is missing index.html — refusing to publish"
  write_status failed "rendered tree incomplete"
  exit 1
fi

LIVE_DIGEST=""
[ -d "$PUBLISH" ] && LIVE_DIGEST="$(perl PwEvevee/build-system/release/data-digest.pl --tree "$PUBLISH" --quiet 2>/dev/null || true)"

if [ -n "$LIVE_DIGEST" ] && [ "$LIVE_DIGEST" = "$DIGEST_AFTER" ]; then
  say "  the live site is already this exact site (digest $DIGEST_AFTER)"
  say "  nothing to publish — no swap, no backup, no churn"
  write_status ok "live site already current"
  exit 0
fi

CHANGED=1
[ -n "$BACKUPS" ] || BACKUPS="$(dirname "$PUBLISH")/backups"
mkdir -p "$BACKUPS"

# Stage a copy on the destination's own filesystem, so replacing the docroot is
# a rename and never a half-copied directory.
STAGE="$(mktemp -d "$(dirname "$PUBLISH")/.pweevee-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -a "$SITE/$OUT/." "$STAGE/"

for must in index.html data/releases.json data/stats.json; do
  [ -f "$STAGE/$must" ] || {
    say "!! staged site is missing $must — refusing to publish"
    write_status failed "staged site missing $must"
    exit 1
  }
done

if [ -e "$PUBLISH" ]; then
  BACKUP="$BACKUPS/site-$(date -u '+%Y%m%dT%H%M%SZ').tar.gz"
  tar -czf "$BACKUP" -C "$PUBLISH" . || {
    say "!! could not back up the live site — refusing to publish"
    write_status failed "backup failed"
    exit 1
  }
  say "  previous site backed up to $BACKUP"
  rm -rf "$PUBLISH.prev"
  mv "$PUBLISH" "$PUBLISH.prev"
fi

mv "$STAGE" "$PUBLISH"
rm -rf "$PUBLISH.prev"
PUBLISHED=1

# keep the newest N backups, drop the rest (oldest first)
KEPT=0
for f in $(ls -1t "$BACKUPS"/site-*.tar.gz 2>/dev/null); do
  KEPT=$((KEPT + 1))
  [ "$KEPT" -gt "$KEEP" ] && rm -f "$f"
done

say ""
say "Published. Latest PwEevee release now served: ${RELEASE:-unknown}"
say "  digest before : $DIGEST_BEFORE"
say "  digest after  : $DIGEST_AFTER"
write_status ok ""
exit 0
