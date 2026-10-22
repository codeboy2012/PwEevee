#!/usr/bin/perl
# Perl port of Spotipw/scripts/extract-flags.py for machines without python/otool/nm (Windows MINGW64).
# Recovers Spotify's remote-config flag keys, types and defaults from a decrypted arm64 main binary by
# walking the -[SPT*ImplProperties initWithConfigurationProvider:] thunks, then writes
# tweak/Sources/Shared/Flags/SGFlagList.m.
#
#   perl scripts/extract-flags.pl /path/to/decrypted/Spotify/binary [out.m]
use strict;
use warnings;

my ($binpath, $outpath) = @ARGV;
$outpath ||= 'tweak/Sources/Shared/Flags/SGFlagList.m';
my $BASE = 4294967296;   # 0x100000000 (plain decimal: perl warns on >32-bit hex literals)

my %SELS = (
    'boolValueForId:defaultValue:'          => 'Bool',
    'intValueForId:lower:upper:defaultValue:' => 'Int',
    'enumValueForId:values:defaultValue:'   => 'Enum',
);

open my $fh, '<:raw', $binpath or die "$binpath: $!";
local $/; my $data = <$fh>; close $fh;

# ---- Mach-O header / segments ---------------------------------------------
my ($magic, $cputype, $cpusub, $filetype, $ncmds) = unpack('VVVVV', substr($data, 0, 20));
die "not a 64-bit Mach-O\n" unless $magic == 0xfeedfacf;
my @segs;   # [vmaddr, fileoff, filesize]
my ($nlistoff, $nlistn, $stroff, $strsize);
{
    my $off = 32;
    for my $i (1 .. $ncmds) {
        my ($cmd, $size) = unpack('VV', substr($data, $off, 8));
        if ($cmd == 0x19) {   # LC_SEGMENT_64
            my $segname = substr($data, $off + 8, 16); $segname =~ s/\0.*//s;
            my ($vmaddr, $vmsize, $fileoff, $filesize) = unpack("x16 Q<Q<Q<Q<", substr($data, $off + 8, 64));
            push @segs, [$vmaddr, $fileoff, $filesize] if $segname ne '__PAGEZERO' && $filesize > 0;
        } elsif ($cmd == 0x02) {   # LC_SYMTAB
            ($nlistoff, $nlistn, $stroff, $strsize) = unpack('V4', substr($data, $off + 8, 16));
        }
        $off += $size;
    }
}
sub segoff {
    my ($addr) = @_;
    for my $s (@segs) {
        my ($vm, $fo, $fs) = @$s;
        return $addr - $vm + $fo if $vm <= $addr && $addr < $vm + $fs;
    }
    return undef;
}
sub insn {
    my ($addr) = @_;
    my $o = segoff($addr) // return undef;
    return unpack('V', substr($data, $o, 4));
}
sub cstring {
    my ($addr) = @_;
    my $o = segoff($addr) // return undef;
    my $end = index($data, "\0", $o);
    $end = $o + 256 if $end < 0 || $end > $o + 256;
    my $s = substr($data, $o, $end - $o);
    return undef if $s eq '' || $s =~ /[^\x20-\x7e]/;
    return $s;
}

# ---- string table + symbol table (replaces strings -t x / nm -n) ----------
sub str_at {
    my ($off) = @_;
    my $end = index($data, "\0", $off);
    $end = $off + 300 if $end < 0 || $end > $off + 300;
    my $s = substr($data, $off, $end - $off);
    return undef if $s eq '' || $s =~ /[^\x20-\x7e]/;
    return $s;
}

# keys: every "ios-*" flag key cstring with its vm address.
# Like the python original (strings -t x over the whole binary), scan the entire file:
# flag keys live in __TEXT __cstring/__objc_methname (vm = BASE + fileoff since __TEXT
# vmaddr==BASE with fileoff 0), NOT in the symtab string table.
my %keys;
{
    my $n = 0;
    for (my $o = 0; $o < length($data) - 8; $o++) {
        my $b = ord(substr($data, $o, 1));
        next unless $b == ord('i');
        my $s = str_at($o);
        next unless defined $s && $s =~ /^ios-[a-z0-9-]+\.[A-Za-z0-9_.-]+$/;
        # vm address for a file offset: reverse of segoff
        for my $sg (@segs) {
            my ($vm, $fo, $fs) = @$sg;
            if ($o >= $fo && $o < $fo + $fs) {
                $keys{$vm + ($o - $fo)} = $s;
                $n++;
                last;
            }
        }
        # skip past the string we just consumed
        $o += length($s) if defined $s && length($s) > 1;
    }
    print STDERR "keys: $n\n";
}

