#!/usr/bin/env perl
# ============================================================================
# watchfix-tests.pl — regression tests for the watch-aware pipeline stage.
#
#   perl PwEvevee/build-system/watch/tests/watchfix-tests.pl
#
# Builds a synthetic Payload/Spotify.app tree (with a Watch/WatchApp.app,
# a WatchWidgetExtension.appex and an IntentsSupportOnlyPhoneExtension.appex)
# in a temp dir and asserts every failure class the real installer reported:
#   AppexBundleIDNotPrefixed, IntentsAppexIntentsSupportedNotASubset,
#   missing WKCompanionAppBundleIdentifier, stale WKWatchKitApp placement.
# The validator is exercised in BOTH the broken baseline state (must fail)
# and the watchfix-fixed state (must pass).
# ============================================================================
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $ROOT = abs_path(dirname(abs_path(__FILE__)) . '/../../..');
my $WATCH = "$ROOT/build-system/watch";
my $T = $ENV{TMPDIR} || '/tmp';
my $dir = "$T/watchfix-test-$$";
remove_tree($dir);
make_path($dir);

my ($pass, $fail) = (0, 0);
sub ok  { $pass++; printf "  ok  %s\n", $_[0]; }
sub nok { $fail++; printf "  FAIL %s%s\n", $_[0], defined $_[1] ? " -- $_[1]" : ''; }
sub check { my ($c, $n, $w) = @_; $c ? ok($n) : nok($n, $w); }

my $app = "$dir/Payload/Spotify.app";
my $watch = "$app/Watch/WatchApp.app";
my $widget = "$watch/PlugIns/WatchWidgetExtension.appex";
my $intents = "$app/PlugIns/InsightsIntents.appex";
make_path("$watch/PlugIns");
make_path($widget, $intents);
# make-ipa.pl self-check requires an executable + PkgInfo at the app root.
open my $ex, '>', "$app/Spotify" or die "open fake exe: $!"; print $ex "fake\n"; close $ex;
open my $pi, '>', "$app/PkgInfo" or die "open PkgInfo: $!"; print $pi "APPL????"; close $pi;

# Minimal XML plists for each level.
sub write_plist {
  my ($path, $id, %extra) = @_;
  my $extra = '';
  $extra .= "  <key>$_</key><string>$extra{$_}</string>\n" for sort keys %extra;
  open my $fh, '>', $path or die "open $path: $!";
  print $fh <<"PLIST";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$id</string>
$extra</dict></plist>
PLIST
  close $fh;
}

# Broken baseline, exactly the shape that produced the installer errors:
#   - outer id in the legacy skywatch scheme
#   - watch app already rewritten to the spotipw scheme (mismatch!)
#   - widget appex still in the old skywatch scheme (not prefixed by new watch id)
#   - no WKCompanionAppBundleIdentifier on outer app
#   - WKWatchKitApp is on the watch side (wrong side)
#   - intents extension declares an intent the phone app lacks
write_plist("$app/Info.plist", 'com.skywatch.spotify');
write_plist("$watch/Info.plist", 'com.spotipw.client.3522J7W583.watchkitapp', 'WKWatchKitApp' => 'true');
write_plist("$widget/Info.plist", 'com.skywatch.spotify.watchkitapp.widget');
write_plist("$intents/Info.plist", 'com.skywatch.spotify.intents');

open my $fh, '>', "$intents/Info.plist" or die;
print $fh <<"PLISTI";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.skywatch.spotify.intents</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionAttributes</key><dict>
      <key>IntentsSupported</key><array><string>SendMessageIntent</string></array>
    </dict></dict>
  </dict></plist>
PLISTI
close $fh;

my $chk = sub { system($^X, "$WATCH/validate-watchfix.pl", $app) };

# ---- test 1: baseline fails ----
{
  my $out = qx($^X $WATCH/validate-watchfix.pl $app 2>&1);
  my $rc = $?;
  check($rc != 0, 'baseline broken tree FAILS validation') or note_out($out);
  for my $err ('APPEX NOT PREFIXED', 'INTENTS SUBSET VIOLATION', 'COMPANION ID MISMATCH', 'WRONG SIDE') {
    ok(index($out, $err) >= 0, "baseline identifies: $err")
      or diag("missing '$err' in output:\n$out");
  }
}

