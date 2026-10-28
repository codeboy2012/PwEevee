#!/usr/bin/env perl
# ============================================================================
# release-artifact-tests.pl — the PwEevee download-selection contract
# ============================================================================
#
#   perl PwEvevee/build-system/tests/release-artifact-tests.pl
#
# The 3.1.0 regression: a release carried both the clean decrypted Spotify base
# and the PwEevee IPA, every consumer took the first ".ipa" alphabetically, and
# the README + website linked `com.spotify.client_9.1.90_und3fined.ipa`.
#
# These checks are deterministic and offline:
#   1. PwArtifact filename validation (accept/reject, whole-name, channels)
#   2. channel-specific selection, version pinning, multiple assets, bad URLs
#   3. the README generator, driven from a local fixture
#   4. the renderer, run against a throw-away site tree, renders the same asset
#   5. the browser safety net derives the canonical name instead of assets[0]
#   6. no release version is hardcoded in the selection path
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin ();
use lib "$FindBin::Bin/../release/lib";
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use JSON::PP;
use PwArtifact qw(parse_artifact is_canonical release_channel pick_artifact expected_name);

binmode STDOUT, ':encoding(UTF-8)';

my $ROOT = dirname($0) . '/../../..';
$ROOT =~ s{/+$}{};
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";
my $TMP = "$ROOT/PwEvevee/build-system/_work/release-artifact-fixtures";
remove_tree($TMP) if -d $TMP;
make_path($TMP);

my (@failures, $pass);
$pass = 0;
sub ok($;$$) {
    if (@_ == 1) {
        push @failures, 'MALFORMED CHECK: ' . (defined $_[0] ? $_[0] : 'undef');
        return 0;
    }
    my ($cond, $what, $detail) = @_;
    if ($cond) { $pass++; return 1 }
    push @failures, $what . (defined $detail && length $detail ? "  ($detail)" : '');
    return 0;
}
sub section { print "\n$_[0]\n" }
sub slurp { my ($p) = @_; open(my $f, '<:raw', $p) or return undef; local $/; my $d = <$f>; close $f; return $d }
sub spew  { my ($p, $d) = @_; make_path(dirname($p)); open(my $f, '>:raw', $p) or die "write $p: $!\n"; print {$f} $d; close $f }
sub read_json  { my $d = slurp($_[0]); return undef unless defined $d; return eval { JSON::PP->new->utf8->decode($d) } }
sub write_json { spew($_[0], JSON::PP->new->utf8->canonical->pretty->encode($_[1])) }
sub copy_tree {
    my ($from, $to) = @_;
    make_path($to);
    opendir(my $d, $from) or die "read $from: $!\n";
    for my $e (sort grep { $_ ne '.' && $_ ne '..' } readdir $d) {
        my ($s, $t) = ("$from/$e", "$to/$e");
        if (-d $s) { copy_tree($s, $t) }
        else { copy($s, $t) or die "copy $s -> $t: $!\n" }
    }
    closedir $d;
}

# ================================================== 1. filename validation
section('1. canonical PwEevee artifact names');

my @accepted = (
    [ 'PwEevee-3.1.0.ipa',         'stable 3.1.0' ],
    [ 'PwEevee-3.1.5.ipa',         'stable 3.1.5' ],
    [ 'PwEevee-3.2.0-nightly.ipa', 'nightly' ],
    [ 'PwEevee-3.1.5-alpha.ipa',   'alpha' ],
    [ 'pweevee-3.1.5.IPA',         'case-insensitive whole name' ],
);
for my $c (@accepted) {
    my ($name, $what) = @$c;
    ok(is_canonical($name), "accepts $what ($name)");
}

my @rejected = (
    'com.spotify.client_9.1.90_und3fined.ipa',
    'Spotify-9.1.90.ipa',
    'PwEevee-3.1.0-stable.ipa',
    'PwEevee-3.1.0-debug.ipa',
    'PwEevee-3.1.0-beta.ipa',
    'PwEevee-3.1.0.zip',
    'OtherProject-3.1.0.ipa',
    'PwEevee-3.1.ipa',
    'PwEevee-3.1.0.0.ipa',
    'PwEevee-3.1.0.ipa.part',
    'PwEevee-3.1.0.ipa ',
    'xPwEevee-3.1.0.ipa',
    '../PwEevee-3.1.0.ipa',
    'dir/PwEevee-3.1.0.ipa',
    'PwEevee-3.1.0-nightly.ipa.extra',
    '',
);
for my $name (@rejected) {
    ok(!is_canonical($name), 'rejects ' . (length $name ? $name : '(empty name)'));
}