# thunks: -[SPT*ImplProperties initWithConfigurationProvider:] IMPs.
# The python original uses `nm -n`, but this binary is built with chained fixups and has NO local
# ObjC method symbols in the symtab. Instead, walk the ObjC runtime structures:
#   class_ro_t.name is a chained pointer (low 32 bits = target va offset from BASE);
#   class_ro_t.baseMethodList likewise points at a relative method list (flags 0x8000000c),
#   whose entries are (name rel-to-field -> selref, types rel, imp rel-to-field).
#   selref qwords live in __DATA __objc_selrefs: low 32 bits = cstring va offset from BASE.
sub cstr2 {
    my ($va) = @_;
    return undef if $va < $BASE;
    my $o = segoff($va) // return undef;
    return undef if $o >= length($data);
    my $e = index($data, "\0", $o);
    return undef if $e < 0 || $e > $o + 300;
    my $s = substr($data, $o, $e - $o);
    return undef if $s eq '' || $s =~ /[^\x20-\x7e]/;
    return $s;
}
sub selref_at {
    my ($va) = @_;
    my $o = segoff($va) // return undef;
    return undef if $o < 0 || $o + 8 > length($data);
    my $q = unpack('Q<', substr($data, $o, 8));
    my $t = $q & 0xFFFFFFFF;
    return undef if $t == 0;
    return cstr2($BASE + $t);
}
sub ptr_target { return $BASE + ($_[0] & 0x0000FFFFFFFFFFFF); }
my @thunks;
{
    # locate the __objc_classname section: class names live there (va range scanned below)
    my ($cnlo, $cnhi);
    {
        my $off = 32;
        for my $i (1 .. $ncmds) {
            my ($cmd, $size) = unpack('VV', substr($data, $off, 8));
            if ($cmd == 0x19) {
                my $nsects = unpack('V', substr($data, $off + 64, 4));
                for my $s (0 .. $nsects - 1) {
                    my $so = $off + 72 + $s * 80;
                    my $sectname = substr($data, $so, 16); $sectname =~ s/\0.*//s;
                    if ($sectname eq '__objc_classname') {
                        my ($addr, $asz) = unpack('Q<Q<', substr($data, $so + 32, 16));
                        $cnlo = $addr - $BASE; $cnhi = $cnlo + $asz;
                    }
                }
            }
            $off += $size;
        }
    }
    die "no __objc_classname section\n" unless defined $cnlo;
    my %thunkseen;
    # scan all pointer slots in __DATA_CONST/__DATA for class_ro_t name pointers
    for (my $o = 0; $o < length($data) - 48; $o += 8) {
        my $q = unpack('Q<', substr($data, $o, 8));
        my $low = $q & 0xFFFFFFFF;
        next unless $low >= $cnlo && $low < $cnhi;
        next unless ($q >> 48) == 0x0010;          # chained pointer with a target
        my $name = cstr2($BASE + $low);
        next unless defined $name && $name =~ /^SPT\w+ImplProperties$/;
        my $ro = $BASE + $o - 24;                  # name is class_ro_t + 24
        my $mlp = unpack('Q<', substr($data, $o + 8, 8));   # baseMethodList at ro+32
        next unless ($mlp >> 48) == 0x0010;
        my $mlva = ptr_target($mlp);
        my $mlo = segoff($mlva) // next;
        my ($fl, $cnt) = unpack('VV', substr($data, $mlo, 8));
        next unless ($fl & 0xFFFF0000) == 0x80000000 && ($fl & 0xFFFF) == 12 && $cnt > 0 && $cnt < 500;
        for my $e (0 .. $cnt - 1) {
            my $eo = $mlo + 8 + $e * 12;
            last if $eo + 12 > length($data);
            my $rname = unpack('l<', substr($data, $eo, 4));
            next if $rname == 0 || abs($rname) > 0x4000000;
            my $sel = selref_at($mlva + ($eo - $mlo) + $rname) // next;
            next unless $sel eq 'initWithConfigurationProvider:';
            my $rimp = unpack('l<', substr($data, $eo + 8, 4));
            my $imp = $mlva + ($eo - $mlo) + 8 + $rimp;
            push @thunks, $imp unless $thunkseen{$imp}++;
        }
    }
    my $n = scalar(@thunks);
    print STDERR "thunks: $n\n";
    die "no initWithConfigurationProvider: thunks found — is this a decrypted Spotify arm64 binary?\n" unless @thunks;
}

