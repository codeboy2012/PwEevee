#!/usr/bin/env perl
# ============================================================================
# component-manifest-test.pl — every pinned component file matches its manifest
# ============================================================================
#
#   perl PwEvevee/build-system/tests/component-manifest-test.pl
#
# Regression for the v3.1.0 audit finding "stale component manifest": commit
# db3ccd6 refreshed PwEvevee/components/spotipw/dylibs/spotifyglass.dylib in
# place, but the component's manifest.json kept recording the previous sha256
# and size, and no pipeline step compared the two, so the drift was invisible.
#
# This suite walks every PwEvevee/components/*/manifest.json,
# PwEvevee/shared-dependencies/*/manifest.json and
# "Evevee Spotify/component/manifest.json", and asserts that each files[]
# entry matches the pinned file (sha256 + size).
#
# Line endings: manifests record the hashes of the files as stored in git
# (LF), but a Windows checkout with core.autocrlf=true produces CRLF on disk.
# Text pins therefore pass if either the raw bytes or the LF-normalized bytes
# match, mirroring git's normalization; binary pins still have to match raw.
# ============================================================================
use strict;
use warnings;
use File::Basename qw(dirname);
use JSON::PP qw(decode_json);
use Digest::SHA qw(sha256_hex);

binmode STDOUT, ':encoding(UTF-8)';

my $ROOT = dirname($0) . '/../../..';

my @manifests = (
  glob("$ROOT/PwEvevee/components/*/manifest.json"),
  glob("$ROOT/PwEvevee/shared-dependencies/*/manifest.json"),
  "$ROOT/Evevee Spotify/component/manifest.json",
);

my $pass     = 0;
my @failures;

sub ok {
  my ($cond, $what) = @_;
  if ($cond) { $pass++; } else { push @failures, $what; }
}

sub slurp_raw { local $/; open my $fh, '<:raw', $_[0] or die "open $_[0]: $!"; return <$fh>; }

for my $mf (@manifests) {
  (my $rel = $mf) =~ s{^\Q$ROOT\E/?}{};
  unless (-f $mf) { push @failures, "manifest missing: $rel"; next; }

  my $data = eval { decode_json(slurp_raw($mf)) };
  unless ($data) { push @failures, "manifest unparseable: $rel"; next; }

  my $entries = $data->{files} // [];

  # Manifests without a files[] list (e.g. the CydiaSubstrate shared
  # dependency) declare their single pin via provides/install_path instead.
  my $is_framework = ($data->{provides} // '') eq 'CydiaSubstrate.framework';
  unless ($is_framework) {
    ok(scalar(@$entries) > 0, "$rel: lists at least one pinned file");
  }

  # files[] paths are relative to the manifest's own directory.
  (my $dir = $mf) =~ s{/manifest\.json$}{};
  for my $e (@$entries) {
    my $path = $e->{path} // '(no path)';
    my $pin  = "$dir/$path";
    unless (-f $pin) { push @failures, "$rel: pinned file missing on disk: $path"; next; }

    my $raw    = slurp_raw($pin);
    my $lf     = $raw =~ s/\r\n/\n/gr;   # git-normalized variant
    my $lfok   = ($raw eq $lf);          # true for binary/already-LF content
    my $size   = length $raw;

    ok(defined $e->{size} && ($size == $e->{size} || ($lfok ? 0 : length($lf) == $e->{size})),
       "$rel: $path size (manifest " . ($e->{size} // 'absent') . " vs disk $size"
         . ($lfok ? '' : ', LF ' . length($lf)) . ')');

    my $raw_sha = sha256_hex($raw);
    my $match   = defined $e->{sha256} && $raw_sha eq $e->{sha256};
    if (!$match && !$lfok) {
      $match = sha256_hex($lf) eq ($e->{sha256} // '');
    }
    ok($match, "$rel: $path sha256 (manifest " . substr($e->{sha256} // 'absent', 0, 12)
                                     . " vs disk " . substr($raw_sha, 0, 12) . ")");
  }

  # CydiaSubstrate.framework pins the framework binary without a files[] list;
  # verify the shipped object is actually present.
  if ($is_framework) {
    # install_path (e.g. 'Frameworks/CydiaSubstrate.framework') is where the
    # framework lands inside the app; the pin on disk sits directly under the
    # shared-dependency directory, next to its manifest.
    my $bin = "$dir/CydiaSubstrate.framework/CydiaSubstrate";
    ok(-f $bin, "$rel: CydiaSubstrate binary present on disk");
  }
}

if (@failures) {
  print "COMPONENT MANIFEST TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "COMPONENT MANIFEST TESTS PASSED ($pass checks)\n";
exit 0;
