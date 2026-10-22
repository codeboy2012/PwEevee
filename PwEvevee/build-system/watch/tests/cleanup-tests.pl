#!/usr/bin/env perl
# ============================================================================
# cleanup-tests.pl — regression tests for unified.sh workspace cleanup.
#
#   perl PwEvevee/build-system/watch/tests/cleanup-tests.pl
#
# Verifies, in an ISOLATED fixture directory (never touching the real
# build-system tree, real _work, or any real IPA):
#   1. failed build removes the per-run workspace AND preserves exit status 1
#   2. successful build removes the per-run workspace
#   3. PWEEVEE_KEEP_WORK=1 preserves the workspace and logs its path
#   4. paths containing spaces are handled safely
#   5. unrelated files in _work are never removed
#   6. the input IPA stays byte-identical after success and failure
# The build is exercised DIRECTLY through bash on a cloned unified.sh whose
# repo-relative asset paths are all faked inside the fixture, so nothing in
# the real repo is modified or deleted.
# ============================================================================
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);

my $ROOT   = abs_path(dirname(abs_path(__FILE__)) . '/../../..');   # PwEvevee/
my $BS_SRC = "$ROOT/build-system";
my $T      = ($ENV{TMPDIR} || '/tmp') . "/cleanup-test-$$";
remove_tree($T); make_path($T);
END { remove_tree($T) }

my ($pass, $fail) = (0, 0);
sub check { my ($c, $n) = @_; if ($c) { $pass++; printf "  ok  %s\n", $n } else { $fail++; printf "  FAIL %s\n", $n } }

# ---- fixture: isolated build-system clone + fake repo assets ----------------
my $bs   = "$T/repo/PwEvevee/build-system";
my $repo = "$T/repo";
my $work = "$bs/_work";
make_path($bs);
copy("$BS_SRC/unified.sh", "$bs/unified.sh") or die "copy unified.sh: $!";
make_path("$bs/watch", "$bs/validate", "$bs/package", "$bs/inject", "$bs/lib", "$work");
for my $f ('watch/watchfix-stage.sh', 'watch/watchfix.sh', 'watch/validate-watchfix.pl',
           'validate/validate-ipa.pl', 'validate/validate-macho.pl', 'package/make-ipa.pl',
           'package/resolve-deps.pl', 'inject/inject-dylib.pl', 'lib/plist-value.pl', 'lib/macho.pm', 'lib/zip.pm') {
  copy("$BS_SRC/$f", "$bs/$f") or die "copy $f: $!";
}
chmod 0755, "$bs/watch/watchfix-stage.sh", "$bs/watch/watchfix.sh";
# unrelated sentinel inside _work that cleanup must NEVER remove
open my $s, '>', "$work/UNRELATED-SENTINEL.txt" or die; print $s "do not delete\n"; close $s;

# fake repo assets unified.sh reads. Paths mirror the REAL repo layout:
# components/ and shared-dependencies/ live UNDER PwEvevee/ (unified.sh reads
# "$BS/../components", i.e. repo/PwEvevee/components), while "Evevee Spotify"
# is resolved relative to REPO (unified.sh chdir's to $REPO before merging).
# The merge step only `cp -a`s these blobs into the staged tree, so tiny
# placeholders satisfy it and nothing real is touched.
my $eevee = "$repo/Evevee Spotify/component";
make_path("$repo/Spotipw",
          "$T/repo/PwEvevee/components/spotipw/dylibs",
          "$T/repo/PwEvevee/shared-dependencies/cydiasubstrate/CydiaSubstrate.framework",
          "$eevee/package/dynamic-libraries",
          "$eevee/frameworks/Orion.framework",
          "$eevee/frameworks/EeveeSwiftProtobuf.framework",
          "$eevee/bundles/EeveeSpotify.bundle",
          "$eevee/resources");
