#!/usr/bin/perl
# Rebuild EeveeSpotify-6.6.8-SelfContained.deb (v2) so Sideloadly injects the tweak.
#
# Payload layout (all paths in data.tar):
#   Spotify.app/<bundle, Frameworks minus bare dylib, theme PNGs>   (as in v1, known to merge)
#   var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib   (byte-identical)
#   var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.plist   (original filter)
#
# control.tar.gz is reused verbatim from the existing deb (no dep/orion changes needed).
use strict; use warnings;

my $OUT      = $ENV{OUT} || "EeveeSpotify-6.6.8-SelfContained-v2.deb";
my $BUILDDIR = "/tmp/eevee_build";
my $PAYLOAD  = "$BUILDDIR/payload";

# NOTE: use the SelfContained deb's copy (631d4f17...) which is byte-identical to the
# known-good working IPA - NOT the original jailbreak deb's copy (01087637...).
my $SRC_DYLIB  = "/tmp/self_ext/Spotify.app/Frameworks/EeveeSpotify.dylib";
my $SRC_PLIST  = "/tmp/eevee_filter.plist";
my $SRC_APPDIR = "/tmp/self_ext/Spotify.app";
my $OLD_DEB    = $ENV{OLD_DEB} || die "set OLD_DEB to the existing EeveeSpotify-6.6.8-SelfContained.deb\n";
my $MTIME      = 1750000000;

# ---------- 1. stage payload ----------
system("rm -rf $BUILDDIR && mkdir -p -m 755 '$PAYLOAD/Spotify.app' '$PAYLOAD/var/jb/Library/MobileSubstrate/DynamicLibraries'") == 0
    or die "mkdir failed";

# 1a. app-level files except Frameworks (bundle, PNGs)
opendir(my $dh, $SRC_APPDIR) or die;
while (my $e = readdir($dh)) {
    next if $e eq '.' || $e eq '..' || $e eq 'Frameworks';
    system("cp -a '$SRC_APPDIR/$e' '$PAYLOAD/Spotify.app/'") == 0 or die "cp $e";
}
closedir($dh);

# 1b. frameworks except the bare EeveeSpotify.dylib (moved to MobileSubstrate pair)
mkdir("$PAYLOAD/Spotify.app/Frameworks", 0755) or die;
opendir(my $fh2, "$SRC_APPDIR/Frameworks") or die;
while (my $e = readdir($fh2)) {
    next if $e eq '.' || $e eq '..' || $e eq 'EeveeSpotify.dylib';
    system("cp -a '$SRC_APPDIR/Frameworks/$e' '$PAYLOAD/Spotify.app/Frameworks/'") == 0 or die "cp fw $e";
}
closedir($fh2);

# 1c. the tweak pair (dylib exactly once, in the MobileSubstrate layout)
system("cp -a '$SRC_DYLIB' '$PAYLOAD/var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib'") == 0 or die;
system("cp -a '$SRC_PLIST' '$PAYLOAD/var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.plist'") == 0 or die;

# ---------- 2. deterministic ustar writer (fixed-width fields) ----------
sub pad { my ($s, $n) = @_; die "field too long: '$s' > $n" if length($s) > $n; return $s . ("\0" x ($n - length($s))); }

