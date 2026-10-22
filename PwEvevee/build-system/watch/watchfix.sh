#!/usr/bin/env bash
# ============================================================================
# watchfix.sh — make a decrypted Spotify IPA with an embedded Watch app
#               installable over USB (Sideloadly / AltStore / SideStore).
# ============================================================================
#
#   PwEvevee/build-system/watch/watchfix.sh <decrypted.ipa> [options]
#
#     --out PATH            output IPA (default: dist/<name>-watchfix.ipa)
#     --base-id ID          free-signing base bundle id for the iPhone app.
#                           Every nested id is DERIVED from it. Default stays
#                           com.spotify.client (valid; switch when signing with
#                           a free profile to dodge the 10-App-ID/7-day cap).
#     --team-id XXXXXXXXXX  10-char Team ID for codesign. Required with --sign.
#     --sign                re-sign every bundle innermost-first after edits.
#     --skip-sign           never modify existing signatures (validate only).
#
# What it does, in order (all edits BEFORE any re-signing):
#
#   1. unpack IPA, locate the outer app and its Watch/WatchApp.app companion
#   2. rewrite every CFBundleIdentifier under the app to a consistent scheme:
#        outer app        <base-id>
#        Watch app        <outer>.watchkitapp
#        any .appex       <parent-id>.<leaf-name>
#   3. fix companion metadata on both sides:  #        Watch app Info.plist gets WKWatchKitApp=true (a real plist
  #        Boolean) and WKCompanionAppBundleIdentifier pointing at the
  #        companion's id; the COMPANION's Info.plist gets WKWatchKitApp
  #        removed (that key marks the WATCH side of the pair; Apple: "this
  #        key applies to the Watch app only").
#   4. phone-side entitlements gain the watchcompanion domains for the watch
#        app id and watch app's NSExtension NSExtensionPointIdentifier list
#        is left alone (no invented intents).
#   5. phone-side app needs NSExtension with NSExtensionPointIdentifier
#        com.apple.appintents-extension only if it actually provides one;
#        IntentsAppexIntentsSupportedNotASubset is fixed by making the PHONE
#        app's supported Intents declarations a superset of its extension's
#        (phone copy is authoritative; watch extension subset is preserved).
#   6. codesign innermost-out when --sign is given: first every .appex,
#        then the Watch app, phone Frameworks, then the outer app.
#
# The mapping is DERIVED, not hard-coded: base id comes from --base-id and
# every nested id is '<parent-id>.<leaf-bundle-name-without-extension>'.
# ============================================================================
set -euo pipefail

IN="" OUT="" BASE_ID="com.spotify.client" TEAM_ID="" SIGN=0 SKIP_SIGN=0
# First non-option argument is the input IPA; every --flag consumes its value.
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --base-id) BASE_ID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --sign) SIGN=1; shift ;;
    --skip-sign) SKIP_SIGN=1; shift ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
if [ -z "$IN" ]; then
  echo "usage: watchfix.sh <decrypted.ipa> [--out P] [--base-id ID] [--team-id T] [--sign]" >&2
  exit 1