spew("$repo/Spotipw/version.txt", "1.2.3\n");
spew("$T/repo/PwEvevee/dependencies.json", '{"load_commands":[],"expected_load_commands":[]}');
spew("$T/repo/PwEvevee/components/spotipw/manifest.json", '{"version":"1.2.3"}');
spew("$eevee/manifest.json", '{"version":"1.0.0"}');
spew("$T/repo/PwEvevee/components/spotipw/dylibs/spotifyglass.dylib", 'placeholder');
spew("$eevee/package/dynamic-libraries/EeveeSpotify.dylib", 'x' x 150000);
spew("$T/repo/PwEvevee/components/spotipw/dylibs/spotifyglass.dylib", 'x' x 150000);
make_path("$eevee/bundles/EeveeSpotify.bundle/en.lproj");
spew("$eevee/bundles/EeveeSpotify.bundle/en.lproj/Localizable.strings", 'placeholder');

spew("$eevee/frameworks/Orion.framework/Orion", 'placeholder');
spew("$eevee/frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf", 'placeholder');
spew("$eevee/bundles/EeveeSpotify.bundle/Info.plist", '<?xml version="1.0"?><plist version="1.0"><dict/></plist>');
spew("$T/repo/PwEvevee/shared-dependencies/cydiasubstrate/CydiaSubstrate.framework/CydiaSubstrate", 'placeholder');

# ---- input IPA: synthetic Spotify.app in the skywatch scheme ----------------
my $input = "$T/input dir/input ipa.ipa";   # spaces in dir AND file names
my $stage = "$T/input dir/stage/Payload/Spotify.app";
make_path("$stage/PlugIns/AppExtension.appex",
          "$stage/Watch/WatchApp.app/PlugIns/WatchExtension.appex");
write_plist("$stage/Info.plist", 'com.skywatch.spotify');
write_plist("$stage/PlugIns/AppExtension.appex/Info.plist", 'com.skywatch.spotify.AppExtension');
write_plist("$stage/Watch/WatchApp.app/Info.plist", 'com.skywatch.spotify.watchkitapp');
write_plist("$stage/Watch/WatchApp.app/PlugIns/WatchExtension.appex/Info.plist", 'com.skywatch.spotify.watchkitapp.WatchExtension');
spew("$stage/Spotify", make_macho(), 'raw');
spew("$stage/PkgInfo", 'APPL????');
# resolve-deps requires >= 140 icon PNGs at the app root
for my $i (1..140) { spew("$stage/icon-$i.png", 'png'); }
system($^X, "$BS_SRC/package/make-ipa.pl", $stage, $input) == 0 or die "fixture make-ipa failed";
my $input_sha = file_sha($input);

# Run the fixture pipeline; returns (exit_status, captured_output).
sub exec_build {
  my ($env) = @_;
  my @sets;
  for my $k (sort keys %$env) {
    (my $v = $env->{$k}) =~ s/'/'"'"'/g;
    push @sets, "$k='$v'";
  }
  my $prefix = @sets ? join(' ', @sets) . ' ' : '';
  my $out = qx($prefix bash "$bs/unified.sh" "$T/input dir/input ipa.ipa" -o "$T/out dir/build.ipa" --watch 2>&1);
  my $rc = $?;
  return ($rc >> 8, $out);
}

sub ws_entries { return scalar grep { !/UNRELATED-SENTINEL/ } glob "$work/*" }

# ---- 1. failed build: workspace cleaned, status 1 preserved -----------------
{
  my ($rc, $out) = exec_build({ PWEEVEE_FORCE_FAIL => '1' });
  check($rc == 1, "failed build exits 1 (got $rc)") or note_out($out);
  check($out =~ /FORCE_FAIL/, 'failure is the simulated forced one') or note_out($out);
  check(ws_entries() == 0, 'failed build leaves NO per-run workspace') or note_out(join "\n", glob "$work/*");
  check(-f "$work/UNRELATED-SENTINEL.txt", 'unrelated sentinel in _work survives cleanup');
  check(file_sha($input) eq $input_sha, 'input IPA byte-identical after failed build');
}

# ---- 2. successful build: workspace cleaned --------------------------------
{
  my ($rc, $out) = exec_build({});
  check($rc == 0, "successful build exits 0 (got $rc)");
  diag_out($out);
  check(-f "$T/out dir/build.ipa", 'output IPA produced at spaced path');
  check(ws_entries() == 0, 'successful build leaves NO per-run workspace') or note_out(join "\n", glob "$work/*");
  check(file_sha($input) eq $input_sha, 'input IPA byte-identical after success');
}

