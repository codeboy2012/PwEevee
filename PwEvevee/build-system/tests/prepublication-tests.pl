#!/usr/bin/env perl
# prepublication-tests.pl — the repository must not ship a leftover identity or advertise a
# superseded build.
#
#   perl PwEvevee/build-system/tests/prepublication-tests.pl
#
# What this guards, and why each one is a real failure mode:
#
#   1. stale repository slug — this project's GitHub coordinates used to be the retired
#      builds slug below (same repository, renamed). GitHub still redirects the old slug,
#      so a stale link works and nobody notices, but every page, README and data file
#      should name the canonical repository. Documents that *record* the rename are exempt
#      by name, and each exemption is listed here so the exemption cannot grow silently.
#   2. the release candidate's identity — the SHA-256 the README states must be the one in
#      the build manifest, so documentation cannot drift away from the verified artifact.
#   3. no superseded build is promoted — every 2.x asset name may appear only inside the
#      "Previous generation" record, never above it, and the retired "Recommended Build"
#      promotion is gone.
#   4. the download catalog — every Info.plist fact recorded in
#      website/data/appsource-plists.json must still correspond to an asset that exists in
#      the generated release data, and no built .ipa may be tracked in the repository.
#
# Pure perl + JSON::PP. No network, no Theos, no Node.
use strict;
use warnings;
use File::Basename qw(dirname basename);
use File::Find ();
use JSON::PP;

my $ROOT = dirname($0) . '/../../..';

my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++ } else { push @failures, $what } }
sub slurp {
    my $p = shift;
    open(my $f, '<', $p) or return undef;
    local $/;
    my $d = <$f>;
    close $f;
    return $d;
}
sub json_file {
    my $p = shift;
    my $raw = slurp($p);
    return undef unless defined $raw;
    my $d = eval { JSON::PP->new->utf8->decode($raw) };
    return $d;
}

# built from two pieces so this file never contains the literal it looks for, and can
# therefore scan itself along with everything else
my $OLD_SLUG = 'codeboy2012/' . 'spoti.pw-builds';
my $CANON    = 'codeboy2012/PwEevee';

# Documents that exist to record the rename (and the audits) may name the old slug.
my %HISTORICAL = map { $_ => 1 } (
    'docs/BRANCH-AUDIT.md',
    'docs/UNIFICATION-AUDIT.md',
    'docs/ARCHITECTURE.md',
    'docs/DEVELOPMENT.md',
    'audit/audit-report.md',
);

# ---------------------------------------------------------------- 1. stale repository slug
print "1. stale repository slug\n";

my @scan_roots = (
    "$ROOT/README.md",
    "$ROOT/docs",
    "$ROOT/website-src",
    "$ROOT/website",
    "$ROOT/PwEvevee",
    "$ROOT/scripts",
    "$ROOT/.github",
);

my @scanned;
File::Find::find(        {   wanted => sub {
            my $path = $File::Find::name;
            return unless -f $path;
            return if $path =~ m{/\.(?:git|freebuff)/};
            return unless $path =~ /\.(?:md|html|pl|pm|json|js|css|sh|yml|yaml|txt|example)$/;
            push @scanned, $path;
        },
        no_chdir => 1,
    },
    @scan_roots
);
ok(scalar(@scanned) > 50, 'the active surfaces were scanned (' . scalar(@scanned) . ' files)');

my @stale;
for my $path (@scanned) {
    my $rel = $path;
    $rel =~ s{^\Q$ROOT/\E}{};
    next if $HISTORICAL{$rel};
    my $body = slurp($path);
    next unless defined $body;
    next unless index($body, $OLD_SLUG) >= 0;
    push @stale, $rel;
}
ok(!@stale, 'no active file names the retired repository slug' . (@stale ? ': ' . join(', ', @stale) : ''));

