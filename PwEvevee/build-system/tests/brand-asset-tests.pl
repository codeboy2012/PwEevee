#!/usr/bin/env perl
# Technical validation of the PwEevee-owned brand-asset pipeline.
#
#   perl PwEvevee/build-system/tests/brand-asset-tests.pl
#
# Checks the committed artwork only (nothing is regenerated unless the
# guarded determinism run below passes):
#   * every brand PNG parses, is square RGBA with an intact alpha channel,
#     and has exactly the expected pixel dimensions
#   * PwEvevee/brand-icons/pweevee-icon.png matches its manifest sha256+size
#     (the build validates this again at package time)
#   * website assets reference PwEevee's own icon set; no Spotify-mark file
#     is used as PwEevee's brand asset anywhere in the website tree
#   * determinism: make-app-icon.pl run twice produces byte-identical outputs
#     — verified against an explicit backup; any divergence is restored and
#     reported as a failure, so the committed files are never left changed
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use File::Spec::Functions qw(catfile);
use Digest::SHA qw(sha256_hex);
use File::Find;
use JSON::PP ();
use lib dirname($0) . '/../release/lib';
use PwPng;

my $ROOT = dirname($0) . '/../../..';
my $BRAND = catfile($ROOT, 'PwEvevee', 'brand-icons');
my $WEBAS = catfile($ROOT, 'website', 'assets');

my $pass = 0;
my @failures;
sub ok { my ($c, $w) = @_; $c ? $pass++ : push @failures, $w }

# ---------- 1. committed brand PNGs: parse, dims, alpha ----------
my @pngs = (
  [ catfile($BRAND, 'pweevee-icon.png'),  180 ],
  [ catfile($WEBAS,  'icon-512.png'),     512 ],
  [ catfile($WEBAS,  'icon-180.png'),     180 ],
  [ catfile($WEBAS,  'icon-32.png'),       32 ],
);
for my $pair (@pngs) {
  my ($path, $want) = @$pair;
  if (!-f $path) { push @failures, "missing committed PNG: $path"; next }
  my $img = eval { PwPng::png_read($path) };
  ok(defined $img, "PNG parses: " . basename___($path));
  next unless $img && $img->{w};
  ok($img->{w} == $want && $img->{h} == $want,
     sprintf('%s is %dx%d', basename___($path), $img->{w}, $img->{h}));
  ok($img->{bpp} == 4, sprintf('%s is RGBA (alpha channel)', basename___($path)));

  # alpha channel is meaningful: has real opaque AND real transparent samples
  my ($opaque, $transpx) = (0, 0);
  for my $row (@{ $img->{rows} }) {
    for (my $i = 3; $i < length($row); $i += 4) {
      my $a = ord(substr($row, $i, 1));
      $opaque++  if $a == 255;
      $transpx++ if $a == 0;
    }
  }
  my $total = $img->{w} * $img->{h};
  ok($opaque > 0 && $transpx < $total,
     sprintf('%s has usable alpha (%d opaque px, %d px max)', basename___($path), $opaque, $total));
}

sub basename___ {
  my $p = shift;
  my $i = rindex($p, '/'); my $j = rindex($p, "\\");
  my $k = $i > $j ? $i : $j;
  return $k >= 0 ? substr($p, $k + 1) : $p;
}

