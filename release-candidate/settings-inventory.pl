#!/usr/bin/env perl
# Settings inventory generator for the v3.1.0 RC audit.
#   perl release-candidate/settings-inventory.pl <repo-root> > release-candidate/settings-inventory.tsv
# Every output line is derived from the tweak sources on disk; nothing is invented.
use strict;
use warnings;
use File::Find;
use File::Spec;

my $ROOT = shift or die "usage: settings-inventory.pl <repo-root>\n";
my $SP = File::Spec->catdir($ROOT, 'Spotipw', 'tweak', 'Sources');

my %ctor_count;
my $nrows  = 0;
my %seen_key;

sub rows_of {
  my ($dir) = @_;
  find({ wanted => \&scan, no_chdir => 1 }, $dir);
}

sub scan {
  return unless /\.(?:x|m|h)\z/;   # keys live in headers, rows in .m/.x
  local $/;
  open my $f, '<', $_ or return;
  my $d = <$f> or return;
  close $f;
  $d =~ s/\r//g;
  my $file = $File::Find::name;

  # registry keys: #define SGKeyX @"value"  (also const NSString *SGKeyX = @"...")
  while ($d =~ /#\s*define\s+SGKey([A-Za-z0-9]+)\s+@"([^"]*)"|NSString\s*\*\s*const\s+SGKey([A-Za-z0-9]+)\s*=\s*@"([^"]*)"/g) {
    my $name = defined $1 ? $1 : $3;
    my $val  = defined $2 ? $2 : $4;
    my ($name, $val) = ($1, $2);
    next if $seen_key{"K:$name"};
    $seen_key{"K:$name"} = 1;
    print "KEY\t$name\t$val\t$file\n";
  }

  # row call-sites: balanced-paren scan from each constructor
  while ($d =~ /\b((?:SGSwitchRow|SGHideRow|SGOptionRow|SGUnstableRow|SGFlagRow|SGKillRow|SGChoiceRow|SGSliderRow|SGStatRow|SGActionRow|SGWarningRow|SGPageRow|SGLinkRow|SGStatActionRow))\(/g) {
    my $ctor = $1;
    my $i    = pos($d);
    my $depth = 1;
    while ($depth > 0 && $i < length $d) {
      my $ch = substr($d, $i, 1);
      $depth++ if $ch eq '(';
      $depth-- if $ch eq ')';
      $i++;
    }
    my $args = substr($d, pos($d), $i - pos($d) - 1);

    my ($keyname)  = $args =~ /\bSGKey([A-Za-z0-9]+)/;
    my ($flagkey)  = $args =~ /@"((?:ios|spoti|spotify|com\.)[^"]*)"/;
    my ($title)    = $args =~ /@"([^"]*)"/;
    my $k = defined $keyname ? "SGKey$keyname"
          : defined $flagkey ? "flag:$flagkey"
          : '(none)';
    $k  =~ s/^SGKey//;
    $title //= '';
    $title =~ s/\s+/ /g;
    my $def = $ctor =~ /^(SGSwitchRow|SGPageRow)$/ ? 'on'
            : $ctor =~ /^(SGHideRow|SGOptionRow|SGUnstableRow)$/ ? 'off'
            : $ctor eq 'SGFlagRow' ? 'force-on'
            : $ctor eq 'SGKillRow' ? 'force-off'
            : 'n/a';
    print "ROW\t$ctor\t$k\t$title\t$def\t$file\n";
    $ctor_count{$ctor}++;
    $nrows++;
  }
}

rows_of($SP);
print "TOTAL\trows=$nrows\t", join(', ', map { "$_=" . ($ctor_count{$_} // 0) } sort keys %ctor_count), "\n";