sub ustar_entry {
    my ($name, $type, $mode, $content) = @_;
    $content = '' unless defined $content;
    my $size = length $content;
    my ($prefix, $fname) = ('', $name);
    if (length($name) > 100) {
        my @parts = split('/', $name);
        for my $i (reverse 1..$#parts) {
            my $p = join('/', @parts[0..$i-1]);
            my $n = join('/', @parts[$i..$#parts]);
            if (length($p) <= 155 && length($n) <= 100) { $prefix = $p; $fname = $n; last; }
        }
        die "cannot split name: $name" if length($fname) > 100;
    }
    my $hdr = "\0" x 512;
    substr($hdr,   0, 100) = pad($fname, 100);
    substr($hdr, 100,   8) = pad(sprintf("%07o", $mode), 8);
    substr($hdr, 108,   8) = pad("0000000", 8);
    substr($hdr, 116,   8) = pad("0000000", 8);
    substr($hdr, 124,  12) = pad(sprintf("%011o", $size), 12);
    substr($hdr, 136,  12) = pad(sprintf("%011o", $MTIME), 12);
    substr($hdr, 148,   8) = "        ";                       # checksum placeholder
    substr($hdr, 156,   1) = $type;
    substr($hdr, 257,   6) = "ustar\0";
    substr($hdr, 263,   2) = "00";
    substr($hdr, 345, 155) = pad($prefix, 155);
    my $sum = 0; $sum += ord for split //, $hdr;
    substr($hdr, 148,   8) = sprintf("%06o", $sum) . "\0 ";    # 6 digits + NUL + space = 8
    die "header not 512" unless length($hdr) == 512;
    return $hdr . $content . ("\0" x ((512 - $size % 512) % 512));
}

my @entries;
sub walk {
    my ($dir, $rel) = @_;
    push @entries, [$rel, '5', 0755, ''] unless $rel eq '';
    opendir(my $d, $dir) or die "opendir $dir: $!";
    for my $e (sort readdir($d)) {
        next if $e eq '.' || $e eq '..';
        my $full = "$dir/$e";
        my $r = $rel eq '' ? $e : "$rel/$e";
        if (-d $full) { walk($full, $r); }
        else {
            open(my $f, '<:raw', $full) or die "open $full: $!";
            local $/; my $c = <$f>; close $f;
            push @entries, [$r, '0', 0644, $c];
        }
    }
    closedir($d);
}
walk($PAYLOAD, '');
@entries = sort { $a->[0] cmp $b->[0] } @entries;

open(my $tf, '>:raw', "$BUILDDIR/data.tar") or die;
print $tf ustar_entry(@$_) for @entries;
print $tf "\0" x 1024;
close $tf;

# ---------- 3. compress: preset -9 = 64MiB dict (matches original debs) ----------
system("rm -f $BUILDDIR/data.tar.lzma && xz --format=lzma -9 -T1 -c $BUILDDIR/data.tar > $BUILDDIR/data.tar.lzma") == 0
    or die "xz failed";

# ---------- 4. reuse control.tar.gz verbatim ----------
open(my $of, '<:raw', $OLD_DEB) or die;
local $/; my $olddata = <$of>; close $of;
my $off = 8; my $control;
while ($off + 60 <= length($olddata)) {
    my $h = substr($olddata,$off,60);
    my $n = substr($h,0,16); $n =~ s/\/\s*$//; $n =~ s/\s+$//;
    my $s = substr($h,48,10); $s =~ s/\s//g;
    last unless $s =~ /^\d+$/; $s = int($s);
    if ($n eq 'control.tar.gz') { $control = substr($olddata,$off+60,$s); }
    $off += 60 + $s; $off++ if $off % 2;
}
die "no control.tar.gz found" unless defined $control;

# ---------- 5. ar archive ----------
sub ar_member {
    my ($name, $data) = @_;
    my $hdr = sprintf("%-16s%-12d%-6d%-6d%-8o%-10d`\n", "$name/", 0, 0, 0, 100644, length $data);
    die "bad ar hdr" unless length($hdr) == 60;
    $data .= "\n" if length($data) % 2;
    return $hdr . $data;
}
open(my $arf, '>:raw', $OUT) or die;
print $arf "!<arch>\n";
print $arf ar_member('debian-binary', "2.0\n");
print $arf ar_member('control.tar.gz', $control);
{
    open(my $d, '<:raw', "$BUILDDIR/data.tar.lzma") or die;
    local $/; my $c = <$d>; close $d;
    print $arf ar_member('data.tar.lzma', $c);
}
close $arf;
print "WROTE $OUT\n";
