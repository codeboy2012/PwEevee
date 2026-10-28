#!/usr/bin/env bash
# ============================================================================
# refresh-notify.sh — deliver one refresh notification to a configured endpoint
# ============================================================================
#
#   PWEEVEE_NOTIFY_TITLE=... PWEEVEE_NOTIFY_TEXT=... \
#       scripts/refresh-notify.sh [--dry-run]
#
#   scripts/refresh-notify.sh --check                 # is it wired up?
#   scripts/refresh-notify.sh --check --send-test     # ... and prove delivery
#
# The refresh wrapper calls this only when refresh-health.pl has decided an
# alert is due. It is deliberately a separate program: a delivery problem must
# never be able to change the outcome of the refresh, and the pipeline's own
# failure has to survive whatever happens here.
#
# Configuration — one value, kept out of the repository:
#
#   ~/.config/pweevee-site/notify.conf   (mode 0600)
#       PWEEVEE_NOTIFY_URL=https://…
#
#   or the same value in the environment (PWEEVEE_NOTIFY_URL). The environment
#   wins, which is what the tests and a one-off run use. PWEEVEE_NOTIFY_CONF
#   points at a different file; PWEEVEE_NOTIFY_TIMEOUT sets the HTTP timeout
#   (seconds, default 10).
#
# The payload shape follows the endpoint, so the operator does not have to
# describe a schema:
#
#   hooks.slack.com            {"text": "*title*\ntext"}
#   discord.com / discordapp   {"content": "**title**\ntext"}
#   *ntfy*                     plain-text body + Title / Tags headers
#   anything else              {"title":…, "text":…, "source":"pweevee-website"}
#
# The URL is never printed, logged or echoed — not on success, not on failure,
# not by --dry-run and not by --check, which reports only the service host and
# the payload shape. Message text is redacted before it leaves the process, so a
# diagnostic that happens to contain an endpoint or a token cannot leak it.
#
# Exit status: 0 delivered; 2 no endpoint configured; 3 delivery failed
#              (including an unusable URL); 64 usage error.
#              --check without --send-test exits 0 when configured, 2 when not.
# ============================================================================
set -euo pipefail

TITLE="${PWEEVEE_NOTIFY_TITLE:-PwEevee website refresh}"
TEXT="${PWEEVEE_NOTIFY_TEXT:-}"
TIMEOUT="${PWEEVEE_NOTIFY_TIMEOUT:-10}"
DRY=0
CHECK=0
SEND_TEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --title)     TITLE="${2:-}"; shift 2 ;;
    --text)      TEXT="${2:-}";  shift 2 ;;
    --timeout)   TIMEOUT="${2:-}"; shift 2 ;;
    --dry-run)   DRY=1; shift ;;
    --check)     CHECK=1; shift ;;
    --send-test) SEND_TEST=1; CHECK=1; shift ;;
    -h|--help)   sed -n '3,45p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 64 ;;
  esac
done

if [ "$SEND_TEST" = 1 ] && [ "$DRY" = 1 ]; then
  echo "--send-test and --dry-run are mutually exclusive" >&2
  exit 64
fi

# ---------------------------------------------------------------- redaction

redact() {
  sed -E 's#https?://[^[:space:]]+#<url>#g; s/([Tt]oken|[Ss]ecret|[Pp]assword|[Bb]earer|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/\1=<redacted>/g'
}

TITLE="$(printf '%s' "$TITLE" | redact | tr -d '\r')"
TEXT="$(printf '%s' "$TEXT" | redact | tr -d '\r')"

# ---------------------------------------------------------------- endpoint

CONF="${PWEEVEE_NOTIFY_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/pweevee-site/notify.conf}"
URL="${PWEEVEE_NOTIFY_URL:-}"
SOURCE="env"

if [ -z "$URL" ] && [ -f "$CONF" ] && [ -r "$CONF" ]; then
  URL="$(sed -n 's/^[[:space:]]*PWEEVEE_NOTIFY_URL[[:space:]]*=[[:space:]]*//p' "$CONF" 2>/dev/null \
         | head -1 | tr -d '\r' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")"
  SOURCE="file"
fi

# ---------------------------------------------------------------- check mode

