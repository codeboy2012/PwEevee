#!/usr/bin/env perl
# ============================================================================
# downloads-engine-test.pl — the Downloads engine must be built, loaded and real
# ============================================================================
#
#   perl PwEvevee/build-system/tests/downloads-engine-test.pl
#   PWEEVEE_IPA=/path/to/PwEevee-3.1.5.ipa perl .../downloads-engine-test.pl
#
# Regression for the 3.1.0 build, where the Downloads page reported
#
#   "Downloads engine isn't loaded"
#
# for two independent reasons that every other check in the tree missed:
#
#   1. the IPA carried an inherited Taurus-era SpotifyAudioProbe.dylib whose
#      bridge class was SAPTaurusBridge, while the tweak looks up
#      SAPPwEeveeBridge — so NSClassFromString() returned nil;
#   2. no LC_LOAD_DYLIB named the companion at all, so dyld never loaded the
#      file even if it had exported the right class.
#
# This test asserts the build contract (unified.sh builds the engine from
# source, loads it, and verifies it) and, when a candidate IPA is supplied,
# inspects the artifact itself. With no IPA it still runs the source checks.
# ============================================================================
use strict;
use warnings;
use File::Basename qw(dirname);
use JSON::PP qw(decode_json);

my $ROOT = dirname($0) . '/../../..';
my $DEPS = "$ROOT/PwEvevee/dependencies.json";
my $UNIFIED = "$ROOT/PwEvevee/build-system/unified.sh";
my $RESOLVE = "$ROOT/PwEvevee/build-system/package/resolve-deps.pl";
my $MANIFEST = "$ROOT/source/extension/OpenSpotify/Resources/manifest.json";
my $PLIST_PY = "$ROOT/source/scripts/safari-extension-plist.py";

my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++ } else { push @failures, $what } }
sub slurp { local $/; open my $fh, '<', $_[0] or die "open $_[0]: $!"; return <$fh> }
sub slurp_raw { local $/; open my $fh, '<:raw', $_[0] or die "open $_[0]: $!"; return <$fh> }

