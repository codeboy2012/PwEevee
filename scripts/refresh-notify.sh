#!/usr/bin/env bash
# ============================================================================
# refresh-notify.sh — deliver one refresh notification to a configured endpoint
# ============================================================================
#
#   PWEEVEE_NOTIFY_TITLE=... PWEEVEE_NOTIFY_TEXT=... \
#       scripts/refresh-notify.sh [--dry-run]
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
# not by --dry-run. Message text is redacted before it leaves the process, so a
# diagnostic that happens to contain an endpoint or a token cannot leak it.
#
# Exit status: 0 delivered; 2 no endpoint configured; 3 delivery failed
#              (including an unusable URL); 64 usage error.
# ============================================================================
set -euo pipefail

TITLE="${PWEEVEE_NOTIFY_TITLE:-PwEevee website refresh}"
TEXT="${PWEEVEE_NOTIFY_TEXT:-}"
TIMEOUT="${PWEEVEE_NOTIFY_TIMEOUT:-10}"
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --title)   TITLE="${2:-}"; shift 2 ;;
    --text)    TEXT="${2:-}";  shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '3,45p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 64 ;;
  esac
done

# ---------------------------------------------------------------- redaction

redact() {
  sed -E 's#https?://[^[:space:]]+#<url>#g; s/([Tt]oken|[Ss]ecret|[Pp]assword|[Bb]earer|api[_-]?key)[[:space:]]*[:=][[:space:]]*[^[:space:]]+/\1=<redacted>/g'
}

TITLE="$(printf '%s' "$TITLE" | redact | tr -d '\r')"
TEXT="$(printf '%s' "$TEXT" | redact | tr -d '\r')"

# ---------------------------------------------------------------- endpoint

CONF="${PWEEVEE_NOTIFY_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/pweevee-site/notify.conf}"
URL="${PWEEVEE_NOTIFY_URL:-}"

if [ -z "$URL" ] && [ -r "$CONF" ]; then
  URL="$(sed -n 's/^[[:space:]]*PWEEVEE_NOTIFY_URL[[:space:]]*=[[:space:]]*//p' "$CONF" \
         | head -1 | tr -d '\r' | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//")"
fi

if [ -z "$URL" ]; then
  echo "no notification endpoint configured (set PWEEVEE_NOTIFY_URL in $CONF, mode 0600)" >&2
  exit 2
fi

case "$URL" in
  http://*|https://*) ;;
  *) echo "PWEEVEE_NOTIFY_URL is not an http(s) URL; not sending" >&2; exit 3 ;;
esac

# ---------------------------------------------------------------- payload

HOST="$(printf '%s' "$URL" | sed -E 's#^https?://([^/:?#]+).*#\1#' | tr '[:upper:]' '[:lower:]')"
case "$HOST" in
  hooks.slack.com)                    FMT=slack ;;
  discord.com|discordapp.com|*.discord.com) FMT=discord ;;
  ntfy.sh|*ntfy*)                     FMT=ntfy ;;
  *)                                  FMT=generic ;;
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
    exit 3
  fi
else
  if ! CODE="$(printf '%s' "$BODY" | curl -sS -o /dev/null -w '%{http_code}' \
        --max-time "$TIMEOUT" -X POST \
        -H 'Content-Type: application/json' \
        --data-binary @- "$URL" 2>/dev/null)"; then
    echo "the notification endpoint could not be reached" >&2
    exit 3
  fi
fi

case "$CODE" in
  2??) exit 0 ;;
  *) echo "the notification endpoint answered HTTP $CODE" >&2; exit 3 ;;
esac