if [ "$CHECK" = 1 ]; then
  if [ -z "$URL" ]; then
    echo "configured=no"
    echo "config=$CONF"
    echo "hint=set PWEEVEE_NOTIFY_URL in that file (mode 0600); docs/homelab-deployment.md has the exact commands"
    exit 2
  fi
  case "$URL" in
    http://*|https://*) ;;
    *) echo "configured=no" >&2; echo "reason=the configured value is not an http(s) URL" >&2; exit 3 ;;
  esac

  HOST="$(printf '%s' "$URL" | sed -E 's#^https?://([^/:?#]+).*#\1#' | tr '[:upper:]' '[:lower:]')"
  case "$HOST" in
    hooks.slack.com)                          FMT=slack ;;
    discord.com|discordapp.com|*.discord.com) FMT=discord ;;
    ntfy.sh|*ntfy*)                           FMT=ntfy ;;
    *)                                        FMT=generic ;;
  esac

  echo "configured=yes"
  echo "service=$HOST"
  echo "format=$FMT"
  echo "source=$SOURCE"
  if [ "$SOURCE" = file ]; then
    MODE="$(stat -c '%a' "$CONF" 2>/dev/null || stat -f '%Lp' "$CONF" 2>/dev/null || echo '')"
    if [ -n "$MODE" ]; then
      echo "config_mode=$MODE"
      case "${MODE: -2}" in
        00) ;;
        *) echo "warning=$CONF is readable by group or others; chmod 600 it" >&2 ;;
      esac
    fi
  fi

  if [ "$SEND_TEST" = 0 ]; then
    echo "delivery=not-tested"
    exit 0
  fi

  TITLE="PwEevee website refresh — test"
  TEXT="Test notification from the homelab refresh pipeline at $(date -u '+%Y-%m-%dT%H:%M:%SZ'). No failure occurred; receipt of this message means alerts are wired up."
  # fall through to the normal delivery path below
fi

# ---------------------------------------------------------------- payload

if [ -z "$URL" ]; then
  echo "no notification endpoint configured (set PWEEVEE_NOTIFY_URL in $CONF, mode 0600)" >&2
  exit 2
fi

case "$URL" in
  http://*|https://*) ;;
  *) echo "PWEEVEE_NOTIFY_URL is not an http(s) URL; not sending" >&2; exit 3 ;;
esac

if [ "$SOURCE" = file ]; then
  MODE="$(stat -c '%a' "$CONF" 2>/dev/null || stat -f '%Lp' "$CONF" 2>/dev/null || echo '')"
  if [ -n "$MODE" ] && [ "${MODE: -2}" != "00" ]; then
    echo "warning: $CONF is mode $MODE; it should be 600" >&2
  fi
fi

HOST="${HOST:-$(printf '%s' "$URL" | sed -E 's#^https?://([^/:?#]+).*#\1#' | tr '[:upper:]' '[:lower:]')}"
case "$HOST" in
  hooks.slack.com)                          FMT=slack ;;
  discord.com|discordapp.com|*.discord.com) FMT=discord ;;
  ntfy.sh|*ntfy*)                           FMT=ntfy ;;
  *)                                        FMT=generic ;;
esac

if [ "$FMT" = ntfy ]; then
  BODY="$TITLE"$'\n\n'"$TEXT"
else
  BODY="$(PWEEVEE_FMT="$FMT" PWEEVEE_TITLE="$TITLE" PWEEVEE_TEXT="$TEXT" \
    perl -MJSON::PP -e '
      my $j = JSON::PP->new->utf8->canonical;
      my ($t, $x, $f) = @ENV{qw(PWEEVEE_TITLE PWEEVEE_TEXT PWEEVEE_FMT)};
      if ($f eq "slack")   { print $j->encode({ text => "*$t*\n$x" }) }
      elsif ($f eq "discord") { print $j->encode({ content => "**$t**\n$x" }) }
      else { print $j->encode({ title => $t, text => $x, source => "pweevee-website" }) }
    ')"
fi

if [ "$DRY" = 1 ]; then
  printf 'format=%s\n%s\n' "$FMT" "$BODY"
  exit 0
fi

# ---------------------------------------------------------------- delivery

if [ "$FMT" = ntfy ]; then
  if ! CODE="$(printf '%s' "$BODY" | curl -sS -o /dev/null -w '%{http_code}' \
        --max-time "$TIMEOUT" -X POST \
        -H "Title: $TITLE" -H 'Tags: warning' \
        -H 'Content-Type: text/plain; charset=utf-8' \
        --data-binary @- "$URL" 2>/dev/null)"; then
    echo "the notification endpoint could not be reached" >&2
    [ "$CHECK" = 1 ] && echo "delivery=failed"
    exit 3
  fi
else
  if ! CODE="$(printf '%s' "$BODY" | curl -sS -o /dev/null -w '%{http_code}' \
        --max-time "$TIMEOUT" -X POST \
        -H 'Content-Type: application/json' \
        --data-binary @- "$URL" 2>/dev/null)"; then
    echo "the notification endpoint could not be reached" >&2
    [ "$CHECK" = 1 ] && echo "delivery=failed"
    exit 3
  fi
fi

case "$CODE" in
  2??)
    [ "$CHECK" = 1 ] && echo "delivery=ok http=$CODE"
    exit 0 ;;
  *)
    echo "the notification endpoint answered HTTP $CODE" >&2
    [ "$CHECK" = 1 ] && echo "delivery=failed http=$CODE"
    exit 3 ;;
esac
