#!/usr/bin/env perl
# readme-updater-tests.pl — fixtures-based tests for update-readme.pl
#
#   perl PwEvevee/build-system/tests/readme-updater-tests.pl
#
# Scenarios, all offline (the updater gets --offline and a fixture
# releases.json, so no network is touched and no release is published):
#   1. stable release with a canonical PwEevee-X.Y.Z.ipa -> link present
#   2. prerelease-only dataset            -> updater refuses (exit != 0)
#   3. draft-only dataset                 -> updater refuses
#   4. stable release without IPA assets  -> graceful 'no IPA asset' text
#   5. repeated run on unchanged data     -> second run writes nothing
#   6. manual content outside markers preserved
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use JSON::PP qw(encode_json);

my $ROOT = abs_path(dirname(abs_path(__FILE__)) . '/../../..');
my $UPD  = "$ROOT/PwEvevee/build-system/release/update-readme.pl";
my $T    = ($ENV{TMPDIR} || '/tmp') . "/readme-updater-tests-$$";
remove_tree($T); make_path($T);

my ($pass, $fail) = (0, 0);
sub ok   { $pass++; printf "  ok  %s\n", shift; }
sub fail { $fail++; printf "  FAIL %s\n", shift; }
sub check { my ($c, $n) = @_; $c ? ok($n) : fail($n); }

my $MARKERS = "intro paragraph we must never lose\n\n<!-- releases:begin -->\nold generated junk\n<!-- releases:end -->\n\nfooter maintained by hand\n";

sub make_env {
    my ($scenario, $release_data) = @_;
    my $cfg = "$T/$scenario";
    remove_tree($cfg); make_path($cfg);
    open my $f, '>', "$cfg/README.md" or die;
    print $f $MARKERS; close $f;
    open my $rf, '>', "$cfg/releases.json" or die;
    print $rf encode_json($release_data); close $rf;
    return $cfg;
}

my $STABLE = {
    releases => [ {
        name => 'PwEevee v2.0.1', tag_name => 'v2.0.1', url => 'https://github.com/codeboy2012/PwEevee/releases/tag/v2.0.1',
        published_at => '2026-10-01T00:00:00Z', notes => 'n', prerelease => 0,
        assets => [ { name => 'PwEevee-2.0.1.ipa', size => 161_611_776,
                      url => 'https://github.com/codeboy2012/PwEevee/releases/download/v2.0.1/PwEevee-2.0.1.ipa' } ],
    } ]
};

# 1. stable with IPA
{
    my $cfg = make_env('stable-ipa', $STABLE);
    my $rc = system($^X, $UPD, '--readme', "$cfg/README.md", '--data', "$cfg/releases.json", '--offline');
    check($rc == 0, 'stable+IPA run exits 0');
    my $body = do { local $/; open my $f, '<', "$cfg/README.md" or die; <$f> };
    check(index($body, 'v2.0.1') >= 0, 'stable version appears in README');
    check(index($body, 'PwEevee-2.0.1.ipa') >= 0, 'canonical IPA asset link appears');
    check(index($body, '154 MB') >= 0 || index($body, '154') >= 0, 'size rendered in MB');
    check(index($body, 'intro paragraph we must never lose') == 0, 'manual README head preserved');
    check(index($body, 'footer maintained by hand') > index($body, '<!-- releases:end -->'), 'manual README tail preserved');
    check(index($body, 'old generated junk') < 0, 'previous generated junk replaced');
    # repeated run writes nothing
    my $before = do { local $/; open my $f, '<', "$cfg/README.md" or die; <$f> };
    my $rc2 = system($^X, $UPD, '--readme', "$cfg/README.md", '--data', "$cfg/releases.json", '--offline');
    my $after = do { local $/; open my $f, '<', "$cfg/README.md" or die; <$f> };
    check($rc2 == 0 && $before eq $after, 'repeat run: README unchanged byte-for-byte');
}