sub note_out { }
sub diag { printf "    [diag] %s\n", $_[0] for split /\n/, $_[1]; }

# ---- test 2: watchfix.sh --skip-sign fixes everything ----
{
  # fake input IPA out of the tree
  # build a stage-only (unsigned, no re-sign) run: point watchfix at a zip: use
  # the repo zip.pm to write a minimal IPA wrapper quickly.
  my $zip_pl = "$ROOT/build-system/package/make-ipa.pl";
  my $lib = "$ROOT/build-system/lib";
  my $pa = "$dir/stage";
  remove_tree($pa);
  make_path("$pa/Payload");
  system('cp', '-a', "$dir/Payload/Spotify.app", "$pa/Payload/Spotify.app");
  my $out = qx($^X $zip_pl $pa/Payload/Spotify.app $dir/input.ipa 2>&1);
  my $rc = $?;
  check($rc == 0, 'make-ipa.pl produced input IPA') or diag($out);

  my $fixed_out = "$dir/fixed.ipa";
  $out = qx(bash "$WATCH/watchfix.sh" "$dir/input.ipa" --out "$fixed_out" --base-id com.pweevee.spotify --skip-sign 2>&1);
  $rc = $?;
  check($rc == 0, 'watchfix.sh --skip-sign succeeds') or diag($out);

  # unpack the fixed IPA and re-validate at the target base id
  my $ud = "$dir/unz";
  remove_tree($ud);
  system('unzip', '-q', $fixed_out, '-d', $ud) == 0 or nok('fixed IPA unzip');
  my $fapp = "$ud/Payload/Spotify.app";
  my $out2 = qx($^X $WATCH/validate-watchfix.pl "$fapp" com.pweevee.spotify 2>&1);
  my $rc2 = $?;
  check($rc2 == 0, 'watchfix output PASSES validation at --base-id') or diag($out2);
  ok(index($out2, 'VALIDATION PASSED') >= 0, 'validator emits PASSED line') or diag($out2);

  # explicit invariants on the fixed tree
  sub read_id { my $p = shift; local $/; open my $f, '<', $p or return undef; my $d = <$f>; $d =~ /<key>CFBundleIdentifier<\/key><string>([^<]+)<\/string>/ ? $1 : undef }
  my $outer = read_id("$fapp/Info.plist");
  my $wid = read_id("$fapp/Watch/WatchApp.app/Info.plist");
  my $wxid = read_id("$fapp/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex/Info.plist");
  check($outer eq 'com.pweevee.spotify', 'outer id rewritten to --base-id', $outer);
  check($wid eq 'com.pweevee.spotify.watchkitapp', 'watch id derived from base', $wid);
  check($wxid eq 'com.pweevee.spotify.watchkitapp.WatchWidgetExtension', 'widget appex id now prefixed', $wxid);

  my $comp;
  { local $/; open my $f, '<', "$fapp/Info.plist" or die; my $d = <$f>; $d =~ /<key>WKCompanionAppBundleIdentifier<\/key><string>([^<]+)<\/string>/ and $comp = $1; }
  check(defined $comp && $comp eq 'com.pweevee.spotify.watchkitapp', 'companion metadata set on phone app');

  { local $/; open my $f, '<', "$fapp/Watch/WatchApp.app/Info.plist" or die; my $d = <$f>; check($d !~ /WKWatchKitApp/, 'WKWatchKitApp removed from watch side'); }

  # Intents: phone app now declares the union
  { local $/; open my $f, '<', "$fapp/Info.plist" or die; my $d = <$f>; check($d =~ /SendMessageIntent/, 'IntentsSupported union copied into phone app'); }
  { local $/; open my $f, '<', "$fapp/PlugIns/InsightsIntents.appex/Info.plist" or die; my $d = <$f>; check($d =~ /SendMessageIntent/, 'intents extension still declares its own intent'); }
}

remove_tree($dir);

print "\n";
if ($fail) { print "watchfix-tests FAILED ($pass ok, $fail fail)\n"; exit 1; }
print "watchfix-tests PASSED ($pass ok)\n";
exit 0;
