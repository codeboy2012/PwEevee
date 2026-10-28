#!/usr/bin/env perl
# Regression tests for the bundle dependency validator (self-contained design).
#
#   PwEvevee/build-system/tests/bundle-deps-tests.pl
#
# 1. a healthy bundled dylib pair (main binary absent, so only the policy rules run)
#    must PASS;
# 2. the old failing dylib that shipped the absolute
#    /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate load command must FAIL,
#    naming the absolute path;
# 3. with a host binary present, an @rpath reference that the host rpaths cannot
#    resolve must FAIL.
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Basename qw(dirname);

my $ROOT = dirname($0) . '/../..';            # repo root (PwEvevee/..)
my $BS   = dirname($0) . '/..';              # PwEvevee/build-system
my $DYLIB = "$ROOT/components/spotipw/dylibs/spotifyglass.dylib";
my $FIXTURE = "$BS/tests/fixtures/abs-substrate-dylib.dylib";   # old failing embedded binary

my $T = "/tmp/bundle-deps-test.$$";
remove_tree($T);
make_path($T);

my @failures;
my $pass = 0;
sub ok  { my ($c, $w) = @_; if ($c) { $pass++; } else { push @failures, $w; } }
sub run_validator {
  my ($dir) = @_;
  my $out = `perl "$ROOT/build-system/validate/validate-bundle-deps.pl" --strict-all "$dir" 2>&1`;
  return ($? >> 8, $out);
}

# fixtures must exist
unless (-f $DYLIB and -f $FIXTURE) {
  print "BUNDLE-DEPS TESTS FAILED: pinned dylib or negative fixture missing\n";
  exit 1;
}

# ---------- 1. pinned (healthy) dylib passes the policy ----------
{
  make_path("$T/pass");
  copy($DYLIB, "$T/pass/spotifyglass.dylib") or die "copy: $!";
  my ($rc, $out) = run_validator("$T/pass");
  ok($rc == 0, "healthy bundled dylib passes the dependency policy (rc=$rc):\n$out");
}

# ---------- 2. old failing dylib with the absolute substrate path fails ----------
{
  make_path("$T/fail");
  copy($FIXTURE, "$T/fail/spotifyglass.dylib") or die "copy: $!";
  my ($rc, $out) = run_validator("$T/fail");
  ok($rc != 0, "dylib carrying /Library/Frameworks/CydiaSubstrate absolute path is rejected (rc=$rc)");
  ok($out =~ m{/Library/Frameworks/CydiaSubstrate\.framework/CydiaSubstrate}, "failure names the absolute path:\n$out");
}

# ---------- 3. unresolved @rpath fails once a host binary exists ----------
{
  # Craft a tiny fake 'host' rpath set by copying the pinned dylib in as Spotify is not
  # possible without a real Mach-O executable; instead run the validator twice on the
  # same staged tree with a real host binary copied from the pinned input IPA presence
  # is environment-dependent - so test the resolution path directly with a staged main
  # binary only when the input IPA is available; otherwise record the edge as covered
  # by the pipeline validation (unified.sh runs the check with the binary present).
  my $src_ipa = "$ROOT/Evevee Spotify/source-artifacts/Sptoify-No_Watch_App.ipa";
  if (-f $src_ipa) {
    make_path("$T/rpath/Payload");
    system("unzip -q -o \"$src_ipa\" 'Payload/Spotify.app/Spotify' -d $T/rpath > /dev/null 2>&1");
    if (-f "$T/rpath/Payload/Spotify.app/Spotify") {
      # the pinned component dylib's own @rpath references cannot resolve against the
      # host's rpaths in this synthetic layout, so expect a failure naming @rpath
      copy($DYLIB, "$T/rpath/spotifyglass.dylib");
      my ($rc, $out) = run_validator("$T/rpath");
      ok($rc != 0, "unresolvable \@rpath with host rpaths staged fails (rc=$rc)");
    } else {
      print "  (host binary extraction failed - \@rpath resolution edge skipped)\n";
    }
  } else {
    print "  (input IPA absent - \@rpath resolution edge skipped)\n";
  }
}

remove_tree($T);
if (@failures) {
  print "BUNDLE-DEPS TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "BUNDLE-DEPS TESTS PASSED ($pass checks)\n";
exit 0;