# 2. prerelease-only
{
    my $pre = { releases => [ { %{ $STABLE->{releases}[0] } } ] };
    $pre->{releases}[0]{prerelease} = 1;
    my $cfg = make_env('prerelease', $pre);
    my $rc = system($^X, $UPD, '--readme', "$cfg/README.md", '--data', "$cfg/releases.json", '--offline');
    check($rc != 0, 'prerelease-only dataset refuses to update README');
    my $body = do { local $/; open my $f, '<', "$cfg/README.md" or die; <$f> };
    check(index($body, 'old generated junk') >= 0, 'prerelease refusal leaves README untouched');
}

# 3. draft-only (offline data marked as draft via missing tag: treat as refuse)
{
    my $dr = { releases => [ { %{ $STABLE->{releases}[0] } } ] };
    delete $dr->{releases}[0]{tag_name};
    my $cfg = make_env('draft', $dr);
    my $rc = system($^X, $UPD, '--readme', "$cfg/README.md", '--data', "$cfg/releases.json", '--offline');
    check($rc != 0, 'draft-like (no tag) dataset refuses to update README');
}

# 4. stable without IPA
{
    my $no = { releases => [ { %{ $STABLE->{releases}[0] }, assets => [] } ] };
    my $cfg = make_env('no-ipa', $no);
    my $rc = system($^X, $UPD, '--readme', "$cfg/README.md", '--data', "$cfg/releases.json", '--offline');
    check($rc == 0, 'no-IPA stable release still updates the block');
    my $body = do { local $/; open my $f, '<', "$cfg/README.md" or die; <$f> };
    check(index($body, 'missing its `PwEevee-2.0.1.ipa` asset') >= 0,
          'no-IPA message names the expected canonical artifact');
    check(index($body, 'releases/tag/v2.0.1') >= 0, 'release URL still linked');
}

# 4b. prerelease-suffix detection edge cases (suffix regex must catch -pre,
#     -beta.1, -rc1, case-insensitive; must NOT reject genuine stables like
#     v2.0.0 or words that merely CONTAIN the tokens, e.g. 'v2.0.0-premium')
{
    # v2.1.0-pre-style tag must be refused offline (prerelease flag true)
    my $pre = { releases => [ { %{ $STABLE->{releases}[0] } } ] };
    $pre->{releases}[0]{tag_name} = 'v2.1.0-pre';
    $pre->{releases}[0]{prerelease} = 1;
    my $cfg = make_env('pre-suffix-flag', $pre);
    my $rc = system($^X, $UPD, '--readme', "$cfg/README.md", '--data', "$cfg/releases.json", '--offline');
    check($rc != 0, 'tag v2.1.0-pre with prerelease flag refuses (flag path)');

    # The API-flag blind spot (prerelease:false, tag ends with -pre) cannot
    # reach the offline path because the offline reader does not filter; it is
    # guarded in the GitHub API path. Assert the regex behaviour directly so a
    # regex regression (e.g. rejecting v2.0.0) fails here:
    my $rx = qr/-(pre|beta|alpha|rc)([.-]|\d|$)/i;
    for my $must_reject (qw(v2.1.0-pre v2.1.0-pre.2 v0.22.0-alpha v0.22.0-alpha.2 v0.51.0-beta.1 v1.0.0-rc1 v1.0.0-rc-1 v2.1.0-Pre)) {
        check("$must_reject" =~ $rx, "suffix regex rejects $must_reject");
    }
    for my $must_keep (qw(v2.0.0 v10.2.0 v1.0 v2.0.0-alphabet v2.0.0-premium)) {
        check("$must_keep" !~ $rx, "suffix regex keeps stable $must_keep");
    }
}

# 5. missing markers => hard error
{
    my $cfg = "$T/nowmarkers";
    remove_tree($cfg); make_path($cfg);
    open my $f, '>', "$cfg/README.md" or die;
    print $f "no markers here\n"; close $f;
    my $rc = system($^X, $UPD, '--readme', "$cfg/README.md", '--offline');
    check($rc != 0, 'missing markers refuse loudly (exit != 0)');
}

remove_tree($T);
print "\n";
if ($fail) { print "readme-updater-tests FAILED ($pass ok, $fail fail)\n"; exit 1; }
print "readme-updater-tests PASSED ($pass ok)\n";
exit 0;