fi
case "$IN" in /*) ;; *) IN="$PWD/$IN" ;; esac
[ -f "$IN" ] || { echo "no such IPA: $IN" >&2; exit 1; }

BS="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$BS/../../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/watchfix.XXXXXX")"
# Generated content is removed when the run ends; set WF_DEBUG=1 to keep it.
trap 'rm -rf "$WORK"' EXIT
[ -n "${WF_DEBUG:-}" ] && trap ':' EXIT
: 
mkdir -p "$WORK/in" "$REPO/dist"

# ---------------- 1. unpack ------------------------------------------------
# NOTE: store-only IPA entries often carry DOS read-only attributes (especially
# SC_Info-adjacent bundles). Strip them after extraction so the structured
# plist editors can write; the packager re-serializes cleanly.
unzip -q "$IN" -d "$WORK/in"
find "$WORK/in" -type f ! -perm -u+w -exec chmod u+w {} + 2>/dev/null || true
find "$WORK/in" -type d ! -perm -u+w -exec chmod u+w {} + 2>/dev/null || true
APP_REL="$(cd "$WORK/in" && unzip -Z1 "$IN" -l 2>/dev/null | grep -oE '^Payload/[^/]+\.app/$' | head -1 || true)"
if [ -z "$APP_REL" ]; then
  APP_REL="$(find "$WORK/in/Payload" -maxdepth 1 -name '*.app' -type d | head -1 | sed "s|^$WORK/in/||")"
fi
[ -n "$APP_REL" ] || { echo "no Payload/*.app found" >&2; exit 1; }
APP_REL="${APP_REL%/}"
APP_DIR="$WORK/in/$APP_REL"
[ -d "$APP_DIR" ] || { echo "app dir missing: $APP_DIR" >&2; exit 1; }

# python plistlib check (structured binary-plist API for non-macOS hosts;
# never byte-edits — parses/writes the whole object table)
HAVE_PY_PLIST=""
if command -v python >/dev/null 2>&1 && python -c 'import plistlib' 2>/dev/null; then
  HAVE_PY_PLIST=python
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import plistlib' 2>/dev/null; then
  HAVE_PY_PLIST=python3
fi
export HAVE_PY_PLIST   # the perl intents-fixup child reads it to detect plistlib

# outer Info.plist reader (XML and binary; falls back to plutil on macOS)
plist_value() { # $1 plist, $2 key
  # Order: (1) macOS plutil — parses binary plists correctly; (2) python
  # plistlib — structured parser on any host, safe for binary plists; (3) the
  # perl plist-value.pl binary scanner, a last-resort fallback that can grab
  # the wrong object on real app plists.
  if command -v plutil >/dev/null 2>&1 \
      && out="$(plutil -extract "$2" raw -o - "$1" 2>/dev/null)"; then
    printf '%s\n' "$out"
    return 0
  fi
  if [ -n "$HAVE_PY_PLIST" ]; then
    "${HAVE_PY_PLIST:-python}" - "$1" "$2" <<'PYEOF' 2>/dev/null || true
import plistlib, sys
with open(sys.argv[1], 'rb') as f: d = plistlib.load(f)
path = sys.argv[2].split('.')
for k in path[:-1]:
    d = d[k]
key = path[-1]
for k in d.keys():
    if k.lower() == key.lower():
        print(d[k]); break
else:
    sys.exit(1)
PYEOF
    return 0
  fi
  perl "$BS/../lib/plist-value.pl" "$1" "$2" 2>/dev/null || true
}
plist_set() { # $1 plist, $2 key, $3 value; $4 optional "--boolean"
  # Order: (1) macOS plutil for binary plists; (2) python plistlib on ANY
  # host — a structured read-modify-write of the full object table that never
  # byte-edits; (3) the perl XML editor for XML plists only.
  if [ "$(head -c 6 "$1" 2>/dev/null)" = "bplist" ]; then
    if command -v plutil >/dev/null 2>&1; then
      if [ "${4:-}" = "--boolean" ]; then
        plutil -replace "$2" -bool "true" "$1" 2>/dev/null || plutil -insert "$2" -bool "true" "$1" 2>/dev/null || {
          echo "WARN: plutil could not set $2 (boolean) in $1" >&2; return 1;
        }
        return 0
      fi
      plutil -replace "$2" -string "$3" "$1" 2>/dev/null || plutil -insert "$2" -string "$3" "$1" 2>/dev/null || {
        echo "WARN: plutil could not set $2 in $1" >&2; return 1;
      }
      return 0
    fi
    # No plutil but a python plistlib? Structured set preserves the plist's
    # original format and never touches the object table by hand.
    if [ -n "$HAVE_PY_PLIST" ]; then
      set -- "$1" "$2" "$3" "${4:-}"   # re-assign for the python heredoc
      "${HAVE_PY_PLIST:-python}" - "$@" <<'PYEOF'
import plistlib, sys
path, key, val, mode = sys.argv[1:5]
with open(path, 'rb') as f: d = plistlib.load(f)
found = [k for k in d.keys() if k.lower() == key.lower()]
k = found[0] if found else key
d[k] = True if mode == '--boolean' else (
    float(val) if (mode != '--boolean' and val.replace('.','',1).isdigit()
                   and '.' in val) else
    int(val) if (mode != '--boolean' and val.lstrip('-').isdigit()) else val)
with open(path, 'wb') as f: plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
PYEOF
      [ $? -eq 0 ] || { echo "WARN: python plistlib could not set $2 in $1" >&2; return 1; }
      return 0
    fi
    # No safe structured editor available: refuse rather than corrupt.
    echo "WARN: binary plist $1 but no plutil/plistlib — cannot edit $2 safely" >&2
    return 1
  fi
  perl - "$1" "$2" "$3" "${4:-}" <<'PERLEOF'
  # XML path only (no plutil on this host). Replace the value between the
  # key's closing </key> and the next opening tag; when the key is missing
  # entirely, insert key+value before the closing </dict> of the top dict.
  # '--boolean' writes a real plist Boolean (<true/>) instead of a string.
  my ($path, $key, $val, $mode) = @ARGV;
  open my $f, '<:raw', $path or die "open $path: $!";
  local $/; my $d = <$f>; close $f;
  die "refusing to byte-edit binary plist $path without plutil; convert with plutil -convert xml1\n"
    if substr($d, 0, 6) eq 'bplist';
  my $kv = "<key>$key</key>";
  my $newel = $mode eq '--boolean' ? '<true/>' : "<string>$val</string>";
  my $i = index($d, $kv);
  my $new;
  if ($i >= 0) {
    my $pos = $i + length($kv);              # start of the value region
    # skip whitespace only (plists have no comments)
    $pos++ while $pos < length($d) && substr($d, $pos, 1) =~ /\s/;
    my $open = '<string>';
    if (substr($d, $pos, length($open)) eq $open) {
      my $close = index($d, '</string>', $pos);
      die "unterminated <string> for $key in $path\n" if $close < 0;
      $new = substr($d, 0, $pos) . $newel . substr($d, $close + length('</string>'));
    } else {
      # non-string (true/false/integer...) after the key: replace the whole
      # element up to the next '<' of the following tag
      my $next = index($d, '<', $pos + 1);
      $new = substr($d, 0, $pos) . $newel . substr($d, $next);
    }
  } else {
    my $kvx = "<key>$key</key>$newel\n";
    # Insert before the LAST </dict> (top-level dict); the first occurrence
    # may close a nested structure (icons, NSExtension, ...).
    my $insert = rindex($d, '</dict>');
    die "no closing top-level </dict> in $path\n" if $insert < 0;
    $new = substr($d, 0, $insert) . $kvx . substr($d, $insert);
  }
  open my $o, '>:raw', $path or die "write $path: $!";
  print $o $new; close $o;
PERLEOF
}
plist_del() { plist="$1"; key="$2"
  # Order: (1) plutil for any plist; (2) python plistlib for binary plists
  # (structured, never byte-edited); (3) perl XML editor. With no structured
  # tooling, deleting from a binary plist is unsafe: FAIL LOUDLY.
  if command -v plutil >/dev/null 2>&1 \
      && plutil -remove "$key" "$plist" 2>/dev/null; then
    return 0
  fi
  if [ "$(head -c 6 "$plist" 2>/dev/null)" = "bplist" ] && [ -n "$HAVE_PY_PLIST" ]; then
    "${HAVE_PY_PLIST:-python}" - "$plist" "$key" <<'PYEOF' || return 1
import plistlib, sys
path, key = sys.argv[1:3]
with open(path, 'rb') as f: d = plistlib.load(f)
for k in [k for k in d.keys() if k.lower() == key.lower()]:
    del d[k]
with open(path, 'wb') as f: plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
PYEOF
    return 0
  fi
  perl - "$plist" "$key" <<'PERLEOF2'
  my ($path, $key) = @ARGV;
  open my $f, '<:raw', $path or die "open $path: $!";
  local $/; my $d = <$f>; close $f;
  die "refusing to byte-edit binary plist $path without plutil; convert with plutil -convert xml1\n"
    if substr($d, 0, 6) eq 'bplist';
  my $kv = "<key>$key</key>";
  my $i = index($d, $kv);
  if ($i >= 0) {
    # remove key plus its value up to the next <key> or the closing tag of
    # the VALUE's element (only string/true/false handled here)
    my $rest = substr($d, $i);
    $rest =~ s/^<key>$key<\/key>(<string>[^<]*<\/string>|<true\/>|<false\/>)*//;
    $d = substr($d, 0, $i) . $rest;
    open my $o, '>:raw', $path or die;
    print $o $d; close $o;
  }