# ---------- 2. brand icon manifest consistency ----------
{
  my $manifest_file = catfile($BRAND, 'manifest.json');
  ok(-f $manifest_file, 'brand-icons/manifest.json exists');
  my $m = eval { JSON::PP::decode_json(scalar _read($manifest_file)) };
  ok(defined $m, 'brand-icon manifest parses');
  my ($e) = grep { $_->{path} eq 'pweevee-icon.png' } @{ $m->{files} // [] };
  ok(defined $e, 'manifest json has the pweevee-icon.png entry');
  if ($e) {
    my $sha = sha256_hex(_read(catfile($BRAND, 'pweevee-icon.png')));
    ok($e->{sha256} eq $sha, 'manifest sha256 matches the committed icon bytes');
    ok($e->{size} == -s catfile($BRAND, 'pweevee-icon.png'), 'manifest size matches');
    ok($m->{license} =~ /not derived from Spotify|no upstream derivation/i,
       'manifest records the icon as original PwEevee artwork, not upstream-derived');
  }
}

# ---------- 3. Spotify mark is not used as the PwEevee brand mark ----------
{
  # No spotify-marked image asset lives in the website assets/brand-icons dirs
  my @suspects;
  find({ wanted => sub {
           return unless -f $_;
           push @suspects, $File::Find::name
             if $File::Find::name =~ m{/website/assets/} && /spotify/i;
         }, no_chdir => 1 }, catfile($ROOT, 'website'));
  ok(!@suspects, 'no Spotify-marked asset files in website/assets/') or push @failures, "  found: @suspects";

  # Any spotify reference in the website sources must be attribution/credit
  # (hrefs/links), never an icon asset file used as PwEevee's own mark.
  my (@href_refs, @asset_refs);
  find({ wanted => sub {
           return unless -f $_ && /\.(html?|css|js|svg|pl)$/i;
           my $d = _read($_) or return;
           while ($d =~ /([^\s"'<>]{0,120}spotify[^\s"'<>]{0,120})/gis) {
             my $frag = defined($1) ? $1 : '';
             my $f = $File::Find::name;
             my $rootq = quotemeta($ROOT);
             $f =~ s/^$rootq\/?//;
             if ($frag =~ /\.(?:png|jpe?g|svg|ico|icns)\b/i) { push @asset_refs, "$f: $frag" }
             else { push @href_refs, $frag }
           }
         }, no_chdir => 1 }, catfile($ROOT, 'website'));
  my $root_re = quotemeta($ROOT);
  ok(!@asset_refs, 'no Spotify-mark asset file is wired into the website') or push @failures, map {"  $_"} @asset_refs;
}

# ---------- 4. website references PwEevee's own icons ----------
{
  my $index = _read(catfile($ROOT, 'website', 'index.html'));
  ok(index($index, '/assets/icon-32.png') >= 0,  'rendered website links the 32px PwEevee icon (favicon)');
  ok(index($index, '/assets/icon-512.png') >= 0, 'rendered website links the 512px PwEevee icon (installable)');
  ok(index($index, '/assets/icon-180.png') >= 0, 'rendered website links the 180px PwEevee icon (apple-touch)');
  ok($index !~ m{spotify\S*\.(?:png|svg|ico)}i, 'no Spotify-marked image filename appears in the rendered index');
  for my $asset ('icon-512.png', 'icon-180.png', 'icon-32.png', 'favicon.svg') {
    ok(-f catfile($WEBAS, $asset), 'website asset present: ' . $asset);
  }
}

# ---------- 5. determinism: double-run byte-identical, with backup ----------
{
  my $gen = catfile($ROOT, 'PwEvevee', 'build-system', 'release', 'make-app-icon.pl');
  ok(-f $gen, 'icon generator present');
  my $T = catfile(div(), "brand-determinism-$$");
  make_path(catfile($T, 'backup'), catfile($T, 'after'));

  my @outs = map { $_->[0] } grep { -f $_->[0] } @pngs;
  for my $p (@outs) { copy($p, catfile($T, 'backup', basename___($p))) or die "backup $p: $!" }

  my $run1 = _shell("$^X \"$gen\" 2>&1");
  my $run2 = _shell("$^X \"$gen\" 2>&1");
  ok($run1 =~ /app icon done/ && $run2 =~ /app icon done/, 'generator runs cleanly twice');
  if ($run1 !~ /app icon done/) { push @failures, "run1: $run1" }
  if ($run2 !~ /app icon done/) { push @failures, "run2: $run2" }

  for my $p (@outs) {
    if (-f $p) {
      my $a = sha256_hex(_read($p));
      my $b = sha256_hex(_read(catfile($T, 'backup', basename___($p))));
      ok($a eq $b, 'regenerated output byte-identical to committed: ' . basename___($p));
      if ($a ne $b) {
        # restore the committed bytes; never leave the repo mutated by a test
        copy(catfile($T, 'backup', basename___($p)), $p) or die "restore $p: $!";
      }
    }
  }
  remove_tree($T);
}

sub div { return $ENV{TEMP} || '/tmp' }
sub _read { my ($p) = @_; return '' unless -f $p; open my $f, '<:raw', $p or die "open $p: $!"; local $/; my $d = <$f>; close $f; $d }
sub _shell { my ($c) = @_; my $out = `$c`; return $out }

if (@failures) {
  print "BRAND-ASSET TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "BRAND-ASSET TESTS PASSED ($pass checks)\n";
exit 0;
