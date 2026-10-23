#!/usr/bin/env perl
# PwEevee rebrand regression tests: the Discord banner must stay out of the app's
# user-facing sources, the user-facing URLs must point at the PwEevee destinations,
# and the intentional upstream attribution / compatibility identifiers must NOT
# have been churned away by the rebrand.
#
#   perl PwEvevee/build-system/tests/pweevee-rebrand-tests.pl
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Find;

my $ROOT = dirname($0) . '/../../..';
my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }

sub slurp {
    my ($p) = @_;
    open(my $f, '<:raw', $p) or die "open $p: $!";
    local $/;
    my $d = <$f>;
    close $f;
    return $d;
}

my @SRC;
find({
    wanted   => sub {
        push @SRC, $File::Find::name
            if -f $_ && /\.(m|x|h)$/ && $File::Find::name !~ m{/vendor/};
    },
    no_chdir => 1,
}, "$ROOT/Spotipw/tweak/Sources");
ok(@SRC > 100, sprintf('live tweak sources enumerated under Spotipw/tweak/Sources (%d files)', scalar @SRC));

# ---------- 1. the Discord banner is gone from the app's user-facing sources ----------
my $discord_hits;
for my $file (@SRC) {
    my $code = slurp($file);
    # comments may talk about what was removed; string literals and identifiers may not
    my $live = '';
    for my $line (split /\r?\n/, $code) {
        next if $line =~ m{^\s*(//|/\*)};
        $live .= "$line\n";
    }
    for my $needle ('Join the Discord', 'Ask on Discord', 'SGDiscordURL', 'SGDiscordColor', 'discord.gg') {
        my $i = index($live, $needle);
        next if $i < 0;
        $discord_hits++;
        my $line = 1 + (substr($live, 0, $i) =~ tr/\n//);
        my $short = $file;
        $short =~ s{^\Q$ROOT\E/?}{};
        ok(0, "$short: no live '$needle' (line $line)");
    }
}
ok(!$discord_hits, 'no Discord row, URL or tint in the live tweak sources (banner removal holds)');

# ---------- 2. the rows and sections around the removed banner are intact ----------
{
    my $mod = slurp("$ROOT/Spotipw/tweak/Sources/App/ModSettings.x");
    ok(index($mod, 'SGSection(nil, @[SGDonateRow()])') >= 0, 'Mod Settings: the donate row keeps its section');
    ok(index($mod, '@"Spoof Premium"') >= 0, 'Mod Settings: the Spot.pw Spoof Premium row is preserved');
    ok($mod =~ /Eevee's Spoofed Premium/, 'Mod Settings: the Eevee premium label is preserved');

    my $about = slurp("$ROOT/Spotipw/tweak/Sources/App/About/AboutSettings.m");
    ok(index($about, '@"Website"') >= 0, 'About: the Website row is still there');
    ok(index($about, '@"GitHub"') >= 0, 'About: the GitHub row is still there');
    ok(index($about, '@"Licenses"') >= 0, 'About: the Licenses row is still there');

    my ($tour_stack) = slurp("$ROOT/Spotipw/tweak/Sources/App/Onboarding/Tour.m")
        =~ /initWithArrangedSubviews:@\[([^\]]*)\]/;
    ok(index(slurp("$ROOT/Spotipw/tweak/Sources/App/Onboarding/Tour.m"), '@"Report a bug"') >= 0,
       'Tour: the bug-report link survives the removed Discord link');
    ok(defined $tour_stack && $tour_stack !~ /Discord/, 'Tour: the links stack carries no Discord entry');
}

# ---------- 3. the user-facing link map ----------
{
    my %want = (
        SGSiteURL => 'https://pweevee.skytweak.dpdns.org/',
        SGRepoURL => 'https://github.com/codeboy2012/PwEevee',
    );
    for my $sym (sort keys %want) {
        my ($got) = slurp("$ROOT/Spotipw/tweak/Sources/Settings/SGPageStyle.m")
            =~ /NSString \*const \Q$sym\E = @"([^"]*)";/;
        ok(defined $got && $got eq $want{$sym}, "SGPageStyle.$sym = $want{$sym} (got " . ($got // 'absent') . ')');
    }

    my $update = slurp("$ROOT/Spotipw/tweak/Sources/App/About/Update.m");
    ok(index($update, 'repos/codeboy2012/PwEevee/releases') >= 0,
       'Update check: the GitHub releases endpoint is the PwEevee repo');
    ok(index($update, 'skopevoj') < 0, 'Update check: no upstream releases endpoint left in code');

    my $help = slurp("$ROOT/Spotipw/tweak/Sources/App/About/Signing.m");
    my ($anchor) = $help =~ /SGSigningHelpURL = @"[^#]*#([^"]*)"/;
    ok(defined $anchor, 'Signing help: an anchor is set');
    # GitHub turns the heading "### 3. Signing" into the anchor "3-signing"; such a heading must exist
    my $ok_heading = 0;
    for my $head (split /\r?\n/, slurp("$ROOT/README.md")) {
        next unless $head =~ /^#+\s*(.+)$/;
        (my $h = $1) =~ s/\.//g;   # GitHub anchors drop dots
        $h =~ s/\s+/-/g;
        $h = lc $h;                 # GitHub lowercases anchors
        if (defined $anchor && index($h, $anchor) == 0) { $ok_heading = 1; last; }
    }
    ok($ok_heading, "Signing help: '$anchor' resolves to a heading in the repo README");

    my $lrc = slurp("$ROOT/Spotipw/tweak/Sources/Shared/LyricsSources/LrcLib.m");
    ok(index($lrc, '@"PwEevee " @SG_VERSION') >= 0, 'LrcLib: the User-Agent names PwEevee');
    ok(index($lrc, 'github.com/codeboy2012/PwEevee') >= 0, 'LrcLib: the User-Agent cites the PwEevee repo');

    my $hook = slurp("$ROOT/Spotipw/tweak/Sources/Shared/LyricsSources/LyricsHook.x");
    ok(index($hook, 'kUnnamedProvider = @"PwEevee"') >= 0, 'Lyrics credit: the unnamed provider is PwEevee');

    my $donate = slurp("$ROOT/Spotipw/tweak/Sources/App/Donate/Donate.m");
    ok(index($donate, 'Support PwEevee') >= 0, 'Donate row: Support PwEevee');
    ok($donate =~ /Enjoying PwEevee\?/, 'Donate sheet: Enjoying PwEevee?');
}

# ---------- 4. upstream attribution and legal text survived the rebrand ----------
{
    ok(index(slurp("$ROOT/Spotipw/README.md"), 'skopevoj/spoti.pw') >= 0,
       'Spotipw/README.md still documents the upstream source');
    ok(index(slurp("$ROOT/Spotipw/CHANGELOG.md"), 'github.com/skopevoj/spoti.pw/commit/') >= 0,
       'Spotipw/CHANGELOG.md still cites upstream commit history');
    my $license = slurp("$ROOT/Spotipw/LICENSE");
    ok($license =~ /Vojt/, 'Spotipw/LICENSE keeps the required copyright notice');
    ok(index(slurp("$ROOT/Spotipw/CLA.md"), 'Vojt') >= 0, 'Spotipw/CLA.md keeps the upstream owner');
}

# ---------- 5. compatibility-critical internal identifiers were not churned ----------
{
    # on-device data paths: renaming these would orphan installed users' libraries
    my $fx = slurp("$ROOT/Spotipw/tweak/Sources/Shared/AudioEffects/AudioEffectsFiles.m");
    ok(index($fx, 'spoti.pw/JamesDSP') >= 0, 'audio effects: the legacy Documents/spoti.pw/JamesDSP path stays');
    ok(index($fx, 'spoti.pw/Audio effects') >= 0, 'audio effects: the legacy Documents/spoti.pw/Audio effects path stays');
    ok(index(slurp("$ROOT/Spotipw/tweak/Sources/Shared/LockScreenArtwork/SGArtworkFile.m"), 'spoti.pw/LockArtwork') >= 0,
       'lockscreen artwork: the legacy caches path stays');
    ok(index(slurp("$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/Premium.m"), 'spoti.pw/AdBlock') >= 0,
       'adblock: the legacy caches path stays');
    # the tweak's own dylib name is the injection contract
    ok(index(slurp("$ROOT/Spotipw/tweak/Makefile"), 'spotifyglass') >= 0,
       'the tweak binary keeps its spotifyglass identity');
}

if (@failures) {
    print "PWEEVEE REBRAND TESTS FAILED:\n";
    print "  - $_\n" for @failures;
    printf "%d passed, %d FAILED\n", $pass, scalar @failures;
    exit 1;
}
print "PWEEVEE REBRAND TESTS PASSED ($pass checks)\n";
exit 0;