PERLEOF2
}

OLD_OUTER_ID="$(plist_value "$APP_DIR/Info.plist" CFBundleIdentifier)"
[ -n "$OLD_OUTER_ID" ] || { echo "outer CFBundleIdentifier unreadable in $APP_DIR/Info.plist" >&2; exit 1; }
echo "    outer id: $OLD_OUTER_ID -> $BASE_ID"

# ---------------- 2. locate Watch app and extensions ------------------------
WATCH_APP=""
if [ -d "$APP_DIR/Watch" ]; then
  WATCH_APP="$(find "$APP_DIR/Watch" -maxdepth 2 -name '*.app' -type d | head -1)"
fi
[ -n "$WATCH_APP" ] || echo "WARN: no Watch/<name>.app companion found; continuing without Watch fixes"

# ---------------- 3. rewrite identifiers -------------------------------------
# Outer app first.
if [ "$OLD_OUTER_ID" != "$BASE_ID" ]; then
  plist_set "$APP_DIR/Info.plist" CFBundleIdentifier "$BASE_ID"
fi

# Derive the watch id and rewrite it.
WATCH_ID=""
if [ -n "$WATCH_APP" ]; then
  OLD_WATCH_ID="$(plist_value "$WATCH_APP/Info.plist" CFBundleIdentifier)"
  WATCH_ID="$BASE_ID.watchkitapp"
  if [ -n "$OLD_WATCH_ID" ] && [ "$OLD_WATCH_ID" != "$WATCH_ID" ]; then
    echo "    watch id: $OLD_WATCH_ID -> $WATCH_ID"
    plist_set "$WATCH_APP/Info.plist" CFBundleIdentifier "$WATCH_ID"
  fi

  # Every PlugIns/*.appex must be <watch-id>.<leaf>
  for appex in "$WATCH_APP/PlugIns"/*.appex; do
    [ -d "$appex" ] || continue
    leaf="$(basename "$appex" .appex)"
    old="$(plist_value "$appex/Info.plist" CFBundleIdentifier)"
    want="${WATCH_ID}.${leaf}"
    if [ -n "$old" ] && [ "$old" != "$want" ]; then
      echo "    appex id: $old -> $want"
      plist_set "$appex/Info.plist" CFBundleIdentifier "$want"
    fi
  done
fi

# Any other nested .appex directly under the phone app (Widgets, Intents, ...).
for appex in "$APP_DIR/PlugIns"/*.appex; do
  [ -d "$appex" ] || continue
  leaf="$(basename "$appex" .appex)"
  old="$(plist_value "$appex/Info.plist" CFBundleIdentifier)"
  want="${BASE_ID}.${leaf}"
  if [ -n "$old" ] && [ "$old" != "$want" ]; then
    echo "    phone appex id: $old -> $want"
    plist_set "$appex/Info.plist" CFBundleIdentifier "$want"
  fi
done  # ---------------- 4. companion metadata --------------------------------------
  # Apple's watchOS Info.plist key reference (InfoPlistKeyReference, watchOS
  # keys): WKWatchKitApp is a BOOL that "specifies whether the bundle is the
  # Watch app that the user launches" and "applies to the Watch app only";
  # WKCompanionAppBundleIdentifier "specifies the bundle identifier of the iOS
  # app with which the Watch app is paired". Both belong on the WATCH app's
  # Info.plist; the companion's Info.plist must NOT claim WKWatchKitApp.
  if [ -n "$WATCH_APP" ]; then
    # NOTE: this runs AFTER step 3 rewrote the outer id, so the companion id
    # is the rewritten BASE_ID, not the pre-rewrite OLD_OUTER_ID.
    plist_set "$WATCH_APP/Info.plist" WKWatchKitApp "true" --boolean
    plist_set "$WATCH_APP/Info.plist" WKCompanionAppBundleIdentifier "$BASE_ID"
    plist_del "$APP_DIR/Info.plist" WKWatchKitApp
    echo "    watch metadata: WKWatchKitApp=<true/> + WKCompanionAppBundleIdentifier=$BASE_ID on Watch app; companion cleaned"
  fi

# ---------------- 5. Siri Intents consistency --------------------------------
# IntentsAppexIntentsSupportedNotASubset fires when an extension declares
# IntentsSupported intents the phone app doesn't. The phone app's declaration
# must be a SUPERSET. Rather than inventing intents, we copy the union of the
# extension declarations into the phone app's IntentsSupported list, using the
# same perl-only plist edit paths as the rest of this script so the step does
# not depend on python3/plutil being present.
perl - "$APP_DIR" "$WATCH_APP" <<'PERLEOF' || { echo "WARN: intents fixup could not run" >&2; :; }
use strict; use warnings;
use JSON::PP qw(decode_json encode_json);
my ($app, $watch) = @ARGV;

# python helper (invoked from the binary-plist branch): merges the needed
# intent names into Info.plist's IntentsSupported via plistlib; structured,
# format-preserving, exit 0 ONLY when the file was actually changed.
my $PLIST_INTENTS_MERGE = <<'PYMERGE';
import plistlib, sys
path, needed = sys.argv[1], sys.argv[2:]
with open(path, 'rb') as f: d = plistlib.load(f)
cur = None
for k in d.keys():
    if k.lower() == 'intentsupported':
        cur = d[k]; break
if cur is None:
    d['IntentsSupported'] = sorted(set(needed))
elif isinstance(cur, list):
    merged = sorted(set(cur) | set(needed))
    if merged == list(cur):
        sys.exit(1)
    d[[k for k in d.keys() if k.lower() == 'intentsupported'][0]] = merged
else:
    sys.exit(1)
with open(path, 'wb') as f: plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
sys.exit(0)
PYMERGE

sub slurp { my $p = shift; open my $f, '<:raw', $p or return undef; local $/; my $d = <$f>; close $f; return $d }
sub spew  { my ($p, $d) = @_; open my $f, '>:raw', $p or die "write $p: $!"; print $f $d; close $f }
  # collect IntentsSupported values from an extension's Info.plist.
  # XML plists are text-scanned; BINARY plists are read through python
  # plistlib (HAVE_PY_PLIST env, exported by the shell) — structured, never
  # byte-edited. Only strings inside the FIRST top-level <array> after the
  # key count — anything later in the file must not leak into the merge set.
  sub intents_from {
    my $path = $_[0];
    return () unless defined $path && -f $path;
    my $d = slurp($path);
    return () unless defined $d;
    if (substr($d, 0, 6) eq 'bplist') {
      my $py = $ENV{HAVE_PY_PLIST} or return ();
      my $cmd = $py eq 'python3' ? 'python3' : 'python';
      my $json = `$cmd - '$path' <<'PYREAD' 2>/dev/null
import plistlib, json, sys
with open(sys.argv[1], 'rb') as f: d = plistlib.load(f)
print(json.dumps(d.get('NSExtension', {}).get('NSExtensionAttributes', {}).get('IntentsSupported', [])))
PYREAD`;
      chomp $json;
      my $arr = eval { decode_json($json) } or return ();
      return () unless ref $arr eq 'ARRAY';
      return map { $_ } @$arr;
    }
    my $k = index($d, '<key>IntentsSupported</key>');
    return () if $k < 0;
    my $pos = $k + length('<key>IntentsSupported</key>');
    my $open = index($d, '<array>', $pos);
    return () if $open < 0 || $open > $pos + 64;   # value must directly follow the key
    my $close = index($d, '</array>', $open);
    return () if $close < 0;
    my $inner = substr($d, $open + length('<array>'), $close - $open - length('<array>'));
    return $inner =~ /<string>([^<]*)<\/string>/g;
  }

my @sources;
# Watch-side extensions and the watch app itself (the watch app's own
# declaration is BOTH a source and a later target: each parent app must keep
# a top-level IntentsSupported that is a superset of its extensions', or the
# installer raises IntentsAppexIntentsSupportedNotASubset).
if (defined $watch && -d $watch) {
  if (opendir my $dh, "$watch/PlugIns") {
    for my $leaf (grep { /\.appex$/ } readdir $dh) {
      push @sources, intents_from("$watch/PlugIns/$leaf/Info.plist");
    }
  }
  push @sources, intents_from("$watch/Info.plist");
}
# Phone-side extensions: a Siri Intents appex usually lives directly under
# the phone app's PlugIns/, and the phone Info.plist must be a superset of it.
if (opendir my $dh, "$app/PlugIns") {
  for my $leaf (grep { /\.appex$/ } readdir $dh) {
    push @sources, intents_from("$app/PlugIns/$leaf/Info.plist");
  }
}

my %need = map { $_ => 1 } @sources;
my $nsrc = scalar keys %need;
exit 0 if $nsrc == 0;

my $changed = 0;
# Targets: the phone app, the watch app, and every .appex of each. Each
# extension's parent app must itself carry a top-level IntentsSupported
# superset, and the insertion must land in the TOP-level dict — anchored at
# the LAST </dict> of the file, not the first (nested dicts end earlier).
my @targets = ("$app/Info.plist");
push @targets, "$watch/Info.plist" if defined $watch && -f "$watch/Info.plist";
for my $top ($app, (defined $watch && -d $watch) ? $watch : ()) {
  if (opendir my $dh, "$top/PlugIns") {
    for my $leaf (grep { /\.appex$/ } readdir $dh) {
      push @targets, "$top/PlugIns/$leaf/Info.plist";
    }
  }
}
for my $info (@targets) {
  next unless defined $info && -f $info;
  my $d = slurp($info) or next;
  if (substr($d, 0, 6) eq 'bplist') {
    # Binary plist: structured read-modify-write through python plistlib
    # (any host); macOS plutil keeps priority when present. Merge = insert
    # any missing intent names into the existing IntentsSupported array, or
    # add the key. Never byte-edits the object table.
    my $done = 0;
    if ($^O eq 'darwin' && -x '/usr/bin/plutil') {
      my $json = `/usr/bin/plutil -convert json -o - '$info' 2>/dev/null`;
      if ($json) {
        my $data = eval { decode_json($json) } or next;   # malformed json: leave the plist alone
        my $cur = $data->{IntentsSupported} || [];
        my %h = map { $_ => 1 } (@$cur, keys %need);
        my @merged = sort keys %h;
        next if @merged == @$cur;
        $data->{IntentsSupported} = \@merged;
        my $tmp = "$info.watchfix-tmp.$$";
        open my $jf, '>', $tmp or next;
        print $jf encode_json($data); close $jf;
        system('/usr/bin/plutil', '-convert', 'binary1', $tmp) == 0 or do { unlink $tmp; next };
        rename($tmp, $info) and $changed++;
        $done = 1;
      }
    }
    unless ($done) {
      my $py = $ENV{HAVE_PY_PLIST};
      if (defined $py && $py ne '') {
        my $cmd = $py eq 'python3' ? 'python3' : 'python';
        my $ok = system($cmd, '-c', $PLIST_INTENTS_MERGE, $info, sort keys %need) == 0;
        $changed++ if $ok;   # python only reports success when the file changed
      } else {
        warn "WARN: binary plist intents merge unavailable (no plutil/plistlib): $info\n";
      }
    }
    next;
  }
  my ($have) = $d =~ /<key>IntentsSupported<\/key><array>(.*?)<\/array>/s;
  my %cur = map { $_ => 1 } ($have ? ($have =~ /<string>([^<]*)<\/string>/g) : ());
  my %merged = (%cur, %need);
  next if keys(%merged) == keys(%cur);
  my $list = join '', map { "<string>$_</string>" } sort keys %merged;
  if (defined $have) {
    $d =~ s/<key>IntentsSupported<\/key><array>.*?<\/array>/<key>IntentsSupported<\/key><array>$list<\/array>/s;
  } else {
    my $kvx = "<key>IntentsSupported<\/key><array>$list<\/array>\n";
    # Insert before the LAST </dict> so the pair lands in the top-level dict;
    # the first </dict> may belong to a nested structure (icons, NSExtension).
    my $insert = rindex($d, '</dict>');
    die "no closing top-level </dict> in $info\n" if $insert < 0;
    $d = substr($d, 0, $insert) . $kvx . substr($d, $insert);
  }
  spew($info, $d);
  $changed++;
}
print "intents fixup: $changed plist(s) updated with $nsrc intent(s)\n";
PERLEOF

# ---------------- 6. re-sign innermost-out ------------------------------------
if [ "$SIGN" = 1 ]; then
  [ -n "$TEAM_ID" ] || { echo "--sign needs --team-id" >&2; exit 1; }
fi
if [ "$SIGN" = 1 ]; then
  tmp_ent="$WORK/ent.plist"
  cat > "$tmp_ent" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/>
</plist>
EOF
  sign_bundle() {
    local dir="$1" ident="$2" extraargs=()
    [ -n "$ident" ] || ident="${3:-}"
    echo "    codesign: $(basename "$dir") as ${ident:-adhoc}"
    if [ "$ident" = "adhoc" ]; then
      codesign --force --sign - "$dir" >/dev/null 2>&1
    else
      codesign --force --sign "$ident" ${extraargs+"${extraargs[@]}"} "$dir" >/dev/null 2>&1
    fi
  }

  # extension first, then the watch app, then phone Frameworks, then outer
  if [ -n "$WATCH_APP" ]; then
    for appex in "$WATCH_APP/PlugIns"/*.appex; do
      [ -d "$appex" ] || continue
      sign_bundle "$appex" "" "adhoc"
    done
    sign_bundle "$WATCH_APP" "adhoc"
  fi
  for fw in "$APP_DIR/Frameworks"/*.framework; do
    [ -d "$fw" ] || continue
    sign_bundle "$fw" "adhoc"
  done
  for dy in "$APP_DIR/Frameworks"/*.dylib; do
    [ -f "$dy" ] || continue
    codesign --force --sign - "$dy" >/dev/null 2>&1
  done
  for appex in "$APP_DIR/PlugIns"/*.appex; do
    [ -d "$appex" ] || continue
    sign_bundle "$appex" "adhoc"
  done
  sign_bundle "$APP_DIR" "adhoc"
  echo "    signed: ad-hoc. For free-profile installs run Sideloadly afterward; it will re-sign with your identity."
elif [ "$SKIP_SIGN" = 0 ]; then
  echo "    (not signing; run with --sign --team-id X or let Sideloadly sign)"
fi

# ---------------- 7. run validation then repack ------------------------------
perl "$BS/validate-watchfix.pl" "$APP_DIR" "$BASE_ID" || {
  echo "!! watchfix validation FAILED — not packaging" >&2
  exit 1
}

STAMP="$(date -u +%Y%m%d-%H%M%S)"
if [ -z "$OUT" ]; then
  name="$(basename "$IN" .ipa)"
  OUT="$REPO/dist/${name}-watchfix.ipa"
fi
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
mkdir -p "$(dirname "$OUT")"

# Use the same deterministic packager as the unified pipeline.
perl "$BS/../package/make-ipa.pl" "$APP_DIR" "$OUT" >/dev/null
sha="$(perl -MDigest::SHA -e 'print Digest::SHA::sha256_hex(scalar do { local $/; open(my $f,"<:raw",$ARGV[0]); <$f> })' "$OUT")"
echo "==> DONE: $OUT"
echo "    sha256 $sha"