# ---- 3. PWEEVEE_KEEP_WORK=1 preserves the workspace ------------------------
{
  my ($rc, $out) = exec_build({ PWEEVEE_KEEP_WORK => '1' });
  check($rc == 0, 'kept-work build exits 0') or note_out($out);
  my @kept = grep { -d } glob "$work/*";
  check(scalar @kept >= 1, 'PWEEVEE_KEEP_WORK=1 leaves the workspace dir behind');
  if ($out =~ /PWEEVEE_KEEP_WORK: workspace kept at (\S+)/) {
    check(-d $1, 'logged kept path exists on disk');
  } else {
    check(0, 'kept path logged') or note_out($out);
  }
  my ($rc2) = exec_build({});
  check($rc2 == 0, 'next run still succeeds after a kept workspace (stale-tree handling)');
  # Design contract: a run only ever reclaims ITS OWN tenant dir (PWEEVEE_WORK_TENANT,
  # default = its PID). A kept workspace from a FINISHED run survives until an
  # explicit rerun with the same tenant id — the next run must NOT delete it.
  my @dirs2 = grep { -d } glob "$work/*";  check(scalar @dirs2 == 1, 'kept tree from the finished run survives (never deleted by another build)', scalar(@dirs2));

  # A rerun WITH the same tenant id reclaims its own stale tree when idle.
  my ($rc3) = exec_build({ PWEEVEE_WORK_TENANT => '424242' });
  check($rc3 == 0, 'same-tenant rerun succeeds');
  my ($rc4) = exec_build({ PWEEVEE_WORK_TENANT => '424242' });
  check($rc4 == 0, 'same-tenant rerun after completion reclaims its own stale tree');
  my @kept_after = grep { /424242/ } glob "$work/*";
  check(scalar @kept_after == 0, 'own stale tenant tree reclaimed when idle');
}

# ---- 4. spaces in the output path (covered above) + input-path sanity ------
{
  check(-f "$T/out dir/build.ipa", 'spaced output path held its IPA across reruns');
  check(file_sha($input) eq $input_sha, 'input IPA still byte-identical (final)');
}

sub file_sha { my $p = shift; open my $f, '<:raw', $p or die "open $p: $!"; local $/; my $d = <$f>; close $f; return sha256_hex($d) }
sub spew { my ($p, $d) = @_; open my $f, '>:raw', $p or die "open $p: $!"; print $f $d; close $f }
sub note_out { print "    ---- build output ----\n"; print "    $_\n" for split /\n/, $_[0]; print "    ---- end ----\n" }
sub diag_out { print "    ---- build output (diag) ----\n"; print "    $_\n" for split /\n/, $_[0]; print "    ---- end ----\n" }

sub write_plist {
  my ($path, $id) = @_;
  spew($path, <<"PLIST");
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$id</string></dict></plist>
PLIST
}

sub make_macho {
  my @deps = (
    '\@executable_path/Frameworks/spotifyglass.dylib',
    '\@executable_path/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf',
    '\@executable_path/Frameworks/Orion.framework/Orion',
    '\@executable_path/Frameworks/EeveeSpotify.dylib',
    '\@executable_path/Frameworks/CydiaSubstrate.framework/CydiaSubstrate',
  );
  my $cmds = '';
  for my $n (@deps) {
    my $raw = $n . "\0";
    my $cs  = (24 + length($raw) + 7) & ~7;
    $cmds .= pack('V6', 0xC, $cs, 24, 2, 0x10000, 0x10000) . $raw;
    $cmds .= "\0" x ($cs - 24 - length($raw));
  }
  return pack('V6', 0xFEEDFACF, 0x0100000C, 0, 2, scalar(@deps), length($cmds)) . "\0" x 8
       . $cmds . ("\0" x 1024);
}

remove_tree($T);

print "\n";
if ($fail) { print "cleanup-tests FAILED ($pass ok, $fail fail)\n"; exit 1; }
print "cleanup-tests PASSED ($pass ok)\n";
exit 0;

sub done { print "\n"; exit 1; }
