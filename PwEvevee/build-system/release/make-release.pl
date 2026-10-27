#!/usr/bin/env perl
# Register a built IPA as a release and apply the website retention policy.
#
#   perl PwEvevee/build-system/release/make-release.pl <ipa> <build-manifest.json> [options]
#     --retain-months N     website retention window (default 6)
#     --githash X           spoti.pw commit recorded in the release card
#
# Layout created:
#   releases/
#     current/<name>.ipa              downloadable build (within retention)
#     current/<name>.manifest.json    release card
#     metadata/<name>.manifest.json   retained forever, even past retention
#     archive/                        (link-out index only; files live on GitHub)
#
# Retention policy (configurable, WEBSITE_IPA_RETENTION_MONTHS=6):
#   - releases older than the window are REMOVED from current/ (index + file)
#   - their metadata is KEPT in metadata/ and flagged past_retention: true
#   - the card links to GitHub Releases for historical downloads
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Spec;
use Cwd qw(getcwd);
use JSON::PP qw(decode_json encode_json);

# Run from anywhere; locates the repository root automatically (same convention as
# render-site.pl: walk upward until PwEvevee/dependencies.json is found).
my $ROOT = $ENV{PWEEVEE_ROOT} || _repo_root();
my $CALLER = getcwd();
chdir $ROOT or die;

my ($ipa, $manifest, @opt) = @ARGV;
defined $manifest or die "usage: make-release.pl <ipa> <build-manifest.json> [--retain-months N] [--githash X]\n";
for my $p ($ipa, $manifest) {                 # caller-relative paths must survive the chdir
  $p = File::Spec->rel2abs($p, $CALLER) unless File::Spec->file_name_is_absolute($p);
}
-f $ipa && -f $manifest or die "ipa and manifest must exist\n";

my $retain_months = 6;
my $githash;
while (@opt) {
  my $k = shift @opt;
  if    ($k eq '--retain-months') { $retain_months = shift @opt; }
  elsif ($k eq '--githash')       { $githash = shift @opt; }
  else { die "unknown option: $k"; }
}

my $M = decode_json(scalar _slurp($manifest));
my $name = basename($ipa);
my ($version_tag) = $name =~ /pweevee-(\d[\w.-]*)/i;
$version_tag //= 'dev';

my $now = time();
my $build_epoch = $M->{build_epoch} || $now;
my $age_months = ($now - $build_epoch) / (30.44 * 24 * 3600);
my $in_window = $age_months <= $retain_months;

make_path('releases/current', 'releases/metadata', 'releases/archive');

my $card = {
  id            => $version_tag,
  file          => $name,
  version       => $version_tag,
  build_date    => $M->{build_date},
  build_epoch   => $build_epoch,
  spotify_version => $M->{spotify_version},
  spotipw_version  => $M->{spotipw_version},
  spotipw_commit   => $githash // $M->{spotipw_commit},
  eevee_version    => $M->{eevee_version},
  ipa_sha256    => $M->{ipa_sha256},
  ipa_size      => $M->{ipa_size},
  dylibs        => $M->{dylibs},
  frameworks    => $M->{frameworks},
  bundles       => $M->{bundles},
  download      => "/releases/$name",
  hosted        => $in_window ? 'website' : 'github',
  past_retention => !$in_window,
  retention_months => $retain_months,
  github_releases => 'https://github.com/codeboy2012/PwEevee/releases',
};

# metadata is written always; the downloadable copy only while in the window
_spew("releases/metadata/$name.manifest.json", encode_json($card) . "\n");
copy($ipa, "releases/current/$name") or die "copy ipa: $!" if $in_window;
copy($manifest, "releases/metadata/$name.build-manifest.json");

if (!$in_window) {
  print "  '$name' is outside the $retain_months-month window; metadata kept, no website download.\n";
}

# sweep: demote expired current releases
my $swept = 0;
opendir(my $dh, 'releases/current') or die;
for my $f (grep { /\.ipa$/ } readdir($dh)) {
  my $meta = "releases/metadata/$f.manifest.json";
  next unless -f $meta;
  my $c = decode_json(scalar _slurp($meta));
  my $age = ($now - ($c->{build_epoch} || 0)) / (30.44 * 24 * 3600);
  if ($age > $retain_months) {
    unlink "releases/current/$f";
    $c->{hosted} = 'github';
    $c->{past_retention} = 1;
    _spew($meta, encode_json($c) . "\n");
    print "  swept past-retention release: $f (metadata kept)\n";
    $swept++;
  }
}
closedir($dh);

# website-ready index
my @cards;
for my $f (sort { $b cmp $a } glob('releases/metadata/*.manifest.json')) {
  next if $f =~ /\.build-manifest\.json$/;
  push @cards, decode_json(scalar _slurp($f));
}
@cards = sort { ($b->{build_epoch} || 0) <=> ($a->{build_epoch} || 0) } @cards;
_spew('releases/index.json', encode_json({
  canonical_url => 'https://pweevee.skytweak.dpdns.org/',
  retention_months => $retain_months,
  releases => \@cards,
}) . "\n");

print "  releases/index.json: " . scalar(@cards) . " releases, $swept swept\n";

sub _repo_root {
  my $dir = dirname($0);
  while (!-f "$dir/PwEvevee/dependencies.json") {
    my $up = dirname($dir);
    die "cannot locate repository root above $0\n" if $up eq $dir;
    $dir = $up;
  }
  return $dir;
}
sub _slurp { my ($p) = @_; open(my $f, '<:raw', $p) or die "open $p: $!"; local $/; my $d = <$f>; close $f; return $d; }
sub _spew  { my ($p, $d) = @_; open(my $o, '>:raw', $p) or die "write $p: $!"; print $o $d; close $o; }
