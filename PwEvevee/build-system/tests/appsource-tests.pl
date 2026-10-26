#!/usr/bin/env perl
# appsource-tests.pl — deterministic checks for the published PwEevee app
# source and its website integration.
#
#   perl PwEvevee/build-system/tests/appsource-tests.pl
#
# Checks (no network):
#   1. schema   — SideStore/AltStore Classic required fields at every level,
#                 SideStore-strict exclusions (no PAL-only notarization fields,
#                 no per-version buildVersion), newest-first ordering, unique
#                 versions, https URLs, positive integer sizes, ISO dates;
#   2. accuracy — every version's size + download URL + published date must
#                 match the same asset's record in the independent
#                 releases.json snapshot, and the version metadata must match
#                 the appsource-plists.json registry the CI workflow maintains;
#   3. website  — the rendered /downloads page carries the SideStore and
#                 AltStore deep links with the exact percent-encoded source
#                 URL, a View Source JSON link, a Copy Source URL button and
#                 the "store app must already be installed" notice.
use strict;
use warnings;
use File::Basename qw(dirname);
use JSON::PP;

binmode STDOUT, ':utf8';
my $REPO = dirname($0) . '/../../..';
$REPO =~ s{/+$}{};

my $SRC_URL = 'https://pweevee.skytweak.dpdns.org/pweevee/apps.json';
my $URL_ENC = 'https%3A%2F%2Fpweevee.skytweak.dpdns.org%2Fpweevee%2Fapps.json';

my $pass = 0;
my @fail;
sub ok_check { my ($c, $m) = @_; if ($c) { $pass++ } else { push @fail, $m } }
sub slurp { my $p = shift; open my $f, '<', $p or return undef; local $/; my $d = <$f>; close $f; return $d }

# ---- load everything the checks need -------------------------------------
my $raw = slurp("$REPO/website/pweevee/apps.json") or do {
  print "1..1\nnot ok - website/pweevee/apps.json missing — run update-appsource.pl\n";
  exit 1;
};
ok_check(1, 'apps.json exists');

