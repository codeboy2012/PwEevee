#!/usr/bin/env perl
# Print one value from an XML or binary plist.
#
#   PwEvevee/build-system/lib/plist-value.pl <plist> <Key>
use strict;
use warnings;

my ($plist, $key) = @ARGV;
defined $key or die "usage: plist-value.pl <plist> <Key>\n";

# On macOS prefer plutil for binary plists: it parses the object table correctly.
# The raw scanner below only sees serialized strings, not offsets, so on a real
# app's Info.plist it can return the WRONG object (observed: 'T16.0' instead of
# the bundle id). Keep the raw path as the portable fallback only.
if (eval { require POSIX; 1 } && $^O eq 'darwin' && -x '/usr/bin/plutil') {
  my $rc = system('/usr/bin/plutil', '-extract', $key, 'raw', '-o', '-', $plist);
  exit 0 if $rc == 0;    # plutil prints the value itself
  # fall through to the raw path when plutil cannot find/format the key
}

open(my $f, '<:raw', $plist) or die "open $plist: $!";
local $/; my $d = <$f>; close $f;

if (substr($d, 0, 6) eq 'bplist') {
  # binary plist WITHOUT plutil (other platforms): key then the value string
  # follows in the object table; take the first printable run after the key.
  # UNRELIABLE for arbitrary binaries (see comment above) — only a fallback.
  my $i = index($d, $key);
  die "key not found in binary plist: $key\n" if $i < 0;
  my $rest = substr($d, $i + length($key));
  # skip binary junk up to the next printable run of length >= 1
  if ($rest =~ /[\x20-\x7e]+/) {
    my $v = $&;
    # the very next object may be the value; guard against obviously wrong grabs
    $v =~ s/[^[:print:]]//g;
    print "$v\n";
    exit 0;
  }
  die "could not read value for $key\n";
} else {
  # XML plist
  my $i = index($d, "<key>$key</key>");
  die "key not found in plist: $key\n" if $i < 0;
  my $rest = substr($d, $i + length("<key>$key</key>"));
  if ($rest =~ /<string>([^<]*)<\/string>/) { print "$1\n"; exit 0; }
  if ($rest =~ /<integer>([^<]*)<\/integer>/) { print "$1\n"; exit 0; }
  if ($rest =~ /<real>([^<]*)<\/real>/) { print "$1\n"; exit 0; }
  if ($rest =~ /<date>([^<]*)<\/date>/) { print "$1\n"; exit 0; }
  die "no scalar value for $key\n";
}
