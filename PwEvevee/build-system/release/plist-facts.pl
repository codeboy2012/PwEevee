#!/usr/bin/env perl
# plist-facts.pl — print top-level scalar/bool values of any plist as JSON.
# Usage: perl plist-facts.pl <file.plist> [Key ...]
#   (no Key args = print every top-level string key as JSON)
##   XML and binary plist inputs are both handled; output is a flat JSON object
# mapping key → scalar string, ready to feed into update-appsource.pl's
# registry through appsource-update.yml. Reuses the same binary-plist reader
# as the audit tooling (audit/ipas/tools/bpkeys.pl) but emits JSON.
use strict;
use warnings;
use JSON::PP;

my $FILE = $ARGV[0] or die "usage: plist-facts.pl <plist> [Key ...]\n";
my @want = @ARGV[1 .. $#ARGV];
open(my $f, '<:raw', $FILE) or die "open $FILE: $!";
local $/; my $b = <$f>; close $f;

my %out;

if (substr($b, 0, 6) ne 'bplist') {
    # XML: scan top-level <key>..</key> followed by next element
    while ($b =~ m{<key>([^<]+)</key>\s*<(/?\w+)([^>]*)>([^<]*)}g) {
        my ($k, $t, $attrs, $v) = ($1, $2, $3, $4);
        next if $t eq '/';
        $v = '' if !defined $v;
        my $out;
        if    ($t eq 'true')  { $out = 'true' }
        elsif ($t eq 'false') { $out = 'false' }
        elsif ($t eq 'dict' or $t eq 'array') { next }
        else { ($v) = $v =~ m{([^<]*)(?:</\w+)?$}; $out = $v }
        next if !defined $out || (!length($out||'') && ($t ne 'string'));
        emit($k, $out);
    }
} else {
    # Canonical 32-byte trailer readout (same rules as audit/ipas/tools/bpkeys.pl)
    my $tr     = substr($b, -32, 32);
    my $osize  = unpack("C", substr($tr, 6, 1));
    my $rsize  = unpack("C", substr($tr, 7, 1));
    my $numobj = ubig($tr,  8, 8);
    my $top    = ubig($tr, 16, 8);
    my $offtab = ubig($tr, 24, 8);
    die "bad trailer (osize=$osize rsize=$rsize)"
      unless 1 <= $osize && $osize <= 8 && 1 <= $rsize && $rsize <= 8;

    sub ubig { my ($s,$o,$n)=@_; my $v=0; for my $i (0..$n-1){ $v=$v*256+unpack("C",substr($s,$o+$i,1)) } $v }
    sub objoff { my $i=shift; die "obj idx $i >= $numobj\n" unless $i < $numobj;
                 my $off = ubig($b,$offtab+$osize*$i,$osize); die "obj $i offset $off beyond EOF\n" unless $off < length($b); return $off }
    sub uint { my ($o,$n)=@_; return ubig($b,$o,$n) }
    sub extlen { my ($o,$n)=@_; return $n unless $n==15;
                 my $b2=unpack("C",substr($b,$o+1,1)); die "no extlen" unless ($b2>>4)==1;
                 return uint($o+2, 1<<($b2 & 0x0F)) }
    sub lhdr { my ($o,$n)=@_; return 1 unless $n==15;
               my $b2=unpack("C",substr($b,$o+1,1)); die "no extlength-carrying marker" unless ($b2>>4)==1;
               return 2 + (1 << ($b2 & 0x0F)) }

    my %seen;
    sub emit {
        my ($k, $v) = @_;
        return if $seen{$k}++;
        return if @want && !grep { $_ eq $k } @want;
        $out{$k} = $v;
    }

    my $o  = objoff($top);
    my $b0 = unpack("C", substr($b, $o, 1));
    die sprintf("top object not dict (type 0x%02x) at offset $o\n", $b0 >> 4)
      unless ($b0 >> 4) == 0xD;
    my $cnt = ($b0 & 0x0F) == 15 ? extlen($o, 15) : ($b0 & 0x0F);
    my $hdr = ($b0 & 0x0F) == 15 ? 2 + (1 << (unpack("C", substr($b, $o + 1, 1)) & 0x0F)) : 1;
    for my $i (0 .. $cnt - 1) {
        my $kref = uint($o + $hdr + $i * $rsize, $rsize);
        my $vref = uint($o + $hdr + ($cnt + $i) * $rsize, $rsize);
        emit(val($kref, 1), val($vref, 0));
    }

    sub val {
        my ($idx, $iskey) = @_;
        my $o  = objoff($idx);
        my $b0 = unpack("C", substr($b, $o, 1));
        my $t = $b0 >> 4; my $n = $b0 & 0x0F;
        my $h = lhdr($o, $n);
        if ($t == 0x5) { my $L = extlen($o,$n); return substr($b, $o+$h, $L) }
        if ($t == 0x6) {   # UTF-16BE strings: only queried ASCII keys matter, so
                           # collapse NULs and keep the printable run
            my $L = extlen($o,$n); my $s = substr($b, $o+$h, $L);
            $s =~ s/\x00//g; return $s }
        if ($t == 0x1) { my $Ln = 1<<$n; return uint($o+1, $Ln) }
        if ($t == 0x0) { return $n==9 ? 'true' : $n==8 ? 'false' : undef }
        if ($t == 0x2) { my $Ln=1<<$n; my $v = $Ln==8 ? unpack("d>",substr($b,$o+1,8)) : unpack("f>",substr($b,$o+1,4)); return 0+$v }
        return undef;
    }
}

print JSON::PP->new->encode(\%out);