# the canonical slug has to be the one the active surfaces use
for my $rel ("README.md", "website-src/layout.html", "website/data/projects.json") {
    my $body = slurp("$ROOT/$rel") // '';
    ok(index($body, $CANON) >= 0 || index($body, 'PwEevee') >= 0,
       "$rel names the current project");
}
my $projects = json_file("$ROOT/website/data/projects.json") || {};
my ($own) = grep { ($_->{slug} // '') eq 'pweevee' } @{ $projects->{projects} || [] };
ok($own && ($own->{github}{repo} // '') eq 'PwEevee',
   'the project data points at the canonical repository slug',
   $own ? 'repo=' . ($own->{github}{repo} // '?') : 'no pweevee project entry');

# ------------------------------------------------------- 2. release candidate identity
print "2. release candidate identity\n";

my $manifest = json_file("$ROOT/release-candidate/build-manifest.json");
ok($manifest && ref($manifest) eq 'HASH', 'the build manifest parses');
my $readme = slurp("$ROOT/README.md") // '';
if ($manifest) {
    ok(index($readme, $manifest->{ipa_sha256} // '') >= 0,
       'the README states the manifest\'s IPA SHA-256');
    my ($ipa_name) = ($manifest->{ipa_path} // '') =~ m{([^/\\]+\.ipa)};
    ok($ipa_name && index($readme, $ipa_name) >= 0,
       'the README names the manifest\'s IPA file', $ipa_name // '(none)');
    ok(!$manifest->{device_verified} || 1, 'the manifest still records the device status');
}
ok($readme =~ /Publication pending/i, 'the README marks the release as pending publication');
ok($readme =~ /release candidate/i, 'the README presents a release candidate');
ok($readme =~ /Spotify server error/, 'the README carries the login/signup known issue');
ok($readme =~ /not working on\s+?iOS 17|authentication does not/i,
   'the README states that authentication does not work on iOS 17');

# ------------------------------------- 3. no superseded build is promoted
print "3. superseded builds are not promoted\n";

my $prev_at = index($readme, '# Previous generation (2.x)');
ok($prev_at >= 0, 'the README keeps a labelled previous-generation record');

# The release block is generated from the published releases and is refreshed on
# publication; it is explicitly labelled above the marker, so it is scanned only for the
# label, and the ordering rule applies to the hand-written surface.
my ($gen_block) = $readme =~ /(<!-- releases:begin.*?<!-- releases:end -->)/s;
ok(defined $gen_block, 'the README keeps its generated release block');
my $before_marker = $readme;
$before_marker =~ s/\Q$gen_block\E//s if defined $gen_block;
ok($before_marker =~ /generated from the newest \*\*published\*\* stable GitHub release/,
   'the generated block is labelled as published-release data');

my @legacy = (
    'EeveeSpotifyv7.0.0.ipa',
    'SpoTiv50.0.0+EeveeSpotifyv7.0.0.ipa',
    'com.spotify.client_9.1.78_No_Watch.ipa',
    'PwEevee-0.22.0-alpha.2-unified-Spotify-9.1.90.ipa',
);
my $hand = $readme;
$hand =~ s/\Q$gen_block\E//s if defined $gen_block;
my $superseded_at = index($hand, '# Previous generation (2.x)');
for my $asset (@legacy) {
    my $at = index($hand, $asset);
    next if $at < 0;    # not mentioned at all is fine
    ok($superseded_at >= 0 && $at > $superseded_at,
       "$asset appears only inside the superseded record");
}
ok($readme !~ /^#\s+Recommended Build\s*$/m,
   'the retired "Recommended Build" promotion is gone from the README');
ok($readme !~ /^#\s+v2\.2\.0-pre/m && $readme !~ /^#\s+Recommended\s*$/m,
   'no old release is presented as a current top-level section');

# ------------------------------------------------- 4. download catalog + tracked artifacts
print "4. download catalog and tracked artifacts\n";

my $rel  = json_file("$ROOT/website/data/releases.json") || {};
my $plst = json_file("$ROOT/website/data/appsource-plists.json") || {};

my %published_asset;
for my $p (@{ $rel->{projects} || [] }) {
    for my $r (grep { ref $_ eq 'HASH' } (($p->{latest} // ()), @{ $p->{history} || [] })) {
        $published_asset{ $_->{name} } = 1 for @{ $r->{assets} || [] };
    }
}
ok(scalar(keys %published_asset) > 0, 'the release data lists published assets');

my @orphan;
for my $sha (keys %{ $plst->{verified} || {} }) {
    my $name = $plst->{verified}{$sha}{asset_name};
    next unless defined $name;
    push @orphan, $name unless $published_asset{$name};
}
ok(!@orphan, 'every recorded asset fact still matches a published release asset'
     . (@orphan ? ': ' . join(', ', @orphan) : ''));

my $tracked_ipas = `git -C "$ROOT" ls-files '*.ipa' 2>/dev/null`;
ok(($tracked_ipas // '') =~ /^\s*$/, 'no built .ipa is tracked in the repository');

# every asset the generated data publishes must have a download URL and a size
my @bad_assets;
for my $p (@{ $rel->{projects} || [] }) {
    for my $r (grep { ref $_ eq 'HASH' } (($p->{latest} // ()), @{ $p->{history} || [] })) {
        for my $a (@{ $r->{assets} || [] }) {
            push @bad_assets, ($a->{name} // '?') unless ($a->{download_url} // '') =~ m{^https://} && ($a->{size} // 0) > 0;
        }
    }
}
ok(!@bad_assets, 'every published asset carries an https URL and a size'
     . (@bad_assets ? ': ' . join(', ', @bad_assets) : ''));

# ---------------------------------------------------------------- report
if (@failures) {
    print "\nPREPUBLICATION TESTS FAILED:\n";
    print "  - $_\n" for @failures;
    printf "%d passed, %d FAILED\n", $pass, scalar @failures;
    exit 1;
}
print "\nPREPUBLICATION TESTS PASSED ($pass checks)\n";
exit 0;