{
    my $p = parse_artifact('PwEevee-3.1.5-NIGHTLY.ipa');
    ok($p->{ok} && $p->{channel} eq 'nightly' && $p->{version} eq '3.1.5',
       'parse reports the channel and version of an accepted name');
    ok($p->{name} eq 'PwEevee-3.1.5-NIGHTLY.ipa',
       'parse preserves the canonical filename GitHub reported');
}

# ==================================================== 2. channel + selection
section('2. channel classification and deterministic selection');

ok(release_channel('3.1.5', 0) eq 'stable', 'a plain numeric tag is stable');
ok(release_channel('v3.1.5', 0) eq 'stable', 'a v-prefixed tag is stable');
ok(release_channel('v3.1.5-nightly', 0) eq 'nightly', 'a -nightly tag is nightly');
ok(release_channel('v3.1.5-alpha.2', 0) eq 'alpha', 'a -alpha tag is alpha');
ok(release_channel('v3.1.5-beta', 0) eq 'prerelease', 'a -beta tag is never stable');
ok(release_channel('v3.1.5', 1) eq 'prerelease', 'the prerelease flag alone is never stable');

my $spotify = {
    name => 'com.spotify.client_9.1.90_und3fined.ipa',
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/com.spotify.client_9.1.90_und3fined.ipa',
};
my $stable = {
    name => 'PwEevee-3.1.5.ipa',
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/PwEevee-3.1.5.ipa',
};
my $nightly = {
    name => 'PwEevee-3.1.5-nightly.ipa',
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/PwEevee-3.1.5-nightly.ipa',
};
my $old_stable = {
    name => 'PwEevee-3.1.0.ipa',
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.0/PwEevee-3.1.0.ipa',
};

my $picked = pick_artifact([ $spotify, $stable ], 'stable', '3.1.5');
ok($picked && $picked->{name} eq 'PwEevee-3.1.5.ipa',
   'stable selection ignores the Spotify base that sorts first');

$picked = pick_artifact([ $spotify, $nightly ], 'stable', '3.1.5');
ok(!defined $picked, 'stable selection never takes a nightly asset');

$picked = pick_artifact([ $stable, $nightly, $spotify ], 'nightly', '3.1.5');
ok($picked && $picked->{name} eq 'PwEevee-3.1.5-nightly.ipa',
   'nightly selection takes only the nightly asset');

$picked = pick_artifact([ $stable, $spotify ], 'alpha', '3.1.5');
ok(!defined $picked, 'alpha selection never falls back to stable');

$picked = pick_artifact([ $spotify ], 'stable', '3.1.5');
ok(!defined $picked, 'a release with only the Spotify base has no PwEevee download');

$picked = pick_artifact([ $old_stable, $stable ], 'stable');
ok($picked && $picked->{name} eq 'PwEevee-3.1.5.ipa',
   'multiple stable assets resolve to the newest version deterministically');

$picked = pick_artifact([ $old_stable, $stable ], 'stable', '3.1.0');
ok($picked && $picked->{name} eq 'PwEevee-3.1.0.ipa',
   'a pinned release version never downloads a different version');

$picked = pick_artifact([ $old_stable ], 'stable', '3.1.5');
ok(!defined $picked, 'a canonical name for the wrong version is missing, not substituted');

my $insecure = { name => 'PwEevee-3.1.5.ipa', download_url => 'http://example.com/PwEevee-3.1.5.ipa' };
ok(!defined pick_artifact([ $insecure ], 'stable', '3.1.5'),
   'a non-https asset URL is never offered');

my $browser_only = { name => 'PwEevee-3.1.5.ipa',
                     browser_download_url => 'https://github.com/x/y/releases/download/3.1.5/PwEevee-3.1.5.ipa' };
$picked = pick_artifact([ $browser_only ], 'stable', '3.1.5');
ok($picked && $picked->{browser_download_url} =~ m{/PwEevee-3\.1\.5\.ipa$},
   'the URL comes from the actual release asset, not a constructed filename');

ok(expected_name('3.1.5', 'stable') eq 'PwEevee-3.1.5.ipa', 'expected stable name has no suffix');
ok(expected_name('3.1.5', 'nightly') eq 'PwEevee-3.1.5-nightly.ipa', 'expected nightly name');
ok(!defined expected_name('v3.1.5', 'stable'), 'a v-prefixed version is not a filename version');

# ======================================================== 3. README generator
section('3. README release block (offline fixture)');

