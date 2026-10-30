#!/usr/bin/env perl
# ============================================================================
# update-releases.pl — generate website/data/releases.json from the GitHub API
# ============================================================================
#
#   perl PwEvevee/build-system/release/update-releases.pl [options]
#
# Repository coordinates are read from website/data/projects.json — every repo is
# declared exactly once, there. For each project this script:
#
#   1. queries the GitHub releases API
#   2. picks the newest PUBLISHED release (drafts are never considered; a
#      prerelease is used only when a project has no stable release at all)
#   3. validates the response shape
#   4. extracts version, release name, dates, URL, notes and flags
#   5. extracts every asset with name, size, content type and download URL
#   6. validates each download URL (https + GitHub host); --verify-assets also
#      HEAD-checks that the file really is there
#   7. writes website/data/releases.json atomically
#   8. fails loudly when GitHub cannot be reached
#   9. keeps the previous known-good entry for a failed project, flagged stale,
#      instead of replacing good data with nothing
#
# No token is required. If GITHUB_TOKEN (or GH_TOKEN) is set it raises the rate
# limit; it is handed to curl through a 0600 config file so it never appears in
# the process list, and it is NEVER written into the generated data.
#
# Options
#   --out PATH         output file (default website/data/releases.json)
#   --projects PATH    project data model (default website/data/projects.json)
#   --history N        releases kept per project for the history page (default 12)
#   --verify-assets    HEAD-check every asset download URL
#   --strict           exit non-zero if any project did not update cleanly
#   --offline          do not call GitHub; revalidate and rewrite existing data
#   --quiet            print warnings and errors only
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin ();
use lib "$FindBin::Bin/lib";
use JSON::PP ();
use POSIX qw(strftime);
use PwSite qw(repo_root read_json write_json date_epoch fmt_date fmt_bytes
              text_excerpt is_safe_url);
use PwHttp qw(http_init http_get http_head http_cleanup);
use PwArtifact qw(parse_artifact release_channel pick_artifact expected_name);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# RELEASES_API_BASE is a test seam, not a configuration knob: the refresh-pipeline
# suite points it at a local 127.0.0.1 mock so the real selection rules (newest
# published release wins; a draft is never considered; a release flagged
# prerelease, or tagged with a -pre/-beta/-alpha/-rc suffix, is presented only
# when the repository has no stable release at all) are exercised
# deterministically instead of against live GitHub. Mirrors STATS_API_BASE in
# update-stats.pl.
my $API   = $ENV{RELEASES_API_BASE} || 'https://api.github.com';
my $TRUE  = JSON::PP::true;
my $FALSE = JSON::PP::false;

my %opt = (
    out      => 'website/data/releases.json',
    projects => 'website/data/projects.json',
    history  => 12,
);
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '--out')           { $opt{out}      = shift @ARGV }
    elsif ($a eq '--projects')      { $opt{projects} = shift @ARGV }
    elsif ($a eq '--history')       { $opt{history}  = shift @ARGV }
    elsif ($a eq '--verify-assets') { $opt{verify}   = 1 }
    elsif ($a eq '--strict')        { $opt{strict}   = 1 }
    elsif ($a eq '--offline')       { $opt{offline}  = 1 }
    elsif ($a eq '--quiet')         { $opt{quiet}    = 1 }
    elsif ($a eq '-h' || $a eq '--help') { usage(); exit 0 }
    else  { die "unknown option: $a (try --help)\n" }
}
defined $opt{history} && $opt{history} =~ /^[1-9]\d*$/
    or die "--history needs a positive integer\n";

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $TOKEN = $ENV{GITHUB_TOKEN} || $ENV{GH_TOKEN} || '';
my $HTTP  = $opt{offline} ? 'none'
          : http_init(tmp_dir => 'PwEvevee/build-system/_work/net',
                      user_agent => 'PwEevee-release-updater');
END { http_cleanup() }

