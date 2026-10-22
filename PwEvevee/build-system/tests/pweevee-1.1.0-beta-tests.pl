#!/usr/bin/env perl
# ============================================================
# pweevee-1.1.0-beta-tests.pl — structural tests for the
# unified PwEevee 1.1.0-beta deb (SpoTi.pw/Chroma 0.50.0 +
# EeveeSpotify 7.0.0, target Spotify 9.1.78).
#
#   perl PwEvevee/build-system/tests/pweevee-1.1.0-beta-tests.pl [path/to/deb]
#
# Default deb path: dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb
# (relative to repo root). Pure perl + tar/xz; Mach-O and
# binary-plist checks are magic-byte sniffs. No Theos required.
# ============================================================
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $repo = abs_path(dirname(abs_path(__FILE__)) . '/../../..');
my $deb  = shift @ARGV || "$repo/dist/PwEevee_1.1.0-beta_iphoneos-arm64.deb";

my ($pass, $fail) = (0, 0);
sub ok  { my $n = defined $_[0] ? $_[0] : '<unnamed>'; $pass++; printf "  ok  %s\n", $n; }
sub nok { my $n = defined $_[0] ? $_[0] : '<unnamed>'; $fail++; printf "  FAIL %s%s\n", $n, defined $_[1] ? " -- $_[1]" : ''; }
sub check { my ($cond, $name, $why) = @_; $cond ? ok($name) : nok($name, $why); }

-f $deb or die "no such deb: $deb\n";

my $tmp     = tempdir(CLEANUP => 1);
my $extract = "$repo/Spotipw/scripts/ar-extract.pl";

# ---- 1. ar structure (parse headers directly) ----
my $all = do { open my $fh, '<:raw', $deb or die "cannot read $deb: $!"; local $/; <$fh> };
check(substr($all, 0, 8) eq "!<arch>\n", 'ar magic "!<arch>"');

my @hdrs;
{
  my $off = 8;
  while ($off + 60 <= length($all)) {
    my $hdr = substr($all, $off, 60);
    my ($name) = $hdr =~ /^(\S+)\/\s/;
    last unless defined $name;
    # GNU ar header: name(16) date(12) uid(6) gid(6) mode(8) size(10) `\n
    my ($size) = substr($hdr, 48, 10) =~ /^(\d+)\s*$/;
    last unless defined $size;
    push @hdrs, [$name, $off + 60, $size + 0];
    $off += 60 + $size + ($size % 2);
  }
}
check(scalar(@hdrs) == 3, 'exactly 3 ar members', scalar(@hdrs) . ' found');
my ($m_dbb, $m_ctl, $m_dat) = @hdrs;
check($m_dbb && $m_dbb->[0] eq 'debian-binary', 'member 1: debian-binary');
check($m_ctl && $m_ctl->[0] eq 'control.tar.gz', 'member 2: control.tar.gz');
check($m_dat && $m_dat->[0] eq 'data.tar.lzma',  'member 3: data.tar.lzma');
check($m_dbb && $m_dbb->[2] == 4 && substr($all, $m_dbb->[1], 2) eq "2.", 'debian-binary says 2.0');
check($m_ctl && substr($all, $m_ctl->[1], 2) eq "\x1f\x8b", 'control.tar.gz is gzip');
# deb's data.tar.lzma is LZMA-alone (xz --format=lzma): magic 5D 00 00
check($m_dat && substr($all, $m_dat->[1], 3) eq "\x5d\x00\x00", 'data.tar.lzma is LZMA-alone stream');

# ---- 2. extract and inspect ----
my $rc;
$rc = system('perl', $extract, $deb, 'control.tar.gz', "$tmp/ctl.tgz");
check($rc == 0, 'control.tar.gz extracts');
$rc = system('perl', $extract, $deb, 'data.tar.lzma', "$tmp/dat.lzma");
check($rc == 0, 'data.tar.lzma extracts');
mkdir "$tmp/c"; mkdir "$tmp/x";
$rc = system('tar', '-xzf', "$tmp/ctl.tgz", '-C', "$tmp/c")
    + system('tar', '-xJf', "$tmp/dat.lzma", '-C', "$tmp/x");
check($rc == 0, 'tar unpack of both members');

my $control = '';
if (open my $cf, '<', "$tmp/c/control") { local $/; $control = <$cf>; close $cf; }
check($control =~ /^Package: com\.pweevee\.unified$/m, 'control: package id');
check($control =~ /^Version: 1\.1\.0-beta$/m, 'control: version 1.1.0-beta');
check($control =~ /^Architecture: iphoneos-arm64$/m, 'control: arm64 architecture');
check($control =~ /^Depends: firmware \(>= 16\.1\), mobilesubstrate$/m, 'control: Depends firmware>=16.1 + mobilesubstrate');
check($control =~ /^Conflicts:.*com\.eevee\.spotify/m && $control =~ /^Conflicts:.*com\.spotipw/m
      && $control =~ /^Conflicts:.*dev\.theos\.orion/m, 'control: conflicts upstream packages + orion');
check($control =~ /^Provides:.*dev\.theos\.orion/m, 'control: provides dev.theos.orion');
check($control !~ /^Depends:.*dev\.theos\.orion/m, 'control: does NOT depend on external orion (bundled)');