# ---- arm64 decoder (same coverage as the python original) -----------------
sub sext { my ($v, $bits) = @_; return ($v & (1 << ($bits - 1))) ? $v - (1 << $bits) : $v; }
sub bitmask {
    my ($i) = @_;
    my ($n, $immr, $imms, $sf) = ((($i >> 22) & 1), (($i >> 16) & 0x3f), (($i >> 10) & 0x3f), ($i >> 31) & 1);
    my $length;
    if ($n) { $length = 6; }
    else {
        my $ni = (~$imms) & 0x3f;
        $length = log($ni + 1) / log(2);
        return undef if $length != int($length) || $length < 0;
    }
    my $esize = 1 << $length;
    my $levels = $esize - 1;
    my ($s, $r) = ($imms & $levels, $immr & $levels);
    my $welem = (1 << ($s + 1)) - 1;
    my $elem = ((($welem >> $r) | ($welem << ($esize - $r))) & ((1 << $esize) - 1));
    my $v = 0;
    for (1 .. (($sf ? 64 : 32) / $esize)) { $v = (($v << $esize) | $elem) & (($sf ? 64 : 32) == 64 ? ~0 : 0xffffffff); }
    return $v;
}
sub decode {
    my ($i, $pc) = @_;
    my $width = ($i >> 31) ? ~0 : 0xffffffff;
    if (($i & 0x9F000000) == 0x90000000) {
        return ['adrp', $i & 31, ($pc & ~0xfff) + ((sext(((($i >> 5) & 0x7FFFF) << 2) | (($i >> 29) & 3), 21)) << 12)];
    }
    if (($i & 0x7F800000) == 0x11000000) { return ['add', $i & 31, ($i >> 5) & 31, ((($i >> 10) & 0xfff)) << (($i >> 22) & 1)]; }
    if (($i & 0x7F800000) == 0x51000000) { return ['add', $i & 31, ($i >> 5) & 31, -((($i >> 10) & 0xfff)) << (($i >> 22) & 1)]; }
    if (($i & 0x7F800000) == 0x52800000) { return ['movz', $i & 31, ((($i >> 5) & 0xffff) << ((($i >> 21) & 3) * 16)) & $width]; }
    if (($i & 0x7F800000) == 0x12800000) { return ['movz', $i & 31, (~((($i >> 5) & 0xffff) << ((($i >> 21) & 3) * 16))) & $width]; }
    if (($i & 0x7F800000) == 0x72800000) { return ['movk', $i & 31, ((($i >> 5) & 0xffff) << ((($i >> 21) & 3) * 16)), ((($i >> 21) & 3) * 16)]; }
    if (($i & 0x7FE0FFE0) == 0x2A0003E0) { return ['mov', $i & 31, ($i >> 16) & 31]; }
    if (($i & 0x7F800000) == 0x32000000) { return ['orri', $i & 31, ($i >> 5) & 31, bitmask($i)]; }
    if (($i & 0xFFC00000) == 0xF9400000) { return ['ldr', $i & 31, ($i >> 5) & 31, ((($i >> 10) & 0xfff)) << 3]; }
    if (($i & 0xFC000000) == 0x94000000) { return ['bl', $pc + sext($i & 0x3FFFFFF, 26) * 4]; }
    if (($i & 0xFC000000) == 0x14000000) { return ['b', $pc + sext($i & 0x3FFFFFF, 26) * 4]; }
    return ['ret'] if $i == 0xD65F03C0;
    return ['br'] if ($i & 0xFFFFFC1F) == 0xD61F0000;
    return ['other'];
}

sub selref {
    my ($addr) = @_;
    my $o = segoff($addr) // return undef;
    my $target = unpack('Q', substr($data, $o, 8)) & 0xFFFFFFFFF;   # little-endian host; masked to 36 bits
    return cstring($target >= $BASE ? $target : $target + $BASE);
}