info("PwEevee release updater");
info("  repository root : $ROOT");
info("  http client     : $HTTP");
info('  authentication  : ' . ($TOKEN ? 'GITHUB_TOKEN present' : 'anonymous (60 requests/hour)'));
info('');

warn "!! GITHUB_TOKEN is set but wget is the only client available; the token would be\n"
   . "   visible in the process list, so it will NOT be used. Install curl for authenticated requests.\n"
    if $TOKEN && $HTTP eq 'wget';

# ---------------------------------------------------------------- inputs

-f $opt{projects} or die "missing project data model: $opt{projects}\n";
my $model = read_json($opt{projects});
ref $model eq 'HASH' && ref $model->{projects} eq 'ARRAY'
    or die "$opt{projects}: expected an object with a 'projects' array\n";

my %prev_by_slug;
if (-f $opt{out}) {
    my $previous = eval { read_json($opt{out}) };
    if (ref $previous eq 'HASH' && ref $previous->{projects} eq 'ARRAY') {
        $prev_by_slug{ $_->{slug} } = $_ for grep { $_->{slug} } @{ $previous->{projects} };
    } else {
        warn "!! existing $opt{out} could not be parsed; it will be regenerated\n";
    }
}

# ---------------------------------------------------------------- fetch loop

my (@out, @failed, @stale);

