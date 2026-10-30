#!/usr/bin/env perl
# Mach-O load command parser for the unified build.
#
#   PwEvevee/build-system/lib/macho.pm parse <binary>     dump load commands (thin or FAT)
#   PwEvevee/build-system/lib/macho.pm slack <binary>     bytes between end of load commands
#                                                  and the first section (insertion room)
#
# Thin arm64 / armv7 files and FAT containers are handled; big- and little-endian headers
# are both parsed, mirroring Evevee Spotify/source-artifacts/tools/macho_dump.pl.
package macho;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(parse_macho load_commands dylibs rpaths slack);
our @ISA = ('Exporter');

sub rd_u32 { my ($d, $o, $swap) = @_; return $swap ? unpack('N', substr($d, $o, 4)) : unpack('V', substr($d, $o, 4)); }

sub strz {
  my ($d, $off, $max) = @_;
  $max = 512 unless defined $max;
  return '' if $off >= length($d);
  my $end = $off + $max; $end = length($d) if $end > length($d);
  my $chunk = substr($d, $off, $end - $off);
  my $z = index($chunk, "\0");
  return $z >= 0 ? substr($chunk, 0, $z) : $chunk;
}

# Parse one thin Mach-O (or every arch of a FAT one). Returns a list of arch hashes:
#   { cputype, is64, ncmds, cmds => [ { cmd, cmdsize, name?, segname? } ] }
sub parse_macho {
  my ($data) = @_;
  my $m0 = unpack('N', substr($data, 0, 4));
  my $m1 = unpack('V', substr($data, 0, 4));
  my @archs;
  if ($m0 == 0xCAFEBABE || $m1 == 0xCAFEBABE) {
    my $swap = ($m0 == 0xCAFEBABE) ? 1 : 0;
    my $n = rd_u32($data, 4, $swap);
    for my $i (0 .. $n - 1) {
      my $o = 8 + $i * 20;
      my $off  = rd_u32($data, $o + 8,  $swap);
      my $size = rd_u32($data, $o + 12, $swap);
      push @archs, parse_thin(substr($data, $off, $size));
    }
    return @archs;
  }
  return parse_thin($data);
}

sub parse_thin {
  my ($data) = @_;
  my $m1 = unpack('V', substr($data, 0, 4));
  my $m0 = unpack('N', substr($data, 0, 4));
  my ($swap, $is64);
  if    ($m1 == 0xFEEDFACF) { $swap = 0; $is64 = 1; }
  elsif ($m1 == 0xFEEDFACE) { $swap = 0; $is64 = 0; }
  elsif ($m0 == 0xFEEDFACF) { $swap = 1; $is64 = 1; }
  elsif ($m0 == 0xFEEDFACE) { $swap = 1; $is64 = 0; }
  else { die "not a Mach-O (m0=0x" . sprintf('%08x', $m0) . " m1=0x" . sprintf('%08x', $m1) . ")"; }

  my $cputype = rd_u32($data, 4, $swap);
  my $ncmds   = rd_u32($data, 16, $swap);
  my $szcmds  = rd_u32($data, 20, $swap);
  my $off = $is64 ? 32 : 28;
  my @cmds;
  for my $i (0 .. $ncmds - 1) {
    last if $off + 8 > length($data);
    my $cmd     = rd_u32($data, $off,      $swap);
    my $cmdsize = rd_u32($data, $off + 4,  $swap);
    last if $cmdsize < 8 || $off + $cmdsize > length($data);
    my $e = { cmd => $cmd, cmdsize => $cmdsize, off => $off };
    my $nameoff = $off + rd_u32($data, $off + 8, $swap);
    if ($cmd == 0xC || $cmd == 0xD || $cmd == 0x80000018 || $cmd == 0x8000001F || $cmd == 0x20 || $cmd == 0x80000023) {
      $e->{kind} = 'dylib';
      $e->{weak} = 1 if $cmd == 0x80000018;
      $e->{reexport} = 1 if $cmd == 0x8000001F;
      $e->{lazy} = 1 if $cmd == 0x20;
      $e->{upward} = 1 if $cmd == 0x80000023;
      $e->{name} = strz($data, $nameoff);
    } elsif ($cmd == 0x8000001C) {
      $e->{kind} = 'rpath'; $e->{name} = strz($data, $nameoff);
    } elsif ($cmd == 0x19 || $cmd == 0x1) {
      $e->{kind} = 'segment';
      $e->{segname} = strz($data, $off + 8, 16);
      # segment_command (0x1) vs segment_command_64 (0x19): nsects sits at 48 vs 64,
      # the section table starts at 56 vs 72, and each section is 68 vs 80 bytes with
      # its file offset at 40 vs 48. Reading the 32-bit layout with the 64-bit offsets
      # used to yield a huge nsects for armv7 binaries (CydiaSubstrate) and emit one
      # warning per phantom section - gigabytes of them on a real build.
      my $is64seg = ($cmd == 0x19);
      my $nsects = rd_u32($data, $off + ($is64seg ? 64 : 48), $swap);
      my $sbase  = $off + ($is64seg ? 72 : 56);
      my $sectsz = $is64seg ? 80 : 68;
      my $room = int(($cmdsize - ($sbase - $off)) / $sectsz);
      $nsects = $room if $nsects > $room;   # sections cannot exceed their own command
      $nsects = 0 if $nsects < 0;
      my @sects;
      for my $s (0 .. $nsects - 1) {
        my $so = $sbase + $s * $sectsz;
        push @sects, { name => strz($data, $so, 16), offset => rd_u32($data, $so + ($is64seg ? 48 : 40), $swap) };
      }
      $e->{sections} = \@sects;
    }
    push @cmds, $e;
    $off += $cmdsize;
  }
  return { cputype => $cputype, is64 => $is64, ncmds => $ncmds, sizeofcmds => $szcmds, cmds => \@cmds };
}

sub load_commands {
  my ($data) = @_;
  my @archs = parse_macho($data);
  return map { @{ $_->{cmds} } } @archs;
}

sub dylibs {
  my ($data) = @_;
  return map { $_->{name} } grep { ($_->{kind} // '') eq 'dylib' } load_commands($data);
}

sub rpaths {
  my ($data) = @_;
  return map { $_->{name} } grep { ($_->{kind} // '') eq 'rpath' } load_commands($data);
}

# Bytes of zero padding between the end of the load commands and the first section with a
# non-zero file offset. Negative when the load commands overrun (should not happen).
sub slack {
  my ($data) = @_;
  my @archs = parse_macho($data);
  my $a = $archs[0];
  my $end = 32 + $a->{sizeofcmds};
  my $first = length($data);
  for my $c (@{ $a->{cmds} }) {
    next unless ($c->{kind} // '') eq 'segment';
    for my $s (@{ $c->{sections} // [] }) {
      $first = $s->{offset} if $s->{offset} && $s->{offset} < $first;
    }
  }
  return $first - $end;
}

1;
