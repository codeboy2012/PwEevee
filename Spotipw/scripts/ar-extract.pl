#!/usr/bin/env perl
# Take one member out of an ar archive (a .deb is one) and write it to a file.
#
#   scripts/ar-extract.pl <archive> <member> <out>      # "out" of - writes to stdout
#   scripts/ar-extract.pl <archive> <member> -          # member bodies are padded to even length
use strict;
use warnings;

my ($archive, $member, $out) = @ARGV;
defined $out or die "usage: ar-extract.pl <archive> <member> <out|->\n";
open my $f, "<", $archive or die "$archive: $!\n";
binmode $f;
my $magic;
read($f, $magic, 8) == 8 or die "$archive: too short for an ar archive\n";
$magic eq "!<arch>\n" or die "$archive: not an ar archive\n";
while (read($f, my $h, 60) == 60) {
    my $name = substr($h, 0, 16);
    $name =~ s/\s+$//;
    $name =~ s{/$}{};
    my $size = substr($h, 48, 10);
    $size =~ s/\s//g;
    my $body = "";
    read($f, $body, $size) == $size or die "$archive: short read in $name\n";
    read($f, my $pad, $size % 2);   # members are padded to even length
    next unless $name eq $member;
    if ($out eq "-") { binmode STDOUT; print $body; }
    else {
        open my $o, ">", $out or die "$out: $!\n";
        binmode $o;
        print $o $body;
        close $o or die "$out: $!\n";
    }
    exit 0;
}
die "$archive: no member named $member\n";
