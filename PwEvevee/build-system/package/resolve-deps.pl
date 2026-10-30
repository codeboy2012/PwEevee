#!/usr/bin/env perl
# Dependency resolution over the staged Spotify.app.
#
#   PwEvevee/build-system/package/resolve-deps.pl <staged Spotify.app>
#
# Rules (PwEvevee/dependencies.json):
#   - every shared dependency must exist exactly once in the staged app
#   - a dependency provided by more than one supplier is a hard failure, unless the copies
#     are byte-identical (then one copy is kept and the collapse is recorded)
#   - component-supplied dylibs/frameworks must be present and non-empty
#   - Eevee resources (bundle + icons) must be present for BundleHelper
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname basename);
use File::Find;
use JSON::PP qw(decode_json);

my $app = $ARGV[0] or die "usage: resolve-deps.pl <staged Spotify.app>\n";
$app =~ s{/+$}{};

my $deps = do {
  my $p = dirname($0) . '/../../dependencies.json';
  open(my $f, '<', $p) or die "open $p: $!";
  local $/; decode_json(<$f>);
};

my @problems;
my @notes;

# Collect every path in the staged app whose basename matches, once.
sub collect {
  my ($name) = @_;
  my @hits;
  find({ wanted => sub {
    return unless basename($File::Find::name) eq $name;
    push @hits, $File::Find::name;
  }, no_chdir => 1 }, $app);
  return @hits;
}

# 1. shared dependencies exist exactly once under Frameworks/
for my $name (sort keys %{ $deps->{shared_dependencies} }) {
  my $expect = "$app/Frameworks/$name";
  my @hits = collect($name);
  if (@hits == 0) {
    push @problems, "MISSING DEPENDENCY: $name (expected at $expect)";
    next;
  }
  if (@hits == 1) {
    push @notes, "resolved: $name -> $hits[0]";
    next;
  }
  # more than one path with this name: identical regular files may collapse, anything else fails
  my @files = grep { -f $_ } @hits;
  my @dirs  = grep { -d $_ } @hits;
  if (@dirs == 1 && !@files) {
    push @notes, "resolved: $name (framework) -> $dirs[0]";
    next;
  }
  if (@dirs >= 1) {
    push @problems, sprintf($deps->{duplicate_policy}{message},
                            $name, $hits[0], $hits[1]) . " (framework copied more than once)";
    next;
  }
  my %byhash;
  push @{ $byhash{ sha256_hex(scalar _slurp($_)) } ||= [] }, $_ for @files;
  if (keys(%byhash) == 1) {
    push @notes, "IDENTICAL COPIES COLLAPSED: $name (" . join(', ', @files) . ")";
  } else {
    my ($h1, $h2) = map { (keys %byhash)[$_] } 0, 1;
    push @problems, sprintf($deps->{duplicate_policy}{message}, $name, $byhash{$h1}[0], $byhash{$h2}[0]);
  }
}

# 2. component dylibs present and non-trivial
for my $dylib ('spotifyglass.dylib', 'EeveeSpotify.dylib') {
  my $p = "$app/Frameworks/$dylib";
  if (!-f $p || -s $p < 100000) { push @problems, "MISSING COMPONENT DYLIB: $p"; next; }
  push @notes, "component dylib: $dylib (" . sprintf('%d', -s $p) . " bytes)";
}

# 3. Eevee resources (BundleHelper search order, see the build-system dependency notes)
-f "$app/EeveeSpotify.bundle/Info.plist" or push @problems, "MISSING RESOURCE: EeveeSpotify.bundle/Info.plist";
my $en = "$app/EeveeSpotify.bundle/en.lproj/Localizable.strings";
-f $en or push @problems, "MISSING RESOURCE: EeveeSpotify.bundle/en.lproj/Localizable.strings";
my $icons = 0;
find({ wanted => sub {
  $icons++ if -f $File::Find::name
           && $File::Find::name =~ /\.png$/i
           && $File::Find::name =~ m{^\Q$app\E/[^/]+\.png$};
}, no_chdir => 1 }, $app);
$icons >= 140 or push @problems, "Eevee icon set looks wrong: $icons PNGs at app root (expected >= 140)";
push @notes, "eevee resources: bundle OK, $icons icon PNGs at app root";

# 4. the Downloads companion, when this build includes it
#    unified.sh only injects its load command when build_downloads.py produced
#    the library, so its presence is the signal. Checking the class names here
#    catches the exact 3.1.0 defect at dependency-resolution time: an inherited
#    Taurus-era dylib that exports SAPTaurusBridge instead of SAPPwEeveeBridge.
{
  my $dl = $deps->{downloads_engine};
  if (ref $dl eq 'HASH' && $dl->{companion}) {
    my $p = "$app/" . ($dl->{install} // ("Frameworks/" . $dl->{companion}));
    if (-f $p) {
      push @problems, "DOWNLOADS COMPANION TOO SMALL: $p" if -s $p < 100000;
      my $bytes = _slurp($p);
      push @problems, "DOWNLOADS COMPANION lacks $dl->{bridge_class}: $p"
        if index($bytes, $dl->{bridge_class}) < 0;
      push @problems, "DOWNLOADS COMPANION carries retired $dl->{forbidden_class}: $p"
        if $dl->{forbidden_class} && index($bytes, $dl->{forbidden_class}) >= 0;
      push @notes, "downloads companion: $dl->{companion} (bridge $dl->{bridge_class})";
    }
  }
}

# 5. duplicate framework names anywhere in the tree
my %fwnames;
find({ wanted => sub {
  return unless -d $File::Find::name && $File::Find::name =~ /\.framework$/;
  my $base = basename($File::Find::name);
  push @problems, "DUPLICATE FRAMEWORK: $base ($File::Find::name)" if $fwnames{$base}++;
}, no_chdir => 1 }, $app);

print "  $_\n" for @notes;
if (@problems) {
  print "DEPENDENCY RESOLUTION FAILED:\n";
  print "  - $_\n" for @problems;
  exit 1;
}
print "DEPENDENCY RESOLUTION PASSED (" . scalar(@notes) . " checks)\n";

sub _slurp { my ($p) = @_; open(my $f, '<:raw', $p) or die "open $p: $!"; local $/; my $d = <$f>; close $f; return $d; }
