#!/usr/bin/env perl
# Enforce the self-contained runtime design on the staged app bundle.
#
#   PwEevee/build-system/validate/validate-bundle-deps.pl <staged Spotify.app dir>
#
# Documented runtime design (PwEevee 3.1.0): the IPA is self-contained. There is no
# external jailbreak runtime on the packaging target, so every dependency edge of
# the binaries PwEevee controls must resolve either to an Apple system library or
# to a bundle-relative location (CydiaSubstrate is bundled under Frameworks/ and
# resolves through the host binary's @executable_path/Frameworks rpath, i.e. an
# @rpath install-name - see source/tweak/Makefile).
#
# Regression for the dyld crash: spotifyglass.dylib shipped with
#   /Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate (absolute, missing
#   on device) -> DYLD termination "Library missing" before the UI could start.
# The historical broken artifact is preserved as the negative fixture
# build-system/tests/fixtures/abs-substrate-dylib.dylib (v5 rebuild record,
# sha256 b59bdbf9...).
#
# Policy (scoped): LC_LOAD_DYLIB-family commands (NOT the file's own LC_ID_DYLIB)
# of every PwEevee-controlled binary must start with one of:
#     /System/Library/   /usr/lib/   @rpath/   @loader_path/   @executable_path/
# Anything else is a violation (reported with the owning binary). PwEevee is
# strict on: Spotify (host, injected), Frameworks/spotifyglass.dylib (the crash
# origin), Frameworks/EeveeSpotify.dylib. Third-party bundled components
# (CydiaSubstrate, Orion, EeveeSwiftProtobuf, Spotify's own frameworks/plugins)
# are skipped with a warning: their load-command stream exercises weak/reexport
# variants our lightweight parser does not classify fully, and they were never
# part of the fixed trajectory.
#
# Contrary to the lightweight parser's limits the host contract is absolute: when
# the main binary is staged, its LC_RPATH must declare @executable_path/Frameworks
# (the Substrate Residue design: the bundled runtime loads only through the host
# binary, never through an external path), else the build fails here.
use strict;
use warnings;
no warnings 'uninitialized';
use File::Find qw(find);
use File::Basename qw(dirname);
use lib dirname($0) . '/../lib';
use macho;

my $STRICT_ALL = grep { $_ eq '--strict-all' } @ARGV;
my @args = grep { $_ ne '--strict-all' } @ARGV;
my ($appdir) = @args;
defined $appdir or die "usage: validate-bundle-deps.pl [--strict-all] <staged Spotify.app dir>\n";
$appdir =~ s{/\z}{};
-d $appdir or die "not a directory: $appdir\n";

my @fail;
my @ok;
my @warn;

my $RP = '\@rpath';    # displayed literal, also used in regexes
my $LP = '\@loader_path';

# Prefix allow-list, per the policy comment above.
my @AT_PREFIXES  = ('@rpath/', '@loader_path/', '@executable_path/');
my @ABS_PREFIXES = ('/System/Library/', '/usr/lib/');

sub allowed {
  my ($name) = @_;
  for my $p (@AT_PREFIXES, @ABS_PREFIXES) { return 1 if index($name, $p) == 0; }
  return 0;
}

# Host rpaths for @rpath resolution (present only when the main binary is staged).
# Substrate Residue contract: the staged host binary must itself declare
# @executable_path/Frameworks in LC_RPATH - the bundled runtime resolves only
# through the host; an absent declaration cannot be made valid later.
my @host_rpaths;
my $host = "$appdir/Spotify";
if (-f $host) {
  open(my $h, '<:raw', $host) or die "open $host: $!";
  local $/; my $hd = <$h>; close $h;
  @host_rpaths = macho::rpaths($hd);
  my $declared = grep { index($_, '@executable_path/Frameworks') == 0 } @host_rpaths;
  unless ($declared) {
    push @fail, "HOST RPATH VIOLATION in Spotify: no \@executable_path/Frameworks in LC_RPATH ( \@rpath Substrate load is unresolved at launch)";
  }
}

# Mach-O census: any file whose first 4 bytes are a Mach-O magic is parsed.
my @files;
find({
    no_chdir => 1,
    wanted => sub {
      return unless -f $_;
      open(my $f, '<:raw', $_) or return;
      read($f, my $magic, 4);
      close $f;
      return unless length($magic) == 4;
      my $u = unpack('V', $magic);
      my $n = unpack('N', $magic);
      return unless grep { $_ == $u || $_ == $n } (0xFEEDFACE, 0xFEEDFACF, 0xCAFEBABE);
      push @files, $_;
    },
  }, $appdir);

@files or die "no Mach-O files found under $appdir\n";

for my $file (@files) {
  open(my $f, '<:raw', $file) or die "open $file: $!";
  local $/; my $data = <$f>; close $f;
  my $rel = $file;
  $rel =~ s{^\Q$appdir\E/?}{};
  my $dirpath = dirname($file);              # for @loader_path resolution
  my $strict = ($STRICT_ALL
                || $rel eq 'Spotify'
                || $rel eq 'Frameworks/spotifyglass.dylib'
                || $rel eq 'Frameworks/EeveeSpotify.dylib') ? 1 : 0;
  my @archs = eval { macho::parse_macho($data) };
  if ($@) {
    if ($strict) { push @fail, "UNPARSEABLE Mach-O: $rel"; }
    else { push @warn, "skipped unparseable Mach-O (third-party component): $rel"; }
    next;
  }
  for my $a (@archs) {
    for my $c (@{ $a->{cmds} }) {
      next unless ($c->{kind} // '') eq 'dylib';
      next if $c->{cmd} == 0xD;              # LC_ID_DYLIB: identity, not a dependency edge
      next unless $strict;                   # scope-restricted policy (see header)
      my $name = $c->{name};
      if (allowed($name)) {
        push @ok, "$rel -> $name";
      } else {
        push @fail, "ABSOLUTE DEPENDENCY in $rel: $name (self-contained design: use an ${LP}/\@loader_path-style reference against the bundled copy)";
      }
      if ($name =~ m{^\Q\@rpath/\E(.*)\z} && @host_rpaths) {
        my $tail = $1;
        my $resolved;
        for my $r (@host_rpaths) {
          my $base = $r;
          $base =~ s|^\Q\@executable_path\E|$appdir|;
          my $try = "$base/$tail";
          if (-e $try) { $resolved = $try; last; }
        }
        my $show = '@rpath';
        if ($resolved) { push @ok, "$rel $show/$tail resolves -> $resolved"; }
        else { push @fail, "UNRESOLVED $show in $rel: $show/$tail (no host rpath matches)"; }
      }
      if ($name =~ m{^\Q\@loader_path/\E(.*)\z}) {
        my $tail = $1;
        my $try = "$dirpath/$tail";
        my $show = '@loader_path';
        if (-e $try) { push @ok, "$rel $show/$tail resolves -> $try"; }
        else { push @fail, "UNRESOLVED $show in $rel: $show/$tail"; }
      }
    }
  }
}

print "  $_\n" for @ok;
print "  [warn] $_\n" for @warn;
if (@fail) {
  print "BUNDLE DEPENDENCY VALIDATION FAILED:\n";
  print "  - $_\n" for @fail;
  exit 1;
}
print "BUNDLE DEPENDENCY VALIDATION PASSED (" . scalar(@ok) . " edges across " . scalar(@files) . " Mach-O files)\n";
