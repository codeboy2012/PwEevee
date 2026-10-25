#!/usr/bin/env bash
# ============================================================================
# update-stats.sh — refresh the website's live repository statistics, one step
# ============================================================================
#
#   scripts/update-stats.sh [options]
#
# Runs update-stats.pl (GitHub repository stats + download aggregates from the
# tracked release history) and then re-renders website/ so the new numbers are
# actually visible. This is the one command a person runs; the hourly schedule
# lives in .github/workflows/update-stats.yml, which commits only when the
# observable statistics actually changed.
#
# Options (passed through to update-stats.pl):
#   --strict    fail if any project did not update cleanly
#   --offline   do not call GitHub; revalidate and rewrite existing data
#   --no-render only regenerate website/data/stats.json
#   --no-test   skip the site integrity checks
#
# Set GITHUB_TOKEN to raise the API rate limit. It reaches curl through a
# 0600 config file only; it is never written to the generated data or logs.
#
# Requirements: bash, perl (core modules only), curl or wget. No Node, no npm.
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

RENDER=1
TEST=1
ARGS=()

for arg in "$@"; do
  case "$arg" in
    --no-render) RENDER=0 ;;
    --no-test)   TEST=0 ;;
    -h|--help)   sed -n '3,20p' "$0"; exit 0 ;;
    *)           ARGS+=("$arg") ;;
  esac
done

command -v perl >/dev/null || { echo "perl is required" >&2; exit 1; }

TOTAL=2
if [ "$RENDER" = 1 ]; then TOTAL=3; fi
STEP=0
step() { STEP=$((STEP + 1)); printf '\n\033[1m==> %d/%d  %s\033[0m\n' "$STEP" "$TOTAL" "$*"; }

step "fetching repository statistics from GitHub"
perl PwEvevee/build-system/release/update-stats.pl ${ARGS[@]+"${ARGS[@]}"}

if [ "$RENDER" = 1 ]; then
  step "rendering the website"
  perl PwEvevee/build-system/release/render-site.pl
else
  step "rendering skipped (--no-render)"
fi

if [ "$TEST" = 1 ]; then
  step "checking the generated site"
  perl PwEvevee/build-system/tests/website-tests.pl
else
  step "checks skipped (--no-test)"
fi

printf '\nRepository statistics are up to date.\n'
