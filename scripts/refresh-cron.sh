#!/bin/bash
# ============================================================================
# refresh-cron.sh — the fifteen-minute refresh of the live PwEevee website
# ============================================================================
#
#   ~/pweevee-site/bin/refresh-cron.sh        (run by cron every 15 minutes)
#
#   1. takes an exclusive lock, so two runs can never overlap — a run that finds
#      the lock held records a `skipped` attempt and exits 0 without touching
#      the site or the failure counters;
#   2. fetches origin/main into ~/pweevee-site/src — a --no-checkout clone, so
#      the fetch cannot disturb a working tree — and extracts exactly the
#      committed tree with `git archive` into a per-run scratch directory;
#   3. runs that tree's scripts/refresh-site.sh --publish, which refreshes the
#      release metadata, repository statistics and AltSource from GitHub,
#      re-renders every page, runs website-tests.pl, and only then swaps the
#      live document root (a rename, with the previous site backed up);
#   4. records the run in logs/refresh-status.json and logs/refresh.log, then
#      updates the incident state in logs/refresh-health.json and, when
#      refresh-health.pl says an alert is due, delivers one notification
#      through refresh-notify.sh.
#
# Failure is safe by construction: publishing happens only after validation, and
# the document root is replaced by a rename, so a failed run leaves the previous
# site serving. A notification problem can neither change the run's exit status
# nor erase its error: the status file and the log stay authoritative.
#
# This file is the source of truth; the running copy lives in
# ~/pweevee-site/bin/ next to refresh-health.pl and refresh-notify.sh. Deploy
# all three together (docs/homelab-deployment.md). PWEEVEE_SITE_DIR exists so
# the tests can drive the real wrapper against a throwaway site directory.
#
# Nothing here needs root. No secret is read into the code path except the
# notification URL, which refresh-notify.sh reads itself and never logs.
# ============================================================================
set -uo pipefail

D="${PWEEVEE_SITE_DIR:-$HOME/pweevee-site}"
mkdir -p "$D/logs"
# The script runs the pipeline from inside a per-run directory, so every path it
# keeps has to be absolute before that first cd.
D="$(cd "$D" && pwd)"
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$D/src"
LOG="$D/logs/refresh.log"
STATUS="$D/logs/refresh-status.json"
HEALTH="$D/logs/refresh-health.json"
LOCK="$D/refresh.lock"
COOLDOWN="${PWEEVEE_NOTIFY_COOLDOWN:-3600}"

stamp() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log()   { printf '%s  %s\n' "$(stamp)" "$*" >> "$LOG"; }

# ------------------------------------------------------------ health helpers

# Every health operation is best-effort: if the helper is missing or broken the
# refresh still runs, still publishes, and still exits with its own status.
record() {
  perl "$BIN/refresh-health.pl" --status "$STATUS" --state "$HEALTH" "$@" 2>>"$LOG" \
    || { log "health record failed (continuing)"; return 0; }
}

notify_if_pending() {
  [ -f "$HEALTH" ] || return 0
  local pending kind title text nrc result err
  pending="$(perl -MJSON::PP -0777 -ne '
      my $d = eval { decode_json($_) } or exit 0;
      my $p = $d->{pending_notification} or exit 0;
      for my $k (qw(kind title text)) {
          my $v = $p->{$k} // "";
          $v =~ s/[\t\r\n]+/ /g;
          print $v, "\t";
      }' < "$HEALTH" 2>/dev/null)"
  [ -n "$pending" ] || return 0
  IFS=$'\t' read -r kind title text _ <<< "$pending"
  [ -n "${kind:-}" ] || return 0

  if PWEEVEE_NOTIFY_TITLE="$title" PWEEVEE_NOTIFY_TEXT="$text" \
       bash "$BIN/refresh-notify.sh" >> "$LOG" 2>&1; then
    nrc=0
  else
    nrc=$?
  fi

  case "$nrc" in
    0)  result=ok;             err="" ;;
    2)  result=not-configured; err="no notification endpoint is configured" ;;
    *)  result=failed;         err="the notification endpoint did not accept the message" ;;
  esac
  if [ -n "$err" ]; then
    record --record-notification --result "$result" --error "$err" --now "$(date -u +%s)" >/dev/null
  else
    record --record-notification --result "$result" --now "$(date -u +%s)" >/dev/null
  fi
  log "notification ($kind): $result"
}

# finish RC STAGE — record the outcome, then deliver any alert it earned.
finish() {
  local rc="$1" stage="${2:-}"
  record --rc "$rc" --stage "$stage" --since "$RUN_START" \
         --cooldown "$COOLDOWN" --now "$(date -u +%s)" >/dev/null
  notify_if_pending
}

# ------------------------------------------------------------ one at a time

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  if ! flock -n 9; then
    log "another refresh is still running — skipping this cycle"
    record --skipped locked --now "$(date -u +%s)" >/dev/null
    exit 0
  fi
else
  # Better a run without the overlap guard than a schedule that skips forever
  # because a utility is missing.
  log "flock is not installed on this host — running without the overlap guard"
fi

RUN_START="$(stamp)"
log "refresh starting"

# ------------------------------------------------------------ get the tree

if [ ! -d "$SRC/.git" ]; then
  log "src clone missing — nothing to refresh from"
  finish 1 fetch
  exit 1
fi
if ! git -C "$SRC" fetch -q --depth=1 origin main; then
  log "git fetch failed — leaving the live site as it is"
  finish 1 fetch
  exit 1
fi

RUN="$(mktemp -d "$D/run.XXXXXX")"
if [ ! -d "$RUN" ]; then
  log "cannot create a run directory — leaving the live site as it is"
  finish 1 fetch
  exit 1
fi
cleanup() { rm -rf "$RUN"; }
trap cleanup EXIT

if ! git -C "$SRC" archive FETCH_HEAD | tar -x -C "$RUN"; then
  log "extracting the committed tree failed — leaving the live site as it is"
  finish 1 fetch
  exit 1
fi
log "refreshing from $(git -C "$SRC" log -1 --format='%h %s' FETCH_HEAD 2>/dev/null)"

# ------------------------------------------------------------ refresh + publish

cd "$RUN" || { finish 1 fetch; exit 1; }
OUT="$(bash scripts/refresh-site.sh \
          --publish "$D/current" \
          --backups "$D/backups" \
          --status-file "$STATUS" 2>&1)"
RC=$?
printf '%s\n' "$OUT" >> "$LOG"

# ------------------------------------------------------------ outcome + alert

if [ "$RC" = 0 ]; then
  finish 0 done
  HOW="$(perl -MJSON::PP -0777 -ne '
      my $d = eval { decode_json($_) };
      print(($d->{published} ? "published" : "already current")) if $d;
    ' < "$STATUS" 2>/dev/null)"
  log "refresh ok (${HOW:-ok})"
else
  finish "$RC" ""
  log "refresh FAILED (exit $RC) — the live site is unchanged"
fi

exit "$RC"