sub readme_fixture {
    my ($name, @assets) = @_;
    my $rel = {
        name => 'PwEevee v3.1.5',
        tag_name => '3.1.5',
        html_url => 'https://github.com/codeboy2012/PwEevee/releases/tag/3.1.5',
        published_at => '2026-10-28T10:00:00Z',
        body => 'Notes.',
        prerelease => JSON::PP::false,
        assets => [ @assets ],
    };
    my $file = "$TMP/$name.json";
    write_json($file, { releases => [ $rel ] });
    return $file;
}
sub run_readme {
    my ($fixture, $tag) = @_;
    my $dir = "$TMP/readme-$tag";
    make_path($dir);
    my $readme = "$dir/README.md";
    spew($readme, "# PwEevee\n\n<!-- releases:begin -->\nstale\n<!-- releases:end -->\n\nManual tail stays.\n");
    my $out = qx{perl PwEvevee/build-system/release/update-readme.pl --offline --data "$fixture" --readme "$readme" 2>&1};
    my $exit = $? >> 8;
    return ($exit, $out, slurp($readme) // '');
}

my $canonical_asset = {
    name => 'PwEevee-3.1.5.ipa', size => 146953045,
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/PwEevee-3.1.5.ipa',
};
my $spotify_asset = {
    name => 'com.spotify.client_9.1.90_und3fined.ipa', size => 153481523,
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/com.spotify.client_9.1.90_und3fined.ipa',
};

{
    my ($exit, $out, $readme) = run_readme(
        readme_fixture('readme-ok', $spotify_asset, $canonical_asset), 'ok');
    ok($exit == 0, 'the README updater accepts a release with a canonical asset', "exit $exit");
    ok($readme =~ /\*\*Download:\*\* \[PwEevee-3\.1\.5\.ipa\]\(https:\/\/github\.com\/codeboy2012\/PwEevee\/releases\/download\/3\.1\.5\/PwEevee-3\.1\.5\.ipa\)/,
       'the README links the canonical PwEevee asset');
    ok($readme !~ /\[com\.spotify\.client_9\.1\.90_und3fined\.ipa\]/,
       'the README never links the Spotify base IPA');
    ok($readme =~ /Manual tail stays\./, 'manual README content outside the block is untouched');
}

{
    my (undef, undef, $readme) = run_readme(
        readme_fixture('readme-spotify-only', $spotify_asset), 'spotify');
    ok($readme !~ /\[com\.spotify\.client_9\.1\.90_und3fined\.ipa\]/,
       'a release with only the Spotify base produces no download link');
    ok($readme =~ /missing its `PwEevee-3\.1\.5\.ipa` asset/,
       'the README says the expected artifact is missing');
}

{
    my $stable_suffix = { %$canonical_asset, name => 'PwEevee-3.1.5-stable.ipa' };
    my (undef, undef, $readme) = run_readme(
        readme_fixture('readme-stable-suffix', $spotify_asset, $stable_suffix), 'suffix');
    ok($readme !~ /\[PwEevee-3\.1\.5-stable\.ipa\]/,
       'a -stable filename suffix is not accepted as stable');
    ok($readme =~ /missing its `PwEevee-3\.1\.5\.ipa` asset/,
       'the -stable suffix is reported as a missing artifact');
}

# ============================================================ 4. renderer
section('4. rendered homepage uses the same validated asset');

my $SITE = "$TMP/site";
copy_tree('website-src', "$SITE/website-src");
make_path("$SITE/website/data");
copy('website/data/projects.json', "$SITE/website/data/projects.json")
    or die "copy projects.json: $!\n";

my $latest_base = {
    version => '3.1.5', version_label => 'v3.1.5', channel => 'stable',
    name => 'PwEevee v3.1.5',
    published_at => '2026-10-28T10:00:00Z',
    published_label => '28 October 2026',
    published_epoch => 1793181600,
    url => 'https://github.com/codeboy2012/PwEevee/releases/tag/3.1.5',
    prerelease => JSON::PP::false,
    notes => 'Notes.',
    summary => 'Notes.',
    author => 'codeboy2012',
    asset_count => 2,
    artifact_missing => JSON::PP::false,
};
sub site_data {
    my ($name, $assets, $extra) = @_;
    my $latest = { %$latest_base, assets => $assets, %{ $extra || {} } };
    write_json("$SITE/website/data/releases.json", {
        schema => 1, generated_at => '2026-10-28T10:05:00Z',
        projects => [ {
            slug => 'pweevee', name => 'PwEevee', repo => 'codeboy2012/PwEevee',
            repo_url => 'https://github.com/codeboy2012/PwEevee',
            issues_url => 'https://github.com/codeboy2012/PwEevee/issues',
            releases_url => 'https://github.com/codeboy2012/PwEevee/releases',
            available => JSON::PP::true, stale => JSON::PP::false,
            latest => $latest, history => [],
        } ],
    });
    local $ENV{PWEEVEE_ROOT} = $SITE;
    my $out = qx{perl PwEvevee/build-system/release/render-site.pl --quiet 2>&1};
    my $exit = $? >> 8;
    my $html = slurp("$SITE/website/index.html") // '';
    return ($exit, $out, $html);
}

my %canonical_json = (
    name => 'PwEevee-3.1.5.ipa', size => 146953045,
    size_label => '140 MB',
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/PwEevee-3.1.5.ipa',
    kind => 'ipa', sha256 => 'cd' x 32, download_count => 3,
    pweevee_artifact => JSON::PP::true,
    artifact_channel => 'stable', artifact_version => '3.1.5',
);
my %spotify_json = (
    name => 'com.spotify.client_9.1.90_und3fined.ipa', size => 153481523,
    size_label => '146 MB',
    download_url => 'https://github.com/codeboy2012/PwEevee/releases/download/3.1.5/com.spotify.client_9.1.90_und3fined.ipa',
    kind => 'ipa', download_count => 9,
    pweevee_artifact => JSON::PP::false,
);

{
    my ($exit, $out, $html) = site_data(
        'ok', [ { %spotify_json }, { %canonical_json } ],
        { download_asset => { %canonical_json } });
    ok($exit == 0, 'the renderer builds a site from the validated release data', "exit $exit: $out");
    ok($html =~ m{class="btn btn--primary[^"]*"\s+href="[^"]*3\.1\.5/PwEevee-3\.1\.5\.ipa"}s,
       'the rendered homepage primary download is the canonical PwEevee IPA');
    ok($html !~ m{class="btn btn--primary[^"]*"\s+href="[^"]*com\.spotify\.client_}s,
       'the rendered homepage never offers the Spotify base as the download');
}

{
    # A pre-fix snapshot has no download_asset. The renderer still has to
    # derive the canonical name from the assets rather than take assets[0].
    my ($exit, undef, $html) = site_data(
        'legacy', [ { %spotify_json }, { %canonical_json } ]);
    ok($exit == 0, 'the renderer accepts a legacy snapshot without download_asset');
    ok($html =~ m{class="btn btn--primary[^"]*"\s+href="[^"]*3\.1\.5/PwEevee-3\.1\.5\.ipa"}s,
       'legacy cached data resolves to the canonical asset, not the first .ipa');
    ok($html !~ m{class="btn btn--primary[^"]*"\s+href="[^"]*com\.spotify\.client_}s,
       'legacy cached data cannot resurrect the Spotify base download');
}

{
    my ($exit, undef, $html) = site_data(
        'missing', [ { %spotify_json } ],
        { download_asset => undef, artifact_missing => JSON::PP::true });
    ok($exit == 0, 'a release missing its artifact still renders');
    ok($html !~ m{class="btn btn--primary[^"]*"\s+href="[^"]*com\.spotify\.client_}s,
       'a missing artifact is not replaced by the Spotify base download');
    ok(index($html, 'does not carry its expected PwEevee-3.1.5.ipa asset') >= 0,
       'the page names the artifact that the release is missing');
}

# ==================================================== 5. browser safety net
section('5. browser-side selection');

my $js = slurp('website-src/assets/pweevee.js') // '';
ok($js =~ /function primaryAsset\(entry, r, assets\)/,
   'the hydration card routes through one selection helper');
ok($js =~ /r\.download_asset && safeUrl\(r\.download_asset\.download_url\)/,
   'the helper prefers the validated download_asset from generated data');
ok($js =~ /function canonicalName\(r\)/,
   'the helper can re-derive the canonical filename');
ok($js =~ /PwEevee-' \+ version \+ \(channel \? '-' \+ channel : ''\) \+ '\.ipa'/,
   'the derived name follows PwEevee-X.Y.Z[-nightly|-alpha].ipa');
ok($js =~ /function hasArtifact\(rel\)/,
   'the per-visit recheck verifies a canonical asset before changing a card version');
ok($js !~ /var primary = assets\[0\];/,
   'no card unconditionally takes the first asset as the download');

# ========================================================= 6. no hardcoding
section('6. no release version in the selection path');

for my $file (qw(
    PwEvevee/build-system/release/lib/PwArtifact.pm
    PwEvevee/build-system/release/update-releases.pl
    PwEvevee/build-system/release/update-readme.pl
    PwEvevee/build-system/release/render-site.pl
    PwEvevee/build-system/release/update-appsource.pl
)) {
    my $src = slurp($file) // '';
    my $code = join("\n", grep { !/^\s*#/ } split /\n/, $src);
    ok($code !~ /\b[Pp]wEevee-(?:\d+\.){2}\d+(?:-(?:nightly|alpha))?\.ipa\b/,
       "$file contains no hardcoded concrete artifact version");
}

# ================================================================ report
my $total = $pass + scalar @failures;
print "\n1..$total\n";
print "ok $_\n" for 1 .. $pass;
my $n = $pass;
for my $f (@failures) { $n++; print "not ok $n - $f\n" }
print "\n" . (@failures ? scalar(@failures) . " failed\n" : "all $pass checks passed\n");
exit(@failures ? 1 : 0);
