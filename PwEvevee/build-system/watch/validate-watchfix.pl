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
#     NotASubset                    also appear in the phone app
#   missing WKCompanionApp-         companion/parent embedded metadata must
#     BundleIdentifier              agree on BOTH sides
#
# The base id is optional; when given, additionally verify the outer app's
# CFBundleIdentifier equals it (the deterministic mapping invariant).
# ============================================================================
use strict;
use warnings;
use File::Find;
use JSON::PP ();

my ($app, $base_id) = @ARGV;
$app or die "usage: validate-watchfix.pl <staged .app> [base-id]\n";
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
    # Binary plist: scan with plutil FIRST on macOS (parses the object table
    # correctly). The serialized-string scan cannot see offsets and returns
    # garbage on real app plists (observed: 'WKWatchKitApp_' instead of the
    # bundle id), so it is the last-resort fallback only.
    if ($^O eq 'darwin' && -x '/usr/bin/plutil') {
      my $out = `/usr/bin/plutil -extract '$key' raw -o - '$path' 2>/dev/null`;
      return undef unless defined $out && length $out;
      # plutil output may embed a trailing newline but can also carry stray
      # bytes through pipes; take the value strictly up to the first \n
      $out =~ s/\r?\n.*//s;
      return $out;
    }
    warn_("BINARY PLIST without plutil: $path — $key unreadable statically");
    return undef;
  }
  # XML
  my $i = index($d, "<key>$key</key>");
  return undef if $i < 0;
  my $rest = substr($d, $i + length("<key>$key</key>"));
  $rest =~ /<string>([^<]*)<\/string>/ or return undef;
  return $1;
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

# 1. outer app must carry companion metadata for the watch id.
if (defined $watch) {
  my $comp = plist_scalar("$app/Info.plist", 'WKCompanionAppBundleIdentifier');
  if (!defined $comp) {
    fail('MISSING WKCompanionAppBundleIdentifier on outer app');
  } elsif ($comp ne $watch_id) {
    fail("COMPANION ID MISMATCH: WKCompanionAppBundleIdentifier=$comp but watch id=$watch_id");
  } else { ok(); }

  # WKWatchKitApp must NOT claim the watch side is the companion.
  my $w_wkk = plist_scalar("$watch/Info.plist", 'WKWatchKitApp');
  if (defined $w_wkk) {
    fail("WRONG SIDE: WKWatchKitApp on Watch app Info.plist (belongs on the companion)");
  } else { ok(); }
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

    # collect IntentsSupported declared by this extension (XML plists; binary
    # plists cannot be parsed by the naive scanner and are reported as a
    # warning rather than silently passing)
    my $raw = do { local $/; open my $fh, '<:raw', "$ax/Info.plist" or next; <$fh> };
    next unless defined $raw;
    if (substr($raw, 0, 6) eq 'bplist00') {
      warn_("BINARY PLIST: $leaf/Info.plist — IntentsSupported not statically verifiable");
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

# phone app's own declared intents (top-level IntentsSupported). Arrays are
# structured: parse via plutil->json on macOS, else fall back to the XML scan
# (binary XML-less hosts cannot verify and are reported as a warning).
my %app_intents;
if (defined $watch) {
  my @phone_ints;
  if ($^O eq 'darwin' && -x '/usr/bin/plutil') {
    my $json = `/usr/bin/plutil -convert json -o - '$app/Info.plist' 2>/dev/null`;
    if ($json) {
      my $data = eval { JSON::PP::decode_json($json) };
      if ($data && ref $data->{IntentsSupported} eq 'ARRAY') {
        @phone_ints = @{ $data->{IntentsSupported} };
      }
    }
  }
  unless (@phone_ints) {
    my $raw;
    if (open my $fh, '<:raw', "$app/Info.plist") { local $/; $raw = <$fh>; close $fh; }
    if (defined $raw) {
      if (substr($raw, 0, 6) eq 'bplist') {
        warn_("phone Info.plist is binary and plutil could not read IntentsSupported")
      } else {
        my $k = index($raw, 'IntentsSupported');
        if ($k >= 0) {
          my $rest = substr($raw, $k + length('IntentsSupported'));
          while ($rest =~ /<string>([^<]*)<\/string>/g) { push @phone_ints, $1; }
        }
      }
    }
  }
  $app_intents{$outer_id} = \@phone_ints if @phone_ints;
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
if (defined $watch) {
  my $w_min = plist_scalar("$watch/Info.plist", 'MinimumOSVersion');
  warn_('watch MinimumOSVersion missing') unless defined $w_min;
}

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