# ---- 3. payload inventory ----
my @files;
if (opendir my $dh, "$tmp/x") {
  my @stack = ('');
  while (defined(my $rel = shift @stack)) {
    opendir my $d, "$tmp/x/$rel" or next;
    for my $e (sort readdir $d) {
      next if $e eq '.' || $e eq '..';
      my $p = $rel eq '' ? $e : "$rel/$e";
      if (-d "$tmp/x/$p") { push @stack, $p; } else { push @files, $p; }
    }
  }
}
my %f = map { $_ => 1 } @files;
check(scalar(@files) > 0, "payload listed (" . scalar(@files) . " files)");

for my $req (
  'var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib',
  'var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist',
  'var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib',
  'var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.plist',
  'var/jb/Library/MobileSubstrate/DynamicLibraries/KaraokeBackgroundShader.metallib',
  'var/jb/Library/Frameworks/Orion.framework/Orion',
  'var/jb/Library/Frameworks/Orion.framework/Info.plist',
  'var/jb/Library/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf',
  'var/jb/Library/Frameworks/EeveeSwiftProtobuf.framework/Info.plist',
  'var/jb/Library/Application Support/EeveeSpotify.bundle/Info.plist',
) { check($f{$req}, "payload present: $req"); }

# ---- 4. duplicates forbidden ----
check((grep { /EeveeSpotify\.dylib$/ } @files) == 1, 'exactly one EeveeSpotify.dylib');
check((grep { /spotifyglass\.dylib$/ } @files) == 1, 'exactly one spotifyglass.dylib');
check((grep { /\/Orion$/ } @files) == 1, 'exactly one Orion binary');
check((grep { /EeveeSwiftProtobuf\.framework\/EeveeSwiftProtobuf$/ } @files) == 1, 'exactly one EeveeSwiftProtobuf binary');
check((grep { m{EeveeSpotify\.bundle/Info\.plist$} } @files) == 1, 'exactly one EeveeSpotify.bundle');

# ---- 5. nothing that must not ship ----
check(!(grep { /CydiaSubstrate/ } @files), 'no CydiaSubstrate copy');
check(!(grep { /\.ipa$/ || /(^|\/)Payload(\/|$)/ } @files), 'no IPA/Payload leftovers');
check(!(grep { /(^|\/)(\.git|_work|Sources|Headers)(\/|$)/ } @files), 'no build workspace/sources');
check(!(grep { /\.p12$/ || /\.mobileprovision$/ || /entitlements/ } @files), 'no signing credentials');
check(!(grep { m{var/jb/share/pweevee/icons} } @files), 'no dead icons path (var/jb/share/pweevee/icons)');

# ---- 6. filters target only com.spotify.client ----
for my $pl ('var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist',
            'var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.plist') {
  if (open my $p, '<:raw', "$tmp/x/$pl") {
    local $/; my $d = <$p>; close $p;
    check(index($d, 'bplist00') == 0, "$pl: binary plist");
    check(index($d, 'com.spotify.client') >= 0, "$pl: targets com.spotify.client");
    check(index($d, 'SpringBoard') < 0, "$pl: no out-of-scope bundles");
  } else { nok("read $pl"); }
}

# ---- 7. Mach-O sanity: thin arm64 (cputype 0x0100000C LE => 0C 00 00 01) ----
for my $macho ('var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib',
               'var/jb/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib',
               'var/jb/Library/Frameworks/Orion.framework/Orion') {
  if (open my $m, '<:raw', "$tmp/x/$macho") {
    read($m, my $hdr, 8); close $m;
    my $is_arm64 = $hdr =~ /^\xcf\xfa\xed\xfe\x0c\x00\x00\x01/;
    check($is_arm64, "$macho: thin arm64 Mach-O", unpack 'H16', $hdr);
  } else { nok("read $macho"); }
}
# EeveeSwiftProtobuf ships as a fat (cafebabe) binary in the upstream deb — accept either.
{
  my $macho = 'var/jb/Library/Frameworks/EeveeSwiftProtobuf.framework/EeveeSwiftProtobuf';
  if (open my $m, '<:raw', "$tmp/x/$macho") {
    read($m, my $hdr, 8); close $m;
    my $ok_macho = $hdr =~ /^\xcf\xfa\xed\xfe/ || $hdr =~ /^\xca\xfe\xba\xbe/;
    check($ok_macho, "$macho: Mach-O (thin arm64 or fat)", unpack 'H16', $hdr);
  } else { nok("read $macho"); }
}

# ---- 8. Orion placement resolves Eevee's LC_RPATH /var/jb/Library/Frameworks ----
check($f{'var/jb/Library/Frameworks/Orion.framework/Orion'},
      'Orion at var/jb/Library/Frameworks (covers EeveeSpotify rpath /var/jb/Library/Frameworks)');

# ---- 9. size sanity ----
my $size = -s $deb;
check($size > 1_000_000 && $size < 20_000_000, "deb size plausible ($size bytes)");

print "\n", ($fail ? "PwEEVEE 1.1.0-BETA TESTS FAILED ($fail of " . ($pass + $fail) . " checks failed)\n"
                   : "PwEEVEE 1.1.0-BETA TESTS PASSED ($pass checks)\n");
exit($fail ? 1 : 0);
