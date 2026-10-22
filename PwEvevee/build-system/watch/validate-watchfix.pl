#!/usr/bin/env perl
# ============================================================================
# validate-watchfix.pl — structural checks for a Spotify.app with a Watch app.
#
#   PwEvevee/build-system/watch/validate-watchfix.pl <staged .app> [base-id]
#
# Everything checked here corresponds to a real iTunes/App Store install
# validation error class:
#
#   AppexBundleIDNotPrefixed        every .appex id must start with the
#                                   id of its containing bundle
#   IntentsAppexIntentsSupported-   every intent an extension declares must
#     NotASubset                    also appear in its parent app
#   Watch-app pair metadata         per Apple's watchOS Info.plist key
#     (schema violation)            reference, WKWatchKitApp (Boolean) and
#                                   WKCompanionAppBundleIdentifier live on
#                                   the WATCH app's Info.plist; the companion
#                                   must NOT claim WKWatchKitApp
#
# The base id is optional; when given, additionally verify the outer app's
# CFBundleIdentifier equals it (the deterministic mapping invariant).
#
# Prefixed-with-a-dot detection (--catch-double-prefix): an OUTER id that is
# 'a.b.' or ends with '.' is caught by the normal MISMATCH check when a base
# id is supplied; this flag additionally rejects such ids with no base id
# given. Used by the double-prefix regression test.
# ============================================================================
use strict;
use warnings;
use File::Find;
use JSON::PP ();

# python plistlib detection: a structured binary-plist parser on every host
# (macOS plutil OR any host with python). Never byte-edits.
my $py;
foreach my $c ('python', 'python3') {
  my $probe = `$c -c 'import plistlib' 2>&1`;
  if (defined $probe && $probe eq '') { $py = $c; last; }
}
my $have_plistlib = defined $py ? 1 : 0;

