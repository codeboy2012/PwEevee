#!/usr/bin/env perl
# update-appsource.pl — generate the published PwEevee app source for
# AltStore Classic and SideStore.
#
#   perl PwEvevee/build-system/release/update-appsource.pl [--check]
#
# Inputs
#   website/data/appsource-plists.json  Info.plist facts read out of each release
#                                       IPA, keyed by asset SHA-256 (the
#                                       appsource-update.yml workflow appends)
#   website/data/releases.json          GitHub release data (update-releases.pl)
#
# Output
#   website/pweevee/apps.json           the published source, served from
#            https://pweevee.skytweak.dpdns.org/pweevee/apps.json
#
# Schema policy (docs.sidestore.io "App Sources", SideStore/sidestore-source-types
# schema.json, faq.altstore.io "Make a Source" / "Updating Apps"):
#   - Compatible with both AltStore Classic and SideStore. Only fields BOTH
#     sides document are emitted. SideStore's schema is strict
#     (additionalProperties: false), so app-level `category`, per-version
#     `buildVersion`, `downloadDate` and AltStore-PAL-only fields
#     (`marketplaceID`, `Build`) are deliberately NOT emitted.
#   - SideStore-required / AltStore Classic fields kept in sync:
#     top level: name, identifier, apps (+ optional sourceURL, news, iconURL,
#     website, tintColor); app: name, bundleIdentifier, developerName,
#     localizedDescription, iconURL, versions (+ optional subtitle, tintColor,
#     websiteURL); version: version, date, downloadURL, size (+ optional
#     localizedDescription, minOSVersion, maxOSVersion, capital "OS"), so the
#     optional app- and version-level legacy fields match versions[0].
#   - versions[0] must be the newest release: AltStore takes the first version
#     as the latest and ignores dates/order for that decision.
#   - minOSVersion is emitted ONLY where the shipped Info.plist states
#     MinimumOSVersion; nothing about compatibility is guessed.
#   - The version string is the PwEevee release version (not the Spotify host
#     version): this source distributes PwEevee, different releases can ship
#     the same Spotify base, and releases sharing an asset set are
#     disambiguated with a `-combined` suffix.
#
# Failure policy: an IPA whose SHA-256 has no verified plist entry is SKIPPED,
# never imported with guessed metadata. Any validation failure aborts BEFORE
# the write, so the previously published source stays intact.
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use JSON::PP;

binmode STDOUT, ':utf8';
my $OPT_CHECK = grep { $_ eq '--check' } @ARGV;

my $REPO_ROOT = dirname($0) . '/../../..';
$REPO_ROOT =~ s{/+$}{};

my $DATA    = "$REPO_ROOT/website/data";
my $OUTPATH = "$REPO_ROOT/website/pweevee/apps.json";

# The published identity of the source. Permanent once published — changing it
# would orphan every installed-source client and re-add it as a new source.
my $SOURCE_IDENTIFIER = 'org.pweevee.apps';
my $SOURCE_URL_PATH   = 'https://pweevee.skytweep-error.invalid/'; # replaced below
$SOURCE_URL_PATH      = 'https://pweevee.skytweak.dpdns.org/pweevee/apps.json';

# One app grouping per bundle identifier, in this display order.
my @APP_ORDER = ('com.spotify.client', 'com.skywatch.spotify');
my %APP_NAME  = (
    'com.spotify.client'  => 'PwEevee',
    'com.skywatch.spotify'=> 'PwEevee (watchfix experimental)',
);

sub read_json {
    my ($p) = @_;
    open my $f, '<', $p or return undef;
    local $/; my $d = <$f>; close $f;
    return JSON::PP->new->decode($d);
}

my $PL = read_json("$DATA/appsource-plists.json")
  or die "appsource: website/data/appsource-plists.json unreadable — fill it first\n";
my $RL = read_json("$DATA/releases.json")
  or die "appsource: website/data/releases.json not found — run update-releases.pl first\n";

my $valid_plists = $PL->{verified} // {};

