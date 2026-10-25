#!/usr/bin/env perl
# Build-system tests: ZIP determinism, Mach-O injector idempotence, plist reader.
#
#   perl PwEvevee/build-system/tests/build-tests.pl
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Digest::SHA qw(sha256_hex);
use lib dirname($0) . '/../lib';
use zip;
use macho;

my $T = "/tmp/build-test.$$";
remove_tree($T);
make_path($T);
my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }

# ---------- 1. zip writer ----------
{
  my $entries = [
    { name => 'Payload/', data => '' },
    { name => 'Payload/Spotify.app/one.bin', data => "hello" x 100 },
    { name => 'Payload/Spotify.app/empty.bin', data => '' },
    { name => 'Payload/Spotify.app/Info.plist', data => "<?xml version=\"1.0\"?><plist/>" },
  ];
  zip::write_zip("$T/a.ipa", $entries);
  zip::write_zip("$T/b.ipa", [reverse @$entries]);   # caller order wins, so a reversed list is expected to differ

  # -- regression: the ZIP writer must be deterministic for identical input --
  # (a previous version of this suite asserted `$ha eq $ha` — comparing a hash
  # to itself — so this check could never fail regardless of zip.pm behaviour.
  # Writing the SAME entry list twice and comparing the bytes is the true test.)
  zip::write_zip("$T/a2.ipa", $entries);
  my $ha  = sha256_hex(scalar _slurp("$T/a.ipa"));
  my $ha2 = sha256_hex(scalar _slurp("$T/a2.ipa"));
  ok($ha eq $ha2, 'zip writer is byte-for-byte deterministic for identical input');
  my $hb = sha256_hex(scalar _slurp("$T/b.ipa"));
  ok($hb ne $ha, 'entry order changes the archive (reverse gave different bytes)');

  my $listing = zip::read_zip_listing("$T/a.ipa");
  ok(scalar(keys %$listing) == 4, 'zip listing sees all 4 entries');
  ok($listing->{'Payload/Spotify.app/one.bin'} == 500, 'zip stores sizes correctly');
  my $back = zip::read_zip_entry("$T/a.ipa", 'Payload/Spotify.app/one.bin');
  ok($back eq ("hello" x 100), 'zip round-trips content');

  # system unzip must agree
  my $rc = system("unzip -q -o $T/a.ipa -d $T/unz > /dev/null 2>&1");
  ok($rc == 0, 'system unzip accepts our zip');
  ok(-f "$T/unz/Payload/Spotify.app/one.bin", 'unzip extracted the entries');
  ok(-s "$T/unz/Payload/Spotify.app/one.bin" == 500, 'unzip sees the right size');
}

# ---------- 2. macho injector on the real input binary ----------
{
  my $ROOT = dirname($0) . '/../../..';
  my $src = "$ROOT/Evevee Spotify/source-artifacts/Sptoify-No_Watch_App.ipa";
  {
    unless (-f $src) { print "  (input IPA absent - skipping Mach-O injector tests)\n"; }
    else {
    system("unzip -q -o \"$src\" 'Payload/Spotify.app/Spotify' -d $T/mach > /dev/null 2>&1");
    my $bin = "$T/mach/Payload/Spotify.app/Spotify";
    if (-f $bin) {
      my $before = -s $bin;
      my $out = `perl "$ROOT/PwEvevee/build-system/inject/inject-dylib.pl" $bin \@executable_path/Frameworks/spotifyglass.dylib 2>&1`;
      ok($out =~ /added/, "injector adds the load command ($out)");
      ok(-s $bin == $before, 'in-place injection does not change file size');
      my $again = `perl "$ROOT/PwEvevee/build-system/inject/inject-dylib.pl" $bin \@executable_path/Frameworks/spotifyglass.dylib 2>&1`;
      ok($again =~ /already loaded/, 'injector is idempotent');
      my $d = _slurp($bin);
      my @dy = macho::dylibs($d);
      ok((grep { $_ eq "\@executable_path/Frameworks/spotifyglass.dylib" } @dy) == 1, 'parser sees exactly one new command');
      ok(macho::slack($d) >= 0, 'slack stays non-negative after injection');

      # independent verification with the legacy tool
      my $dump = `perl "$ROOT/scripts/macho-dump.pl" $bin 2>&1`;
      ok($dump =~ /LC_LOAD_DYLIB \@executable_path\/Frameworks\/spotifyglass\.dylib/, 'legacy macho_dump.pl confirms the command');
    } else {
      ok(0, 'input IPA extracted but Spotify binary missing');
    }
    }
  }
}

# ---------- 3. plist reader ----------
{
  my $ROOT = dirname($0) . '/../../..';
  my $src = "$ROOT/Evevee Spotify/source-artifacts/Sptoify-No_Watch_App.ipa";
  {
    unless (-f $src) { print "  (input IPA absent - skipping plist reader tests)\n"; }
    else {
    my $v = `unzip -p "$src" 'Payload/Spotify.app/Info.plist' > $T/info.plist; perl "$ROOT/PwEvevee/build-system/lib/plist-value.pl" $T/info.plist CFBundleShortVersionString 2>/dev/null`;
    $v =~ s/\s+$//;
    ok($v eq '9.1.84', "plist reader gets Spotify version (got '$v')");
    }
  }
}

remove_tree($T);
if (@failures) {
  print "BUILD TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "BUILD TESTS PASSED ($pass checks)\n";
exit 0;

sub _slurp { my ($p) = @_; open(my $f, '<:raw', $p) or die "open $p: $!"; local $/; my $d = <$f>; close $f; return $d; }