# ---- walker ---------------------------------------------------------------
my ($REGS, $STEPS, $FOUND, $PENDING, $KEYSREF);
my $steps;
sub is_leaf {
    my ($addr) = @_;
    for (1 .. 40) {
        my $i = insn($addr) // return 0;
        my $d = decode($i, $addr);
        return 0 if ($i & 0xFFC07FFF) == 0xA9007BFD || ($i & 0xFFC07FFF) == 0xA9807BFD || $d->[0] eq 'br';
        return 1 if $d->[0] eq 'ret' || $d->[0] eq 'b';
        $addr += 4;
    }
    return 0;
}
sub do_call {
    my %regs = %$REGS;
    my $sel = $regs{1};
    if (ref $sel eq 'ARRAY' && $SELS{ $sel->[1] }) {
        my @nums = map { (defined $_ && !ref $_) ? $_ : undef } @regs{3, 4, 5};
        if (defined $PENDING) { push @$FOUND, [$PENDING, $SELS{ $sel->[1] }, @nums]; }
        $PENDING = undef;
    } else {
        for my $v (values %regs) {
            next if ref $v;
            if (exists $KEYSREF->{$v})          { $PENDING = $KEYSREF->{$v}; last; }
            if (exists $KEYSREF->{$v + 0x20})   { $PENDING = $KEYSREF->{$v + 0x20}; last; }
        }
    }
    my %keep; @keep{ grep { $_ >= 19 } keys %regs } = @regs{ grep { $_ >= 19 } keys %regs };
    $REGS = \%keep;
}
sub run {
    my ($pc, $depth) = @_;
    $depth ||= 0;
    while ($steps < 8000) {
        $steps++;
        my $i = insn($pc) // return;
        my $d = decode($i, $pc);
        my $op = $d->[0];
        if    ($op eq 'adrp') { $REGS->{ $d->[1] } = $d->[2]; }
        elsif ($op eq 'add')  { my $v = $REGS->{ $d->[2] }; $REGS->{ $d->[1] } = (defined $v && !ref $v) ? $v + $d->[3] : undef; }
        elsif ($op eq 'movz') { $REGS->{ $d->[1] } = $d->[2]; }
        elsif ($op eq 'movk') { my $v = $REGS->{ $d->[1] }; if (defined $v && !ref $v) { $REGS->{ $d->[1] } = ($v & ~(0xffff << $d->[3])) | $d->[2]; } }
        elsif ($op eq 'mov')  { $REGS->{ $d->[1] } = ($d->[2] == 31) ? 0 : $REGS->{ $d->[2] }; }
        elsif ($op eq 'orri') { $REGS->{ $d->[1] } = ($d->[2] == 31) ? $d->[3] : $REGS->{ $d->[2] }; }
        elsif ($op eq 'ldr')  { my $v = $REGS->{ $d->[2] }; my $name = (defined $v && !ref $v) ? selref($v + $d->[3]) : undef; $REGS->{ $d->[1] } = defined $name ? ['sel', $name] : undef; }
        elsif ($op eq 'bl' || $op eq 'b') {
            if ($op eq 'b' && $depth == 0) { return; }
            if ($depth < 3 && is_leaf($d->[1])) { run($d->[1], $depth + 1); }
            else { do_call(); }
            return if $op eq 'b';
        }
        elsif ($op eq 'ret') { return; }
        elsif ($op eq 'br')  { do_call(); return; }
        $pc += 4;
    }
}

# ---- main walk ------------------------------------------------------------
my %flags;
for my $thunk (@thunks) {
    my $target;
    my $t = $thunk;
    for (1 .. 40) {
        my $i = insn($t) // last;
        my $d = decode($i, $t);
        $target = $d->[1] if $d->[0] eq 'bl';
        last if $d->[0] eq 'ret';
        $t += 4;
    }
    next unless $target;
    $REGS = {}; $steps = 0; $FOUND = []; $PENDING = undef;
    run($target, 0);
    for my $f (@$FOUND) {
        my ($key, $kind, $a, $b, $c) = @$f;
        next unless defined $key && $KEYSREF;
        if    ($kind eq 'Bool') { $flags{$key} = ['Bool', ($a // 0), 0, 0]; }
        elsif ($kind eq 'Int')  { $flags{$key} = ['Int',  ($c // 0), ($a // 0), ($b // 0)]; }
        else                    { $flags{$key} = ['Enum', 0, 0, 0]; }
    }
}
for my $k (values %keys) { $flags{$k} = ['Unknown', 0, 0, 0] unless exists $flags{$k}; }

# ---- Info.plist version ----------------------------------------------------
my $version = 'unknown';
if ($binpath =~ m{\.app/}) {
    (my $plist = $binpath) =~ s{/Spotify$}{/Info.plist};
    if (-f $plist) {
        open my $pf, '<:raw', $plist or die $!;
        local $/; my $pd = <$pf>; close $pf;
        if ($pd =~ /CFBundleShortVersionString/) {
            # crude but sufficient: 9.1.76 appears as ASCII in the plist key/value region
            ($version) = $pd =~ m{9\.\d+\.\d+}g;
        }
    }
}

my $typed = grep { $_->[0] ne 'Unknown' } values %flags;
print "flags: " . scalar(keys %flags) . ", $typed with a type and default (host version $version)\n";

open my $out, '>', $outpath or die "$outpath: $!";
print $out "// Generated by scripts/extract-flags.pl (perl port of extract-flags.py) from Spotify $version. Do not edit.\n";
print $out "#import \"Flags.h\"\n\nconst SGFlagDef SGFlagTable[] = {\n";
for my $key (sort keys %flags) {
    my ($kind, $value, $lower, $upper) = @{ $flags{$key} };
    for ($value, $lower, $upper) { $_ -= 1 << 64 if $_ >= 1 << 63; }
    print $out "    {\"$key\", SGFlag$kind, " . ($value // 0) . ', ' . ($lower // 0) . ', ' . ($upper // 0) . "},\n";
}
print $out "};\nconst NSUInteger SGFlagCount = sizeof(SGFlagTable) / sizeof(*SGFlagTable);\n";
close $out;
print "wrote $outpath\n";