# ------------------------------------------------------- collect candidates
# Candidate = a release-history IPA whose SHA-256 matches a verified plist
# entry. Release history comes out of releases.json newest first.
my @candidates;    # { asset release plist sha }
my ($pweevee) = grep { ($_->{slug} // '') eq 'pweevee' } @{ $RL->{projects} // [] };
$pweevee or die "appsource: no pweevee project in releases.json\n";

for my $rel (@{ $pweevee->{history} // [] }) {
    for my $a (@{ $rel->{assets} // [] }) {
        next unless ($a->{kind} // '') eq 'ipa';
        next unless $a->{sha256} && $a->{size} && $a->{download_url};
        my $pl = $valid_plists->{ $a->{sha256} };
        # unverified -> skip, never guess
        push @candidates, { asset => $a, release => $rel, plist => $pl, sha => $a->{sha256} }
          if $pl;
    }
}

@candidates
  or die "appsource: no verified IPA candidates — nothing to publish\n";
warn "appsource: note — @{[ grep { my $k='$_'; () } () ] }" if 0; # (no-op)

# group into apps by bundleIdentifier, keeping release order (newest first)
# as the version order inside each app
my %by_bundle;
my @bundle_order;
for my $c (@candidates) {
    my $bid = $c->{plist}{bundleIdentifier};
    push @bundle_order, $bid unless $by_bundle{$bid};

    my $ver = $c->{release}{version};
    # combined vs standalone builds of the same release share the tag
    my $already = scalar grep { $_->{version} eq $ver } @{ $by_bundle{$bid} // [] };
    $ver .= '-combined' if $already;

    my $summary = $c->{release}{summary} // '';
    $summary =~ s/\s+/ /g;
    if (length $summary > 300) { $summary = substr($summary, 0, 300) . ' …' }

    my $v = {
        version     => $ver,
        date        => $c->{release}{published_at},
        downloadURL => $c->{asset}{download_url},
        size        => $c->{asset}{size},
        localizedDescription
          => "PwEevee release $ver — asset $c->{asset}{name}. Spotify base "
           . $c->{plist}{CFBundleShortVersionString} . ' (build '
           . $c->{plist}{CFBundleVersion} . '). ' . $summary,
    };
    $v->{minOSVersion} = $c->{plist}{MinimumOSVersion}
      if defined $c->{plist}{MinimumOSVersion} && length $c->{plist}{MinimumOSVersion};

    push @{ $by_bundle{$bid} }, $v;
}

# ------------------------------------------------------- assemble the source
my $icon_url = 'https://pweevee.skytweak.dpdns.org/assets/brand/pweevee-app-icon.png';
my $website  = 'https://pweevee.skytweak.dpdns.org/';
my $tint     = '#1DB954';

my @apps;
for my $bid (grep { $by_bundle{$_} } @APP_ORDER) {
    my $newest = $by_bundle{$bid}[0];
    push @apps, {
        name                 => $APP_NAME{$bid} // $bid,
        bundleIdentifier     => $bid,
        developerName        => 'PwEevee',
        subtitle             => 'Spotify customizer for sideloading',
        localizedDescription =>
          'PwEevee packages modified Spotify iOS builds (the spoti.pw and '
        . 'EeveeSpotify components, by their own developers) into installable '
        . 'IPAs. Sign with your own certificate when installing: the builds '
        . 'are unsigned. PwEevee is an independent project and is not '
        . 'affiliated with or endorsed by Spotify or Apple.',
        iconURL              => $icon_url,
        tintColor            => $tint,
        websiteURL           => $website,
        versions             => $by_bundle{$bid},
        # deprecated app-level legacy fields (SideStore schema keeps them
        # optional; AltStore Classic documents them): kept equal to versions[0]
        # so older clients that read app-level facts stay correct.
        downloadURL          => $newest->{downloadURL},
        size                 => $newest->{size},
        version              => $newest->{version},
        versionDescription   => $newest->{localizedDescription},
        versionDate          => $newest->{date},
    };
}

my %visible = map { $_ => 1 } @APP_ORDER;
my @extra_bundles = grep { !$visible{$_} } @bundle_order;
die "appsource: new bundle id(s) [@extra_bundles] appeared in verified plists — "
  . "add them to /APP_ORDER + /%APP_NAME or exclude them intentionally\n"
  if @extra_bundles;

my $source = {
    name       => 'PwEevee App Source',
    identifier => $SOURCE_IDENTIFIER,
    sourceURL  => $SOURCE_URL_PATH,
    iconURL    => $icon_url,
    website    => $website,
    tintColor  => $tint,
    apps       => \@apps,
    news       => [],
};

# ------------------------------------------------------- validate before write
my @fail;
for my $a (@apps) {
    for my $req (qw(name bundleIdentifier developerName localizedDescription iconURL versions)) {
        push @fail, "app $a->{bundleIdentifier}: missing $req"
          unless defined $a->{$req} && (($a->{$req} // '') ne '');
    }
    for my $v (@{ $a->{versions} }) {
        for my $req (qw(version date downloadURL size localizedDescription)) {
            push @fail, "$a->{name} v$v->{version}: missing $req" unless defined $v->{$req};
        }
        push @fail, "$a->{name} v$v->{version}: downloadURL not https"
          unless ($v->{downloadURL} // '') =~ m{^https://};
        push @fail, "$a->{name} v$v->{version}: size not a positive integer"
          unless $v->{size} =~ /^\d+$/ && $v->{size} > 0;
        push @fail, "$a->{name} v$v->{version}: date not ISO-8601 UTC"
          unless ($v->{date} // '') =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
    }
    # newest-first by published_at (versions[0] is what AltStore treats as
    # latest, ignoring the version strings and dates)
    my @dates = map { $_->{date} } @{ $a->{versions} };
    push @fail, "$a->{name}: versions not in newest-first order"
      if grep { $dates[$_] lt $dates[$_ + 1] } 0 .. $#dates - 1;
    # unique version strings (two releases with the same asset dedupe above)
    my %seen_v;
    push @fail, "$a->{name}: duplicate version keys"
      if grep { $seen_v{$_}++ } map { $_->{version} } @{ $a->{versions} };
}
push @fail, 'apps array empty — refusing to publish an empty source' unless @apps;
push @fail, "source identifier missing" unless defined $SOURCE_IDENTIFIER && length $SOURCE_IDENTIFIER;
push @fail, "source URL missing"        unless defined $SOURCE_URL_PATH && length $SOURCE_URL_PATH;

die "appsource: FAILED (nothing written; previous source intact)\n    "
  . join("\n  ", @fail) . "\n" if @fail;

# Cross-check every listed size against the same asset's record in
# releases.json: both must agree or the data feeds disagree.
my %rel_sizes;
for my $a (@{ $pweevee->{history} // [] }) {
    for my $asset (@{ $a->{assets} // [] }) {
        $rel_sizes{ $asset->{download_url} } = $asset->{size} if $asset->{download_url};
    }
}
for my $a (@apps) {
    for my $v (@{ $a->{versions} }) {
        push @fail, "size mismatch apps.json vs releases.json for $v->{downloadURL}"
          if exists $rel_sizes{ $v->{downloadURL} }
          && $rel_sizes{ $v->{downloadURL} } != $v->{size};
    }
}
die "appsource: cross-check FAILED (nothing written)\n    "
  . join("\n  ", @fail) . "\n" if @fail;

# ------------------------------------------------------------- write (atomic)
my $text = JSON::PP->new->canonical(1)->pretty(1)->allow_nonref->encode($source);

if ($OPT_CHECK) {
    print "appsource: --check OK — ".scalar(@apps)." app(s) ("
      . join(', ', map { $_->{name}.': '.scalar(@{ $_->{versions} }).' version(s)' } @apps)
      . ") → would write $OUTPATH\n";
    exit 0;
}

make_path(dirname($OUTPATH));
my ($tfh, $tmpname) = tempfile("$OUTPATH.XXXXXX", UNLINK => 1, SUFFIX => '.tmp');
binmode $tfh, ':raw';
print {$tfh} $text;
close $tfh;

# re-read and re-parse: the published bytes must round-trip cleanly
my $round = do { local $/; open my $r, '<:raw', $tmpname or die; scalar <$r> };
my $parsed = eval { JSON::PP->new->decode($round) };
die "appsource: written file does not re-parse cleanly — not published\n"
  unless $parsed && ref $parsed->{apps} eq 'ARRAY' && @{ $parsed->{apps} }
  && $parsed->{apps}[0]{bundleIdentifier} eq $apps[0]{bundleIdentifier};

rename $tmpname, $OUTPATH or die "appsource: cannot move into $OUTPATH: $!\n";
print "appsource: wrote $OUTPATH (" . length($text) . " bytes, "
  . scalar(@apps) . " app(s))\n";