# ---- 1. the declared contract ------------------------------------------------
my $deps = eval { decode_json(slurp($DEPS)) };
ok($deps && ref $deps eq 'HASH', 'dependencies.json parses');
my $dl = $deps->{downloads_engine} // {};
ok(($dl->{companion} // '') eq 'SpotifyAudioProbe.dylib',
   'downloads_engine names the companion SpotifyAudioProbe.dylib');
ok(($dl->{install} // '') eq 'Frameworks/SpotifyAudioProbe.dylib',
   'the companion is installed at Frameworks/SpotifyAudioProbe.dylib');
ok(($dl->{load_command} // '') eq '@executable_path/Frameworks/SpotifyAudioProbe.dylib',
   'downloads_engine declares the bundle-relative load command');
ok(($dl->{bridge_class} // '') eq 'SAPPwEeveeBridge',
   'downloads_engine requires the SAPPwEeveeBridge class the tweak looks up');
ok(($dl->{forbidden_class} // '') eq 'SAPTaurusBridge',
   'downloads_engine rejects the retired SAPTaurusBridge class');
ok(($dl->{required_spotify} // '') eq '9.1.90',
   'downloads_engine is pinned to the verified Spotify 9.1.90 build');
my @global = map { $_->{name} } @{ $deps->{load_commands} // [] };
ok(!grep({ $_ eq $dl->{load_command} } @global),
   'the companion load command is NOT unconditional (a --no-downloads build must not name a missing file)');

# ---- 2. the pipeline actually performs the steps -----------------------------
my $unified = slurp($UNIFIED);
ok($unified =~ /build_downloads\.py/, 'unified.sh builds the companion with build_downloads.py');
ok($unified =~ /verify_downloads\.py/, 'unified.sh verifies the finished IPA with verify_downloads.py');
ok($unified =~ /--no-downloads/, 'unified.sh exposes an explicit --no-downloads opt-out');
ok($unified =~ /SAPPwEeveeBridge/, 'unified.sh asserts the built companion exports the bridge class');
ok($unified =~ /downloads_engine\}\{load_command\}/, 'unified.sh injects the companion load command from the spec');
ok($unified =~ /SpotifyAudioProbe\.dylib" "\$STAGED\/Frameworks/, 'unified.sh stages the freshly built companion');

my $resolve = slurp($RESOLVE);
ok($resolve =~ /forbidden_class/, 'resolve-deps.pl rejects an inherited Taurus-era companion');
ok($resolve =~ /bridge_class/, 'resolve-deps.pl requires the PwEevee bridge class');

# ---- 3. the Safari extension is PwEevee-branded, not Taurus -------------------
my $manifest = eval { decode_json(slurp($MANIFEST)) };
ok($manifest && ref $manifest eq 'HASH', 'the Safari manifest parses');
ok(($manifest->{name} // '') !~ /taurus/i, 'the Safari extension name contains no Taurus branding');
ok(($manifest->{name} // '') =~ /PwEevee/i, 'the Safari extension name identifies PwEevee');
ok(($manifest->{manifest_version} // 0) == 3, 'the Safari extension is a Manifest V3 web extension');
ok(($manifest->{action}{default_popup} // '') ne '', 'the Safari extension keeps its popup');
my $plist_py = slurp($PLIST_PY);
ok($plist_py =~ /PwEeveeOpenSpotify/, 'the generated appex keeps the PwEeveeOpenSpotify identity');
ok($plist_py !~ /taurus/i, 'the generated appex plist carries no Taurus name');

# ---- 4. the candidate artifact, when one is supplied --------------------------
my $ipa = $ENV{PWEEVEE_IPA};
if (!defined $ipa || !-f $ipa) {
  print "  (no PWEEVEE_IPA given; artifact checks skipped)\n";
} else {
  print "candidate IPA: $ipa\n";
  open my $list, '-|', 'unzip', '-Z1', $ipa or die "unzip -Z1: $!";
  my @names = <$list>;
  close $list;
  chomp @names;
  ok(@names > 100, 'the IPA has a plausible member list');

  my @appex = grep { m{PlugIns/[^/]+\.appex/$} } @names;
  ok(!grep({ /Taurus/i } @appex), 'no Taurus-named appex ships in the IPA');
  ok(scalar(grep({ m{PlugIns/PwEeveeOpenSpotify\.appex/$} } @names)) == 1,
     'exactly one PwEeveeOpenSpotify.appex ships in the IPA');

  my $probe_rel = 'Payload/Spotify.app/Frameworks/SpotifyAudioProbe.dylib';
  ok(scalar(grep { $_ eq $probe_rel } @names) == 1,
     'the IPA contains exactly one Frameworks/SpotifyAudioProbe.dylib');

  my $probe = '';
  if (grep { $_ eq $probe_rel } @names) {
    open my $p, '-|', 'unzip', '-p', $ipa, $probe_rel or die "unzip -p: $!";
    binmode $p;
    local $/; $probe = <$p>;
    close $p;
  }
  ok(length($probe) > 100000, 'the companion is a real library, not a stub');
  ok(index($probe, "SAPPwEeveeBridge\0") >= 0,
     'the companion exports SAPPwEeveeBridge');
  ok(index($probe, "SAPTaurusBridge\0") < 0,
     'the companion does not export the retired SAPTaurusBridge');

  my $host = '';
  open my $h, '-|', 'unzip', '-p', $ipa, 'Payload/Spotify.app/Spotify' or die "unzip -p host: $!";
  binmode $h;
  local $/; $host = <$h>;
  close $h;
  my $needle = $dl->{load_command} . "\0";
  ok(index($host, $needle) >= 0,
     'the Spotify executable loads the Downloads companion');
}

if (@failures) {
  print "DOWNLOADS ENGINE TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "DOWNLOADS ENGINE TESTS PASSED ($pass checks)\n";
exit 0;