# structured reader for one key: returns a hash { type, value } or undef
sub plistlib_read {
  my ($path, $key) = @_;
  return undef unless $have_plistlib;
  my $json = `$py - "$path" "$key" <<'PYEOF' 2>&1
import plistlib, sys, json
with open(sys.argv[1], 'rb') as f: d = plistlib.load(f)
for k in d.keys():
    if k.lower() == sys.argv[2].lower():
        v = d[k]
        t = 'boolean' if isinstance(v, bool) else 'string' if isinstance(v, str) else 'other'
        print(json.dumps({'type': t, 'value': v}))
        sys.exit(0)
sys.exit(1)
PYEOF`;
  return undef unless defined $json && $json =~ /^\{/;
  my $data = eval { JSON::PP::decode_json($json) };
  return $data;
}
# structured reader for the FULL array under one key
sub plistlib_read_array {
  my ($path, $key) = @_;
  return () unless $have_plistlib;
  my $json = `$py - "$path" "$key" <<'PYEOF' 2>&1
import plistlib, sys, json
with open(sys.argv[1], 'rb') as f: d = plistlib.load(f)
for k in d.keys():
    if k.lower() == sys.argv[2].lower():
        v = d[k]
        print(json.dumps(v if isinstance(v, list) else [v]))
        sys.exit(0)
sys.exit(1)
PYEOF`;
  return () unless defined $json && $json =~ /^\[/;
  my $data = eval { JSON::PP::decode_json($json) };
  return ref $data eq 'ARRAY' ? @$data : ();
}

my $catch_double = 0;
my @pos = grep { defined && $_ ne '' && $_ ne '--catch-double-prefix' } @ARGV;
$catch_double = 1 if scalar(@pos) != scalar(grep { defined && $_ ne '' } @ARGV);
my ($app, $base_id) = @pos;
$app or die "usage: validate-watchfix.pl <staged .app> [base-id] [--catch-double-prefix]\n";
$app =~ s{/+$}{};

my (@fail, @warn);
my $pass = 0;
sub ok { $pass++ }
sub fail { push @fail, shift }
sub warn_ { push @warn, shift }

# --- minimal plist reader: XML <key>..</key><string>..</string>, and raw
#     binary-plist best-effort for the string values we care about.
sub plist_scalar {
  my ($path, $key) = @_;
  return undef unless -f $path;
  open my $fh, '<:raw', $path or do { fail("READ: $path ($!)"); return undef };
  local $/; my $d = <$fh>; close $fh;
  if (substr($d, 0, 6) eq 'bplist') {
    # Order: (1) python plistlib — structured, works on every host and parses
    # the object table correctly; (2) macOS plutil; (3) warn + give up. The
    # serialized-string scan is NOT used: it cannot see offsets and returns
    # garbage on real app plists (observed: 'WKWatchKitApp_' for a bundle id).
    my $struct = plistlib_read($path, $key);
    if (defined $struct && $struct->{type} ne 'other') { return $struct->{value} }
    if (defined $struct && $struct->{type} eq 'other') {
      return undef;   # non-scalar (array/dict) is not a string value here
    }
    if ($^O eq 'darwin' && -x '/usr/bin/plutil') {
      my $out = `/usr/bin/plutil -extract '$key' raw -o - '$path' 2>/dev/null`;
      return undef unless defined $out && length $out;
      # plutil output may embed a trailing newline but can also carry stray
      # bytes through pipes; take the value strictly up to the first \n
      $out =~ s/\r?\n.*//s;
      return $out;
    }
    warn_("BINARY PLIST without plutil/plistlib: $path — $key unreadable statically");
    return undef;
  }
  # XML: capture the top-level <key> and support string AND Boolean values
  my $i = index($d, "<key>$key</key>");
  return undef if $i < 0;
  my $rest = substr($d, $i + length("<key>$key</key>"));
  $rest =~ /<string>([^<]*)<\/string>/ or return undef;
  return $1;
}

# Type-aware reader: returns (value, 'string'|'boolean'|undef) and reports a
# clear failure when the key is present with an unsupported/empty XML value.
# Note: plist_scalar is deliberately retained for callers that only handle
# strings (bundle ids, version strings); use plist_typed for Boolean keys.
sub plist_typed {
  my ($path, $key) = @_;
  return (undef, undef) unless -f $path;
  open my $fh, '<:raw', $path or do { fail("READ: $path ($!)"); return (undef, undef) };
  local $/; my $d = <$fh>; close $fh;
  if (substr($d, 0, 6) eq 'bplist') {
    # plistlib first (structured, type-aware, any host); plutil on macOS.
    my $struct = plistlib_read($path, $key);
    if (defined $struct) {
      if ($struct->{type} eq 'boolean') {
        return ($struct->{value} ? (1, 'boolean') : (0, 'boolean'));
      }
      if ($struct->{type} eq 'string') { return ($struct->{value}, 'string') }
      return (undef, undef);   # array/dict/other: not a scalar for this check
    }
    if ($^O eq 'darwin' && -x '/usr/bin/plutil') {
      my $out = `/usr/bin/plutil -extract '$key' raw -o - '$path' 2>/dev/null`;
      return (undef, undef) unless defined $out && length $out;
      $out =~ s/\r?\n.*//s;
      if (index($out, 'true') == 0) { return (1, 'boolean'); }
      if (index($out, 'false') == 0) { return (0, 'boolean'); }
      return ($out, 'string');
    }
    warn_("BINARY PLIST without plutil/plistlib: $path — $key unreadable statically");
    return (undef, undef);
  }
  my $i = index($d, "<key>$key</key>");
  return (undef, undef) if $i < 0;
  my $rest = substr($d, $i + length("<key>$key</key>"));
  if ($rest =~ /<true\/>/) { return (1, 'boolean'); }
  if ($rest =~ /<false\/>/) { return (0, 'boolean'); }
  if ($rest =~ /<string>([^<]*)<\/string>/) { return ($1, 'string'); }
  fail("UNREADABLE VALUE for $key in $path (unsupported plist element type)");
  return (undef, undef);
}

# outer app id
my $outer_id = plist_scalar("$app/Info.plist", 'CFBundleIdentifier');
fail('MISSING outer CFBundleIdentifier') unless defined $outer_id;

if (defined $base_id) {
  if ($outer_id ne $base_id) {
    fail("OUTER ID MISMATCH: $outer_id != $base_id (--base-id)");
  } else { ok(); }
}

my $watch = undef;
for my $cand ("$app/Watch/WatchApp.app", "$app/Watch/SpotifyWatch.app") {
  if (-d $cand) { $watch = $cand; last; }
}
unless ($watch) {
  my $dh;
  opendir $dh, "$app/Watch" or undef $dh;
  if ($dh) {
    for my $e (readdir $dh) {
      next if $e eq '.' || $e eq '..';
      if ($e =~ /\.app$/ && -d "$app/Watch/$e") { $watch = "$app/Watch/$e"; last; }
    }
  }
}
unless ($watch) {
  warn_('NO WATCH APP: no Watch/<name>.app inside ' . $app);
}

my $watch_id = defined $watch
  ? plist_scalar("$watch/Info.plist", 'CFBundleIdentifier')
  : undef;

fail('MISSING watch CFBundleIdentifier') if defined $watch && !defined $watch_id;

# 1. embedded Watch app must carry the Apple-documented pair metadata;
#    the OUTER (companion) app must NOT claim WKWatchKitApp.
if (defined $watch) {
  my $w = "$watch/Info.plist";
  my ($wkk, $wkk_type) = plist_typed($w, 'WKWatchKitApp');
  if (!defined $wkk && !defined $wkk_type) {
    my $raw_present = undef;
    if (open my $fh, '<:raw', $w) { local $/; $raw_present = index(<$fh>, '<key>WKWatchKitApp</key>') >= 0; close $fh; }
    if ($raw_present) {
      fail("WKWatchKitApp on Watch app has an unreadable/unsupported plist value (expected Boolean true)");
    } else {
      fail('MISSING WKWatchKitApp on Watch app Info.plist');
    }
  } elsif ($wkk_type ne 'boolean') {
    fail("WKWatchKitApp WRONG TYPE on Watch app: got '" . ($wkk // 'undef') . "' ($wkk_type), expected plist Boolean");
  } elsif (!$wkk) {
    fail('WKWatchKitApp is Boolean false on Watch app (expected true)');
  } else { ok(); }

  my $comp = plist_scalar($w, 'WKCompanionAppBundleIdentifier');
  if (!defined $comp) {
    fail('MISSING WKCompanionAppBundleIdentifier on Watch app Info.plist');
  } elsif (defined $outer_id && $comp ne $outer_id) {
    fail("COMPANION ID MISMATCH: WKCompanionAppBundleIdentifier=$comp but outer app id=$outer_id");
  } else { ok(); }

  # The companion must NOT claim the Watch role (Apple: the key "applies to
  # the Watch app only"). A string "true" is not a Boolean either.
  my ($a_wkk, $a_wkk_type) = plist_typed("$app/Info.plist", 'WKWatchKitApp');
  if (defined $a_wkk_type) {
    fail("WRONG SIDE: WKWatchKitApp on companion app Info.plist (Apple: applies to the Watch app only) — type=$a_wkk_type");
  } else {
    if (open my $fh, '<:raw', "$app/Info.plist") {
      local $/; my $d = <$fh>; close $fh;
      if (substr($d, 0, 6) ne 'bplist' && index($d, '<key>WKWatchKitApp</key>') >= 0) {
        fail('WRONG SIDE: WKWatchKitApp key present on companion app Info.plist (must be removed)');
      }
    }
    ok();
  }

  my $w_min = plist_scalar($w, 'MinimumOSVersion');
  warn_('watch MinimumOSVersion missing') unless defined $w_min;
}

# 2. every .appex id must start with its parent bundle id.
my %appex_intents;   # parent-bundle-id => [intents declared inside extensions]
my @app_dirs;
push @app_dirs, $watch if defined $watch;
push @app_dirs, $app;

for my $dir (@app_dirs) {
  opendir my $dh, "$dir/PlugIns" or next;
  my $parent_id = ($dir eq $app) ? $outer_id : $watch_id;
  for my $leaf (grep { /\.appex$/ } readdir $dh) {
    my $ax = "$dir/PlugIns/$leaf";
    next unless -d $ax;
    my $ax_id = plist_scalar("$ax/Info.plist", 'CFBundleIdentifier');
    if (!defined $ax_id) {
      fail("MISSING id for $leaf inside " . ($dir eq $app ? 'app' : 'watch'));
      next;
    }
    my $prefix = $parent_id . '.';
    if (index($ax_id, $prefix) != 0) {
      fail("APPEX NOT PREFIXED: $ax_id should start with $prefix");
    } else { ok(); }

    # double-prefix sentinel (AppexBundleIDNotPrefixed class): an id that
    # embeds its parent id's dot-terminated namespace TWICE was rewritten
    # twice (e.g. base watch id applied over an already-derived id).
    if ($catch_double) {
      my $cnt = 0;
      my $probe = "$parent_id.";
      my $p = 0;
      while (($p = index($ax_id, $probe, $p)) >= 0) { $cnt++; $p += 1; }
      if ($cnt > 1) {
        fail("APPEX DOUBLE-PREFIXED: $ax_id embeds its parent id $parent_id more than once ($cnt)");
      } else { ok() if $cnt == 1; }
    }

    # stale-namespace sentinel: an appex id still in a namespace that is NOT
    # the parent's namespace at all (i.e. it doesn't share the parent's first
    # two dot-separated components) — the exact shape that produced the real
    # AppexBundleIDNotPrefixed install failure (com.skywatch.* appex under a
    # com.spotipw.* renamed parent).
    {
      my @p = split /\./, $parent_id;
      my @a = split /\./, $ax_id;
      my $shared = 0;
      $shared++ while $shared < @p && $shared < @a && $p[$shared] eq $a[$shared];
      if ($shared < 2) {
        fail("APPEX STALE NAMESPACE: $ax_id does not share its parent's namespace ($parent_id) — stale pre-rewrite id");
      } else { ok(); }
    }

    # collect IntentsSupported declared by this extension (XML plists are
    # text-scanned; BINARY plists are read through plistlib when available)
    my $raw = do { local $/; open my $fh, '<:raw', "$ax/Info.plist" or next; <$fh> };
    next unless defined $raw;
    if (substr($raw, 0, 6) eq 'bplist00') {
      if (my @ints = plistlib_intents("$ax/Info.plist")) {
        push @{ $appex_intents{$parent_id} ||= [] }, @ints;
      } else {
        warn_("BINARY PLIST: $leaf/Info.plist — IntentsSupported not statically verifiable");
      }
      next;
    }
    my @ints;
    my $ki = index($raw, 'IntentsSupported');
    if ($ki >= 0) {
      my $rest = substr($raw, $ki + length('IntentsSupported'));
      while ($rest =~ /<string>([^<]*)<\/string>/g) {
        push @ints, $1;
        last if $rest =~ /<\/array>/;
      }
    }
    push @{ $appex_intents{$parent_id} ||= [] }, @ints;
  }
}

# structured plistlib reader: full IntentsSupported array of a plist, any host
sub plistlib_intents {
  my ($path) = @_;
  return () unless $have_plistlib;
  my $json = `$py - "$path" <<'PYINT' 2>/dev/null
import plistlib, json, sys
with open(sys.argv[1], 'rb') as f: d = plistlib.load(f)
print(json.dumps(d.get('IntentsSupported', [])))
PYINT`;
  my $arr = eval { JSON::PP::decode_json($json) };
  return () unless ref $arr eq 'ARRAY';
  return @$arr;
}

# phone app's own declared intents (top-level IntentsSupported). Arrays are
# structured: parse via plutil->json on macOS, else fall back to the XML scan
# (binary XML-less hosts cannot verify and are reported as a warning).
my %app_intents;
# Every parent app (phone and watch) must declare a top-level IntentsSupported
# superset of its extensions'. Read each parent's own Info.plist (via plutil
# on macOS; XML scan fallback elsewhere; binary plists are reported as a
# warning rather than silently passing).
my @parents = ([$outer_id, "$app/Info.plist"]);
my %parent_seen = map { $_->[0] => 1 } @parents;
for my $pdir ($app, (defined $watch ? $watch : ())) {
  next unless -d $pdir;
  my $pid = plist_scalar("$pdir/Info.plist", 'CFBundleIdentifier');
  next unless defined $pid && length $pid;
  next if $parent_seen{$pid}++;
  push @parents, [$pid, "$pdir/Info.plist"];
}
for my $pair (@parents) {
  my ($pid, $ppath) = @$pair;
  next unless -f $ppath;
  my @parent_ints;
  if ($^O eq 'darwin' && -x '/usr/bin/plutil') {
    my $json = `/usr/bin/plutil -convert json -o - '$ppath' 2>/dev/null`;
    if ($json) {
      my $data = eval { JSON::PP::decode_json($json) };
      if ($data && ref $data->{IntentsSupported} eq 'ARRAY') {
        @parent_ints = @{ $data->{IntentsSupported} };
      }
    }
  }
  unless (@parent_ints) {
    my $raw;
    if (open my $fh, '<:raw', $ppath) { local $/; $raw = <$fh>; close $fh; }
    if (defined $raw) {
      if (substr($raw, 0, 6) eq 'bplist') {
        if (my @pl = plistlib_intents($ppath)) {
          @parent_ints = @pl;
        } else {
          warn_("Info.plist of $pid is binary and plutil/plistlib could not read IntentsSupported")
        }
      } else {
        my $k = index($raw, 'IntentsSupported');
        if ($k >= 0) {
          my $rest = substr($raw, $k + length('IntentsSupported'));
          my $a = index($rest, '<array>');
          if ($a >= 0) {
            my $close = index($rest, '</array>', $a);
            if ($close >= 0) {
              my $inner = substr($rest, 0, $close);
              @parent_ints = ($inner =~ /<string>([^<]*)<\/string>/g);
            }
          }
        }
      }
    }
  }
  $app_intents{$pid} = \@parent_ints if @parent_ints;
}

# 5. subset check: every intent declared by an extension of the app must be
#    in the app's own declaration, otherwise the installer groans with
#    IntentsAppexIntentsSupportedNotASubset.
for my $parent (sort keys %appex_intents) {
  my %need = map { $_ => 1 } @{ $appex_intents{$parent} };
  my %have = map { $_ => 1 } @{ $app_intents{$parent} || [] };
  for my $i (sort keys %need) {
    unless ($have{$i}) {
      fail("INTENTS SUBSET VIOLATION: extension declares intent '$i' not present in app ($parent)");
    }
  }
}

# 6. minimum OS coherence: iPhone app MinOS < watch MinOS is normal; flag if
#    watch MinOS is missing or nonsense (e.g. lower than its appex's).
# (watch MinimumOSVersion is warned about inside the metadata block above.)

# ---- summary ----------------------------------------------------------------
if (@warn) { print "WARNINGS:\n  - $_\n" for @warn; }
if (@fail) {
  print "VALIDATION FAILED ($pass passed, " . scalar(@fail) . " failed):\n";
  print "  - $_\n" for @fail;
  exit 1;
}
print "VALIDATION PASSED ($pass checks";
print ', ' . scalar(@warn) . ' warnings' if @warn;
print ")\n";
exit 0;
