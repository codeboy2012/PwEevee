#!/usr/bin/env perl
# Validate the staged Spotify.app filesystem structure before packaging.
#
#   PwEvevee/build-system/validate/validate-ipa.pl <staged Spotify.app> [watch-enabled]
#
# Fails on:
#   - nested *.app bundles (no Spotify.app inside Spotify.app)
#   - Watch app leftovers (Watch/, *Watch*.app) — UNLESS watch-enabled was
#     passed, in which case unified.sh has just normalized the Watch tree
#     through watchfix-stage.sh and this check defers to validate-watchfix.pl
#   - development-only files (.git, .DS_Store, *.o, debug trees, __MACOSX)
#   - duplicate dylib/framework names anywhere in the tree
#   - missing critical app files (Info.plist, executable, PkgInfo)
use strict;
use warnings;
use File::Find;

my $app = $ARGV[0] or die "usage: validate-ipa.pl <staged Spotify.app> [watch-enabled]\n";
my $watch_enabled = defined $ARGV[1] && $ARGV[1] ne '0' && $ARGV[1] ne '';
$app =~ s{/+$}{};

my @fail;
my %names;
my ($ndylib, $nfw) = (0, 0);

find({ wanted => sub {
  my $rel = $File::Find::name;
  $rel =~ s/^\Q$app\E\/?//;
  return unless length $rel;
  if (-d $_) {
    if ($rel =~ m{\.app/.*\.app$}i) { push @fail, "NESTED APP BUNDLE: $rel"; }
    # Watch leftovers: hard fail only when the pipeline did NOT enable watch.
    # With watch enabled, validate-watchfix.pl has already validated the
    # companion tree (IDs, Intents, metadata) more thoroughly than a
    # filename grep can.
    if (!$watch_enabled && ($rel =~ m{^Watch}i || $rel =~ m{/Watch}i)) {
      push @fail, "WATCH APP LEFTOVER: $rel (re-run unified.sh with --watch to keep it)";
    }
    if ($rel eq '__MACOSX') { push @fail, "DEVELOPMENT JUNK: __MACOSX"; }
    if (/\.framework$/ && $rel =~ m{^Frameworks/[^/]+$}) {
      $nfw++;
      my $base = $_;
      push @fail, "DUPLICATE FRAMEWORK: $base" if $names{"fw:$base"}++;
    }
    return;
  }
  if (/^\.DS_Store$/ || /^\.git/ || /\.o$/ || /\.orig$/ || /\.rej$/) {
    push @fail, "DEVELOPMENT-ONLY FILE: $rel";
  }
  if (/\.dylib$/ && $rel =~ m{^Frameworks/[^/]+$}) {
    $ndylib++;
    push @fail, "DUPLICATE DYLIB: $_" if $names{"dy:$_"}++;
  }
}, no_chdir => 1 }, $app);

-f "$app/Info.plist"  or push @fail, "MISSING: Info.plist";
-f "$app/Spotify"     or push @fail, "MISSING: Spotify executable";
-f "$app/PkgInfo"     or push @fail, "MISSING: PkgInfo";
-d "$app/Frameworks"  or push @fail, "MISSING: Frameworks/";

if (@fail) {
  print "STRUCTURE VALIDATION FAILED:\n";
  print "  - $_\n" for @fail;
  exit 1;
}
print "STRUCTURE VALIDATION PASSED ($ndylib dylibs, $nfw frameworks, no nesting, no junk",
      ($watch_enabled ? ', watch kept' : '', ")\n");
