#!/usr/bin/env perl
# ============================================================================
# PwArtifact.pm — the one rule for what a PwEevee download is
# ============================================================================
#
# A PwEevee GitHub release may carry several files: the PwEevee IPA, the clean
# decrypted Spotify base it was built from, debs, notes, checksums. Only the
# PwEevee IPA is a PwEevee download, and its name is part of the contract:
#
#     PwEevee-X.Y.Z.ipa             stable
#     PwEevee-X.Y.Z-nightly.ipa     nightly
#     PwEevee-X.Y.Z-alpha.ipa       alpha
#
# "stable" is a release classification, never a filename suffix: there is no
# PwEevee-X.Y.Z-stable.ipa. The match is whole-filename and case-insensitive;
# the canonical spelling is always the name GitHub actually reported.
#
# This module exists because every consumer used to answer "which asset?" for
# itself, and "the first .ipa" is wrong the moment a release also ships the
# Spotify base (whose name sorts first). Consumers now share one answer:
#
#   update-releases.pl  -> writes release.download_asset / artifact_channel
#   update-readme.pl    -> README download line
#   update-appsource.pl -> which verified assets may be published
#   update-stats.pl     -> which downloads are PwEevee's
#   render-site.pl      -> the rendered download button
#   pweevee.js          -> the client-side safety-net card
# ============================================================================
package PwArtifact;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    parse_artifact is_canonical release_channel
    pick_artifact primary_for_release expected_name channel_label
);

# Whole filename only. No path separators, no queries, no extra suffixes.
my $RE = qr/\APwEevee-(\d+)\.(\d+)\.(\d+)(?:-(nightly|alpha))?\.ipa\z/i;

# Parse an asset filename. Returns a hashref:
#   { ok => 1, name, version, channel, numeric => [x,y,z] }
#   { ok => 0, reason }
sub parse_artifact {
    my ($name) = @_;
    return { ok => 0, reason => 'missing filename' }
        unless defined $name && length $name;
    return { ok => 0, reason => 'path separator' }
        if $name =~ m{[/\\]};
    return { ok => 0, reason => 'not a PwEevee-X.Y.Z[-nightly|-alpha].ipa filename' }
        unless $name =~ $RE;

    my ($x, $y, $z, $suffix) = ($1, $2, $3, lc($4 // ''));
    my $channel = length $suffix ? $suffix : 'stable';
    return {
        ok      => 1,
        name    => $name,
        version => "$x.$y.$z",
        channel => $channel,
        numeric => [ 0 + $x, 0 + $y, 0 + $z ],
    };
}

sub is_canonical { return parse_artifact($_[0])->{ok} ? 1 : 0 }

# A release's channel, from its tag and GitHub's prerelease flag. Unknown
# prerelease spellings are never silently treated as stable.
sub release_channel {
    my ($tag, $prerelease) = @_;
    my $t = lc($tag // '');
    return 'nightly' if $t =~ /-nightly(?:[.\-]|\d|$)/;
    return 'alpha'   if $t =~ /-alpha(?:[.\-]|\d|$)/;
    return 'prerelease' if $prerelease;
    return 'prerelease' if $t =~ /-(?:pre|beta|rc)(?:[.\-]|\d|$)/;
    return 'stable';
}

# Pick the asset for a channel. When $version is given, only that version may
# match: release 3.1.0 must never download PwEevee-3.1.5.ipa just because the
# file is present. Deterministic: newest version first, then the lexically
# first filename if a release somehow carries two. A non-https URL is not
# offered. Returns the asset hashref, or undef — never a fallback to a
# different channel and never the first arbitrary .ipa.
sub pick_artifact {
    my ($assets, $channel, $version) = @_;
    return undef unless ref $assets eq 'ARRAY' && defined $channel;
    $version = undef unless defined $version && length $version;
    my @hits;
    for my $a (@$assets) {
        next unless ref $a eq 'HASH';
        my $p = parse_artifact($a->{name});
        next unless $p->{ok} && $p->{channel} eq $channel;
        next if defined $version && $p->{version} ne $version;
        my $url = $a->{download_url} // $a->{browser_download_url} // $a->{url};
        next unless defined $url && $url =~ m{\Ahttps://}i;
        push @hits, [ $p, $a ];
    }
    return undef unless @hits;
    @hits = sort {
        my $c = 0;
        for my $i (0 .. 2) {
            $c = $b->[0]{numeric}[$i] <=> $a->[0]{numeric}[$i];
            last if $c;
        }
        $c || lc($a->[1]{name}) cmp lc($b->[1]{name})
    } @hits;
    return $hits[0][1];
}

# The download for a release, using strict PwEevee rules. $release is either a
# normalised release (version/assets) or a raw GitHub release (tag_name/assets).
sub primary_for_release {
    my ($release) = @_;
    return undef unless ref $release eq 'HASH';
    my $channel = release_channel(
        $release->{version} // $release->{tag_name},
        $release->{prerelease} ? 1 : 0,
    );
    return undef if $channel eq 'prerelease';
    my $version = ($release->{version} // $release->{tag_name} // '') =~ s/^v//r;
    return pick_artifact($release->{assets} // [], $channel, $version);
}

# "PwEevee-3.1.5-nightly.ipa" — for operator-facing messages only.
sub expected_name {
    my ($version, $channel) = @_;
    $channel //= 'stable';
    return undef unless defined $version && $version =~ /^\d+\.\d+\.\d+$/;
    my $suffix = ($channel eq 'nightly' || $channel eq 'alpha') ? "-$channel" : '';
    return "PwEevee-$version$suffix.ipa";
}

sub channel_label {
    my ($channel) = @_;
    return { stable => 'stable', nightly => 'nightly', alpha => 'alpha' }->{ $channel // '' } // 'release';
}

1;
