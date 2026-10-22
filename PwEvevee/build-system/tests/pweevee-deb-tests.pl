#!/usr/bin/env perl
# PwEevee unified-deb validation: structure, control, contents, determinism, and the boundaries that
# keep the package from drifting (no IPA inside, no sources, no duplicates, Spotify 9.1.76 metadata).
#
#   perl PwEvevee/build-system/tests/pweevee-deb-tests.pl <out.deb>
#   perl PwEvevee/build-system/tests/pweevee-deb-tests.pl            # structural checks only
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my ($deb) = @ARGV;
my $ROOT = dirname($0) . '/../../..';
my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }
sub slurp { local $/; open my $f, '<', $_[0] or return undef; return <$f>; }

my $AR = "$ROOT/Spotipw/scripts/ar-extract.pl";
ok(-f $AR, 'ar-extract.pl is present');

# ---------------- helpers ----------------
sub ar_member {
    my ($archive, $member) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $out = "$dir/$member";
    system("perl", $AR, $archive, $member, $out) == 0 or return undef;
    return $out;
}

sub tar_members {
    my ($archive, $member, @paths) = @_;
    my $dir = tempdir(CLEANUP => 1);
    my $lzma = "$dir/data.tar.lzma";
    system("perl", $AR, $archive, $member, $lzma) == 0 or return undef;
    my $tar = "$dir/data.tar";
    system("xz -dc --format=lzma $lzma > $tar") == 0 or return undef;
    if (@paths) {
        my $x = "$dir/x";
        make_path($x);
        system("tar", "xf", $tar, "-C", $x, @paths) == 0 or return undef;
        return $x;
    }
    my @list = map { s/\r$//; $_ } grep { chomp; $_ } split /\n/, `tar tf $tar`;
    return \@list;
}

# ---------------- 1. ar structure (the layout deb-format-test.pl pins, with PwEevee's members) ---
if ($deb) {
    my $bin = ar_member($deb, 'debian-binary');
    ok($bin && slurp($bin) eq "2.0\n", 'debian-binary member reads 2.0');
    for my $member ('control.tar.gz', 'data.tar.lzma') {
        my $m = ar_member($deb, $member);
        ok($m && -s $m > 0, "$member member is present and non-empty");
    }

    # ---------------- 2. control ----------------
    my $cdir = tempdir(CLEANUP => 1);
    my $ctar = ar_member($deb, 'control.tar.gz');
    system("tar xzf $ctar -C $cdir") == 0 or ok(0, 'control.tar.gz extracts');
    my $control = slurp("$cdir/control") // '';
    ok($control =~ /^Package: com\.pweevee\.unified$/m, 'control: Package is com.pweevee.unified');
    ok($control =~ /^Version: 0\.22\.0-alpha\.2$/m, 'control: Version is 0.22.0-alpha.2');
    ok($control =~ /^Architecture: iphoneos-arm$/m, 'control: Architecture is iphoneos-arm');
    ok($control =~ /^Depends: firmware \(>= 15\.0\), mobilesubstrate$/m, 'control: Depends declares firmware + mobilesubstrate');
    ok($control =~ /Spotify 9\.1\.76/, 'control: description names Spotify 9.1.76');
    ok($control !~ /9\.1\.84/, 'control: no claim of 9.1.84 support');
    ok($control =~ /^Installed-Size: \d+$/m, 'control: Installed-Size present');
    ok($control =~ /^Maintainer:/m && $control =~ /^Section: Tweaks$/m, 'control: Maintainer and Section present');

    # ---------------- 3. data contents ----------------
    my $list = tar_members($deb, 'data.tar.lzma');
    unless ($list) { ok(0, 'data.tar.lzma extracts'); exit report(); }
    my %has = map { $_ => 1 } @$list;
    ok($has{'var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib'}, 'data: the unified dylib is installed under MobileSubstrate/DynamicLibraries');
    ok($has{'var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist'}, 'data: the MobileSubstrate filter is beside the dylib');
    ok($has{'var/jb/Library/Application Support/EeveeSpotify.bundle/Info.plist'}, 'data: EeveeSpotify.bundle ships where BundleHelper looks first');
    ok($has{'var/jb/Library/Application Support/EeveeSpotify.bundle/en.lproj/Localizable.strings'}, 'data: the English strings ship');
    ok($has{'var/jb/Library/Application Support/EeveeSpotify.bundle/resolveconfiguration.bnk'}, 'data: resolveconfiguration.bnk ships');
    my $icons = grep { m{^var/jb/share/} } @$list;
    ok($icons == 0, "data: no var/jb/share dead paths (icon PNGs ride the host IPA; found $icons)");
    my $pngs = join("\n", grep { m{\.png$} && !m{EeveeSpotify\.bundle/} } @$list);
    ok($pngs eq '', 'data: no icon PNGs outside EeveeSpotify.bundle (setAlternateIconName reads them from the app root; they ride the host IPA)' . ($pngs eq '' ? '' : " — $pngs"));
    ok(!(grep { /EeveeSpotify\.dylib$/ } @$list), 'data: no second EeveeSpotify dylib inside the deb (it lives in the host IPA)');
    ok(!(grep { /CydiaSubstrate\.framework/ } @$list), 'data: no CydiaSubstrate copy (the IPA route provides it)');
    ok(!(grep { /Orion\.framework/ } @$list), 'data: no Orion copy (the IPA route provides it)');
    ok(!(grep { /EeveeSwiftProtobuf/ } @$list), 'data: no EeveeSwiftProtobuf copy (the IPA route provides it)');

    # ---------------- 4. nothing that must not ship ----------------
    my $bad = grep { m{\.ipa$|\.h$|\.swift$|\.m$|\.pl$|\.py$|SGFlagList|_work/|\.freebuff|\.git/|\.p12|\.mobileprovision|id_rsa} } @$list;
    ok($bad == 0, "data: no IPAs, sources, workspace files, keys or certificates ($bad found)");
    ok(!(grep { m{^Payload/} } @$list), 'data: no Spotify.app payload inside the deb');
    ok(!(grep { m{dist/|out/} } @$list), 'data: no build-output directories inside the deb');

    # ---------------- 5. the dylib inside the package ----------------
    my $x = tar_members($deb, 'data.tar.lzma',
        'var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib',
        'var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist');
    if ($x) {
        my $dylib = "$x/var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.dylib";
        my $filter = "$x/var/jb/Library/MobileSubstrate/DynamicLibraries/spotifyglass.plist";
        ok(-s $dylib > 1000000, 'dylib: a real unified binary (over 1 MB)');
        # Mach-O: thin arm64, dylib file type 6
        open my $f, '<', $dylib or die;
        binmode $f; local $/; my $d = <$f>; close $f;
        my ($magic, $cputype, undef, $filetype) = unpack('VVVV', substr($d, 0, 16));
        ok($magic == 0xfeedfacf, 'dylib: Mach-O 64-bit magic');
        ok($cputype == 0x0100000c, 'dylib: arm64 (cputype 0x0100000c)');
        ok($filetype == 6, 'dylib: MH_DYLIB file type');
        ok(index($d, 'SGEeveeSpotifyPage') >= 0, 'dylib: carries the PwEevee settings integration (SGEeveeSpotifyPage)');
        ok(index($d, 'spotifyglass.eevee.') >= 0, 'dylib: carries the Eevee mirror-key storage');
        ok(index($d, 'EeveeSelectedAppIconName') >= 0, 'dylib: carries the app-icon picker integration');
        ok(index($d, 'Mod Settings') >= 0, 'dylib: is the SpoTi.pw Mod Settings build');
        ok(index($d, 'Redesigned') >= 0, 'dylib: carries the redesign (SpoTi.pw v0.22.0 features intact)');
        # filter
        open my $g, '<', $filter or die; binmode $g; local $/; my $p = <$g>; close $g;
        ok(index($p, 'com.spotify.client') >= 0, 'filter: targets com.spotify.client');
    } else {
        ok(0, 'dylib extraction from package');
    }

    # ---------------- 6. Spotify 9.1.76 compatibility metadata ----------------
    my $report = $deb;
    $report =~ s/\.deb$/.build-report.txt/;
    if (-f $report) {
        my $r = slurp($report);
        ok($r && $r =~ /9\.1\.76/, 'build report: names Spotify 9.1.76');
        ok($r && $r =~ /sha256 [0-9a-f]{64}/, 'build report: carries the package sha256');
    }
}

# ---------------- 7. sources on disk agree with what the package must contain ----------------
{
    my $mod = slurp("$ROOT/Spotipw/tweak/Sources/App/ModSettings.x");
    ok($mod && index($mod, 'SGEeveeSpotifyPage') >= 0, 'sources: ModSettings wires the EeveeSpotify page');
    ok($mod && index($mod, 'SGEeveeRemoveStandaloneRow') >= 0, 'sources: the standalone row stays filtered');
    my $eevee = slurp("$ROOT/Spotipw/tweak/Sources/App/Eevee/SGEevee.x");
    ok($eevee && index($eevee, 'removeObjectForKey:kLyricsSource') >= 0, 'sources: the forced lyrics off-switch is undone at launch');
    ok($eevee && index($eevee, 'EeveeLyricsSettingsView') < 0, 'sources: the removed Eevee lyrics UI stays removed');
    my $control = slurp("$ROOT/Spotipw/tweak/pweevee-control");
    ok($control && $control =~ /0\.22\.0-alpha\.2/, 'sources: pweevee-control carries the release version');
}

# ---------------- report ----------------
sub report {
    print "pweevee-deb-tests: $pass passed, " . scalar(@failures) . " failed\n";
    if (@failures) {
        print "  _\n";
        print "  FAIL: $_\n" for @failures;
        exit 1;
    }
    exit 0;
}
report();