for my $p (@{ $model->{projects} }) {
    my $slug = $p->{slug} or next;
    my $name = $p->{name} // $slug;
    my $gh   = ref $p->{github} eq 'HASH' ? $p->{github} : {};
    my $nwo  = ($gh->{owner} && $gh->{repo}) ? "$gh->{owner}/$gh->{repo}" : undef;

    unless ($nwo) {
        warn "!! $name: no GitHub repository declared in $opt{projects}\n";
        push @out, unavailable_entry($p, 'No GitHub repository is declared for this project.');
        push @failed, $name;
        next;
    }

    info("Fetching $name ($nwo)...");

    if ($opt{offline}) {
        if (my $keep = $prev_by_slug{$slug}) {
            info('  - offline: keeping existing data (' . version_of($keep) . ')');
            push @out, $keep;
        } else {
            warn "!! $name: offline mode and no previously generated data\n";
            push @out, unavailable_entry($p, 'Offline mode and no previously generated data.');
            push @failed, $name;
        }
        next;
    }

    my ($releases, $err) = api_releases($nwo);

    if (!$err) {
        my @published = grep { !$_->{draft} && $_->{published_at} } @$releases;
        $err = 'The repository has no published releases.' unless @published;

        unless ($err) {
            # Some authors ship pre-releases without the API flag (observed:
            # v2.1.0-pre counts prerelease: false on the wire). Treat the
            # usual suffixes as prerelease so they never present as stable.
            my ($tagname) = ($_);   # keep map bodies below self-contained
            # For PwEevee itself the stable channel is strict: a prerelease is
            # never promoted to "latest" just because no stable release exists.
            # Upstream projects keep their historical fallback.
            my $strict = ($slug eq 'pweevee');
            my @stable = grep { !$_->{prerelease} && ($_->{tag_name} // '') !~ /-(pre|beta|alpha|rc)([.-]|$)/i } @published;
            my @pool   = $strict ? @stable : (@stable ? @stable : @published);
            if ($strict && !@pool) {
                $err = 'No stable release has been published yet.';
            } else {
                @pool      = sort { date_epoch($b->{published_at}) <=> date_epoch($a->{published_at}) } @pool;
                @published = sort { date_epoch($b->{published_at}) <=> date_epoch($a->{published_at}) } @published;

                my $latest = normalise_release($pool[0], $nwo, $strict);
                my $keep_n = @published < $opt{history} ? scalar(@published) : $opt{history};
                my @history = map { normalise_release($_, $nwo, $strict) } @published[ 0 .. $keep_n - 1 ];

                if ($strict && !$latest->{download_asset}) {
                    my $want = expected_name($latest->{version},
                        release_channel($latest->{version}, $latest->{prerelease} ? 1 : 0));
                    warn "!! $name: release $latest->{version} has no valid "
                       . ($want // 'PwEevee-X.Y.Z.ipa')
                       . " asset; the site will report the artifact as missing\n";
                }

                info(sprintf('  %s Latest release: %s%s',
                    "\x{2713}", $latest->{version},
                    ($latest->{prerelease} ? '  (prerelease — this repository has no stable release)' : '')));
                info(sprintf('    published %s  ·  %d asset%s',
                    $latest->{published_label},
                    scalar @{ $latest->{assets} },
                    (@{ $latest->{assets} } == 1 ? '' : 's')));
                info(sprintf('      - %s (%s)', $_->{name}, $_->{size_label})) for @{ $latest->{assets} };
                info('      (this release carries no downloadable assets)') unless @{ $latest->{assets} };

                if ($opt{verify}) {
                    for my $a (@{ $latest->{assets} }) {
                        my $code = http_head($a->{download_url});
                        my $good = ($code && $code =~ /^(?:200|302)$/) ? 1 : 0;
                        $a->{verified} = $good ? $TRUE : $FALSE;
                        warn "!! $name: asset '$a->{name}' HEAD returned " . ($code // 'no response') . "\n"
                            unless $good;
                    }
                    info('    asset URLs verified');
                }

                push @out, {
                    slug         => $slug,
                    name         => $name,
                    repo         => $nwo,
                    repo_url     => "https://github.com/$nwo",
                    issues_url   => "https://github.com/$nwo/issues",
                    releases_url => "https://github.com/$nwo/releases",
                    available    => $TRUE,
                    stale        => $FALSE,
                    latest       => $latest,
                    history      => \@history,
                };
                next;
            }
        }
    }

    # --- failure path: never destroy good data -----------------------------
    warn "!! $name: $err\n";
    if (my $keep = $prev_by_slug{$slug}) {
        my %copy = %$keep;
        $copy{stale}       = $TRUE;
        $copy{stale_since} = iso_now();
        $copy{error}       = $err;
        info('  - keeping the previous known-good release (' . version_of($keep) . ')');
        push @out, \%copy;
        push @stale, $name;
    } else {
        push @out, unavailable_entry($p, $err);
        push @failed, $name;
    }
}

# ---------------------------------------------------------------- output

write_json($opt{out}, {
    schema       => 1,
    generated_at => iso_now(),
    generator    => 'PwEvevee/build-system/release/update-releases.pl',
    source       => 'GitHub REST API (api.github.com) — public release data only',
    projects     => \@out,
});

my $fresh = grep { $_->{available} && !$_->{stale} } @out;

info('');
printf "Generated %s — %d of %d project%s %s.\n",
    $opt{out}, $fresh, scalar @out, (@out == 1 ? '' : 's'),
    ($opt{offline} ? 'reused from existing data (offline, nothing was fetched)' : 'fetched fresh');
printf "Kept previous known-good data for: %s\n", join(', ', @stale) if @stale;
if (@failed) {
    printf "No release data available for: %s\n", join(', ', @failed);
    print  "The site renders an explanatory state for these instead of a broken download.\n";
}

if (!$fresh && !@stale) {
    print STDERR "\n!! FAIL: no release data could be retrieved for any project, and there was\n"
               . "   no previous data to fall back on. $opt{out} now describes the failure.\n";
    exit 2;
}
if ($opt{strict} && (@failed || @stale)) {
    my $n = scalar(@failed) + scalar(@stale);
    print STDERR "\n!! FAIL: --strict was requested and $n project(s) did not update cleanly.\n";
    exit 2;
}
info('Done.');
exit 0;

# ============================================================ subroutines

sub info { print "$_[0]\n" unless $opt{quiet} }

sub iso_now { return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(time)) }

sub version_of {
    my ($entry) = @_;
    return ref $entry->{latest} eq 'HASH' ? ($entry->{latest}{version} // 'unknown') : 'unknown';
}

sub usage {
    print <<'USAGE';
usage: perl PwEvevee/build-system/release/update-releases.pl [options]

  --out PATH         output file            (default website/data/releases.json)
  --projects PATH    project data model     (default website/data/projects.json)
  --history N        releases kept per project for the history page (default 12)
  --verify-assets    HEAD-check every asset download URL
  --strict           exit non-zero if any project did not update cleanly
  --offline          do not call GitHub; revalidate and rewrite existing data
  --quiet            print warnings and errors only

Set GITHUB_TOKEN to raise the API rate limit. The token is never written to the
generated data and never reaches the browser.
USAGE
}

# Reduce a GitHub release object to exactly the fields the site uses.
sub normalise_release {
    my ($r, $nwo, $strict) = @_;

    my @assets;
    for my $a (@{ ref $r->{assets} eq 'ARRAY' ? $r->{assets} : [] }) {
        next unless ref $a eq 'HASH' && defined $a->{name};
        my $url = $a->{browser_download_url};
        unless (is_safe_url($url)
                && $url =~ m{^https://(?:github\.com|[a-z0-9.-]+\.githubusercontent\.com)/}) {
            warn "!! $nwo: asset '$a->{name}' has an unexpected download URL; skipped\n";
            next;
        }
        my ($sha256) = ($a->{digest} // '') =~ /^sha256:([0-9a-f]{64})$/i;
        my $art = parse_artifact($a->{name});
        push @assets, {
            name           => $a->{name},
            size           => ($a->{size} // 0) + 0,
            size_label     => fmt_bytes($a->{size}),
            content_type   => $a->{content_type} // 'application/octet-stream',
            download_url   => $url,
            kind           => asset_kind($a->{name}),
            sha256         => $sha256,
            # GitHub counts one download per asset fetch. Kept so the website's
            # download aggregates (update-stats.pl) are computed from the same
            # source of truth rather than fetched a second time.
            download_count => ($a->{download_count} // 0) + 0,
            updated_at     => $a->{updated_at},
            pweevee_artifact => $art->{ok} ? $TRUE : $FALSE,
            ($art->{ok} ? (artifact_channel => $art->{channel}, artifact_version => $art->{version}) : ()),
        };
    }

    # Primary first: valid PwEevee artifacts, then other installable packages,
    # then archives and extras. The 3.1.0 bug was exactly this sort: two IPAs,
    # alphabetical order, and the Spotify base ("com.spotify...") won.
    my %rank = (ipa => 0, tipa => 1, deb => 2, archive => 3, other => 4);
    @assets = sort {
        my $pa = parse_artifact($a->{name});
        my $pb = parse_artifact($b->{name});
        (($pa->{ok} ? 0 : 1) <=> ($pb->{ok} ? 0 : 1))
            || ($rank{ $a->{kind} } // 4) <=> ($rank{ $b->{kind} } // 4)
            || lc($a->{name}) cmp lc($b->{name})
    } @assets;

    my $tag  = $r->{tag_name} // '';
    my $body = $r->{body};
    my $channel = release_channel($tag, $r->{prerelease} ? 1 : 0);
    # Strict PwEevee selection: the release channel decides which asset may be
    # the download. No match means no download, never "the first .ipa".
    my $download = $strict
        ? pick_artifact(\@assets, $channel, ($tag =~ s/^v//r))
        : undef;
    my $missing  = $strict && $channel ne 'prerelease' && !$download;

    return {
        version         => $tag,
        channel         => $channel,
        download_asset  => $download,
        artifact_missing => $missing ? $TRUE : $FALSE,
        # Only a bare semver-looking tag gets a "v" for display. Tags such as
        # "swift6.2.2" are shown exactly as the upstream project published them.
        version_label   => (length $tag ? ($tag =~ /^\d/ ? "v$tag" : $tag) : 'unknown'),
        name            => (defined $r->{name} && $r->{name} =~ /\S/) ? $r->{name} : $tag,
        published_at    => $r->{published_at},
        published_label => fmt_date($r->{published_at}),
        published_epoch => date_epoch($r->{published_at}),
        url             => (is_safe_url($r->{html_url} // '') ? $r->{html_url}
                                                              : "https://github.com/$nwo/releases"),
        prerelease      => $r->{prerelease} ? $TRUE : $FALSE,
        notes           => (defined $body && $body =~ /\S/) ? $body : undef,
        summary         => text_excerpt($body, 190),
        assets          => \@assets,
        asset_count     => scalar @assets,
        author          => (ref $r->{author} eq 'HASH' && $r->{author}{login}) ? $r->{author}{login} : undef,
    };
}

sub asset_kind {
    my ($name) = @_;
    return 'other'   unless defined $name;
    return 'ipa'     if $name =~ /\.ipa$/i;
    return 'tipa'    if $name =~ /\.tipa$/i;
    return 'deb'     if $name =~ /\.deb$/i;
    return 'archive' if $name =~ /\.(?:zip|tgz|xz|gz|tar)$/i;
    return 'other';
}

sub unavailable_entry {
    my ($p, $reason) = @_;
    my $gh  = ref $p->{github} eq 'HASH' ? $p->{github} : {};
    my $nwo = ($gh->{owner} && $gh->{repo}) ? "$gh->{owner}/$gh->{repo}" : undef;
    return {
        slug         => $p->{slug},
        name         => $p->{name} // $p->{slug},
        repo         => $nwo,
        repo_url     => $nwo ? "https://github.com/$nwo" : undef,
        issues_url   => $nwo ? "https://github.com/$nwo/issues" : undef,
        releases_url => $nwo ? "https://github.com/$nwo/releases" : undef,
        available    => $FALSE,
        stale        => $FALSE,
        error        => $reason,
        latest       => undef,
        history      => [],
    };
}

# ---------------------------------------------------------------- HTTP
#
# The client itself lives in lib/PwHttp.pm so that update-releases.pl and
# update-altsource.pl share one implementation. Everything below is the GitHub
# API contract: what a good response looks like, and what each failure means in
# words a visitor could read.

# GET /repos/:nwo/releases — returns (arrayref, undef) or (undef, message).
sub api_releases {
    my ($nwo) = @_;
    my $per_page = $opt{history} > 30 ? 100 : 30;
    my ($code, $raw) = http_get("$API/repos/$nwo/releases?per_page=$per_page",
        headers => [ 'Accept: application/vnd.github+json',
                     'X-GitHub-Api-Version: 2022-11-28' ],
        ($TOKEN ? (token => $TOKEN) : ()),
    );

    return (undef, 'network error: api.github.com could not be reached.') unless defined $code;
    return (undef, 'GitHub returned 404 — the repository does not exist or is not public.')
        if $code == 404;
    return (undef, 'GitHub returned 451 (unavailable for legal reasons) — this repository has been disabled.')
        if $code == 451;
    if ($code == 403 || $code == 429) {
        my $hint = $TOKEN ? '' : ' Set GITHUB_TOKEN to raise the anonymous limit of 60 requests/hour.';
        return (undef, "GitHub returned $code — rate limited or access denied.$hint");
    }
    return (undef, "GitHub returned HTTP $code.") if $code != 200;
    return (undef, 'GitHub returned an empty response body.') unless defined $raw && length $raw;

    my $data = eval { JSON::PP->new->utf8->decode($raw) };
    return (undef, 'GitHub returned a response that is not valid JSON.') unless defined $data;
    return (undef, 'GitHub API error: ' . ($data->{message} // 'unknown error'))
        if ref $data eq 'HASH';
    return (undef, 'GitHub returned an unexpected payload (a list of releases was expected).')
        unless ref $data eq 'ARRAY';
    for my $r (@$data) {
        return (undef, 'GitHub returned a release object without a tag_name.')
            unless ref $r eq 'HASH' && defined $r->{tag_name};
    }
    return ($data, undef);
}