my $src = JSON::PP->new->decode($raw);
my $rl  = JSON::PP->new->decode(scalar slurp("$REPO/website/data/releases.json") // '{}');
my $pl  = JSON::PP->new->decode(scalar slurp("$REPO/website/data/appsource-plists.json") // '{}');

# rebuild the independent release-asset fact table (asset facts live on the
# asset record; publish dates belong to the release above it)
my %rel_assets;
for my $p (@{ $rl->{projects} // [] }) {
    next unless ($p->{slug} // '') eq 'pweevee';
    for my $rel (@{ $p->{history} // [] }) {
        for my $a (@{ $rel->{assets} // [] }) {
            next unless $a->{download_url};
            $rel_assets{ $a->{download_url} } = { %$a, released_at => $rel->{published_at} };
        }
    }
}
my %plists = %{ $pl->{verified} // {} };

# ---- 1. schema -------------------------------------------------------------
ok_check(($src->{name} // '') ne '', 'schema: top-level name present');
ok_check(($src->{identifier} // '') ne '', 'schema: top-level identifier present (SideStore requires it)');
ok_check(($src->{sourceURL} // '') eq $SRC_URL, 'schema: sourceURL equals the canonical published URL');
ok_check(($src->{iconURL} // '') =~ m{^https://}, 'schema: top-level iconURL is an https URL');
ok_check(($src->{website} // '') =~ m{^https://}, 'schema: top-level website is an https URL');
ok_check(ref $src->{apps} eq 'ARRAY' && @{ $src->{apps} }, 'schema: apps is a non-empty array');
ok_check(ref $src->{news} eq 'ARRAY', 'schema: news is an array (empty is fine)');

my %top_keys = map { $_ => 1 } keys %$src;
ok_check((not grep { $_ eq 'marketplaceID' } keys %top_keys), 'schema: no AltStore-PAL marketplaceID');

my @all_versions;
my %bundle_apps;
for my $a (@{ $src->{apps} }) {
    my $bid = $a->{bundleIdentifier} // '';
    $bundle_apps{$bid}++;
    for my $k (qw(name bundleIdentifier developerName localizedDescription iconURL versions)) {
        ok_check(defined $a->{$k} && length(ref($a->{$k}) ? 'x' : $a->{$k}),
            "schema: app $bid has required field $k");
    }
    ok_check(($a->{iconURL} // '') =~ m{^https://}, "schema: app $bid iconURL is https");
    ok_check((not grep { $_ eq 'category' } keys %$a),
        "schema: SideStore-strict: no app-level category on $bid");

    my @dates = map { $_->{date} } @{ $a->{versions} };
    my $newest_first_ok = 1;
    for my $i (0 .. $#dates - 1) { $newest_first_ok = 0 if $dates[$i] lt $dates[$i + 1] }
    ok_check($newest_first_ok,
        "schema: app $bid versions are newest-first (AltStore treats versions[0] as latest)");
    my %seen_dup;
    my $unique_ok = 1;
    for (@{ $a->{versions} }) { $unique_ok = 0 if $seen_dup{ $_->{version} }++ }
    ok_check($unique_ok,
        "schema: app $bid version strings are unique");

    for my $v (@{ $a->{versions} }) {
        push @all_versions, { %$v, _bid => $bid };
        my $vn = "$bid/$v->{version}";
        for my $k (qw(version date downloadURL size)) {
            ok_check(defined $v->{$k}, "schema: $vn has required field $k");
        }
        ok_check(($v->{downloadURL} // '') =~ m{^https://}, "schema: $vn downloadURL is https");
        ok_check($v->{size} =~ /^\d+$/ && $v->{size} > 0, "schema: $vn size is a positive integer");
        ok_check(($v->{date} // '') =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/,
            "schema: $vn date is ISO-8601 UTC");
        ok_check((not grep { $_ eq 'buildVersion' } keys %$v),
            "schema: SideStore-strict: no per-version buildVersion on $vn");
        ok_check((not grep { $_ eq 'Build' || $_ eq 'marketplaceID' } keys %$v),
            "schema: no PAL/notarization fields on $vn");
        my $min = $v->{minOSVersion};
        ok_check(!defined $min || ($min =~ /^\d+(\.\d+)?$/ && $min ne ''),
            "schema: $vn minOSVersion present only as verified number");
    }
}
ok_check(scalar(keys %bundle_apps) == scalar @{ $src->{apps} },
    'schema: one app grouping per bundleIdentifier (no duplicate groups)');

# ---- 2. accuracy -----------------------------------------------------------
for my $v (@all_versions) {
    my $a = $rel_assets{ $v->{downloadURL} };
    if ($a) {
        ok_check($a->{size} == $v->{size},
            "accuracy: size matches releases.json for $v->{version}");
        ok_check(($a->{released_at} // '') eq $v->{date},
            "accuracy: date matches releases.json for $v->{version}");
        ok_check(($a->{download_count} // 0) >= 0, "accuracy: asset exists in release history for $v->{version}");
        my $plf = $plists{ $a->{sha256} // '' };
        ok_check(defined $plf, "accuracy: version $v->{version} has a verified plist entry (keyed by its SHA-256)");
        if ($plf) {
            ok_check($plf->{bundleIdentifier} eq $v->{_bid},
                "accuracy: bundleIdentifier matches the app grouping for $v->{version}");
            ok_check($plf->{asset_name}, "accuracy: plist registry entry records its source asset for $v->{version}");
        }
    } else {
        ok_check(0, "accuracy: $v->{version} downloadURL is not a tracked release asset");
    }
}

# ---- 3. website integration --------------------------------------------------
my $page = slurp("$REPO/website/downloads/index.html") // '';
ok_check(length $page > 100, 'website: rendered /downloads page exists');
ok_check(index($page, "sidestore://source?url=$URL_ENC") >= 0,
    'website: /downloads carries the SideStore deep link with the exact encoded source URL');
ok_check(index($page, "altstore://source?url=$URL_ENC") >= 0,
    'website: /downloads carries the AltStore deep link with the exact encoded source URL');
ok_check(index($page, 'href="' . $SRC_URL . '"') >= 0,
    'website: /downloads links the raw source JSON (View Source JSON)');
ok_check(index($page, 'data-copy="' . $SRC_URL . '"') >= 0,
    'website: /downloads has a Copy Source URL button wired to the exact URL');
ok_check(index($page, '/releases') >= 0, 'website: /downloads links the release history');
ok_check(index($page, 'store app must already be installed') >= 0,
    'website: /downloads explains the custom URL scheme needs the store app installed');
ok_check(index($page, 'id="app-source"') >= 0, 'website: the app-source section has an anchor');

# ---- report -----------------------------------------------------------------
my $total = $pass + scalar @fail;
print "1..$total\n";
for my $i (1 .. $pass) { print "ok $i\n" }
my $n = $pass;
for my $m (@fail) { $n++; print "not ok $n - $m\n" }
exit(@fail ? 1 : 0);
