#!/usr/bin/env perl
# ============================================================================
# update-stats.pl — generate website/data/stats.json from the GitHub API
# ============================================================================
#
#   perl PwEevee/build-system/release/update-stats.pl [options]
#   scripts/update-stats.sh                   (same thing, one command)
#
# Like update-releases.pl this script trusts website/data/projects.json as the
# single declaration of every repository, talks to the network only through
# PwHttp, validates response shapes, writes atomically, and never destroys
# previously generated data when GitHub is unreachable or rate-limited.
#
# Metric definitions (documented here because they end up on the website):
#   stars      -> stargazers_count    GitHub repository stars.
#   forks      -> forks_count         GitHub repository forks.
#   watchers   -> subscribers_count   Actual repository watchers/watch
#                                     subscribers. GitHub's REST /repos endpoint
#                                     also returns watchers_count, but that
#                                     field is documented to equal
#                                     stargazers_count — it is NOT the watch
#                                     list. The site therefore labels
#                                     subscribers_count as "Watchers" and never
#                                     uses watchers_count.
#   issues     -> open_issues_count   Open issues AND pull requests combined
#                                     (GitHub counts PRs here). The site labels
#                                     it "Open issues & PRs".
#   downloads  -> per-asset download_count summed over the releases tracked in
#                                     website/data/releases.json. The site
#                                     presents the aggregate as the "total of
#                                     available GitHub release assets", never
#                                     as unique users or installs.
#                                     repo-level verified_total_download -> GitHub's
#                                     own release-download count for the WHOLE
#                                     repository (every release, tracked or not),
#                                     read from
#                                     img.shields.io/github/downloads/<nwo>/total.json
#                                     — the exact figure shields.io badges show.
#                                     This is what a single repository's own
#                                     stats band leads with; the cross-project
#                                     aggregate is a different, clearly
#                                     labelled number.
#
# Conditional requests: the stored ETag per repository is sent as
# If-None-Match; a 304 keeps the stored numbers untouched. An etag is stored
# only when the server actually sent one — never fabricated. That keeps the
# anonymous rate budget (60/h) safe for the 15-minute cadence (conditional GETs are 304s that do not burn the anonymous core budget).
#
# Options (same shape as update-releases.pl):
#   --out PATH        output file (default website/data/stats.json)
#   --releases PATH   release data used for download aggregation
#                     (default website/data/releases.json)
#   --projects PATH   project data model (default website/data/projects.json)
#   --strict          exit non-zero if any project did not update cleanly
#   --offline         do not call GitHub; revalidate and rewrite existing data
#   --quiet           print warnings and errors only
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin ();
use lib "$FindBin::Bin/lib";
use JSON::PP ();
use POSIX qw(strftime);
use PwSite qw(repo_root read_json write_json date_epoch is_safe_url);
use PwHttp qw(http_init http_get http_cleanup);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# STATS_API_BASE is a test seam, not a configuration knob: the website test
# suite points it at a local 127.0.0.1 mock so update-stats' real data flow is
# exercised deterministically and offline. It is never set in production.
my $API = $ENV{STATS_API_BASE} || 'https://api.github.com';

# Same discipline for the per-repository download total: STATS_SHIELDS_BASE
# is a test seam so the total fetch runs against the same loopback mock.
my $SHIELDS = $ENV{STATS_SHIELDS_BASE} || 'https://img.shields.io';

my %opt = (
    out      => 'website/data/stats.json',
    releases => 'website/data/releases.json',
    projects => 'website/data/projects.json',
);
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '--out')      { $opt{out}      = shift @ARGV }
    elsif ($a eq '--releases') { $opt{releases} = shift @ARGV }
    elsif ($a eq '--projects') { $opt{projects} = shift @ARGV }
    elsif ($a eq '--strict')   { $opt{strict}   = 1 }
    elsif ($a eq '--offline')  { $opt{offline}  = 1 }
    elsif ($a eq '--quiet')    { $opt{quiet}    = 1 }
    elsif ($a eq '-h' || $a eq '--help') { usage(); exit 0 }
    else  { die "unknown option: $a (try --help)\n" }
}

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $TOKEN = $ENV{GITHUB_TOKEN} || $ENV{GH_TOKEN} || '';
my $HTTP  = $opt{offline} ? 'none'
          : http_init(tmp_dir => 'PwEvevee/build-system/_work/net',
                      user_agent => 'PwEevee-stats-updater');
END { http_cleanup() }

warn "!! GITHUB_TOKEN is set but wget is the only client available; the token\n"
   . "   would be visible in the process list, so it will NOT be used.\n"
    if $TOKEN && $HTTP eq 'wget';

# ---------------------------------------------------------------- inputs

-f $opt{projects} or die "missing project data model: $opt{projects}\n";
my $model = read_json($opt{projects});
ref $model eq 'HASH' && ref $model->{projects} eq 'ARRAY'
    or die "$opt{projects}: expected an object with a 'projects' array\n";

# Download aggregation is computed from the release data this repository
# already generates (update-releases.pl). Missing release data degrades the
# aggregate to an explicit unavailable state, never to a fabricated number.
my $rel = eval { read_json($opt{releases}) } || { projects => [] };
my %REL = map { $_->{slug} => $_ } grep { $_->{slug} } @{ $rel->{projects} || [] };

my %prev_by_slug;
if (-f $opt{out}) {
    my $previous = eval { read_json($opt{out}) };
    if (ref $previous eq 'HASH' && ref $previous->{repos} eq 'ARRAY') {
        %prev_by_slug = map { $_->{slug} => $_ }
                        grep { $_->{slug} } @{ $previous->{repos} };
    } else {
        warn "!! existing $opt{out} could not be parsed; it will be regenerated\n";
    }
}

# ---------------------------------------------------------------- fetch loop

my (@out, @failed, @stale, @unchanged);

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

    if ($opt{offline}) {
        if (my $keep = $prev_by_slug{$slug}) {
            info("$name: offline — keeping existing stats");
            push @out, $keep;
        } else {
            warn "!! $name: offline mode and no previously generated stats\n";
            push @out, unavailable_entry($p, 'Offline mode and no previously generated data.');
            push @failed, $name;
        }
        next;
    }

    my $prev_etag = ref $prev_by_slug{$slug} eq 'HASH' ? ($prev_by_slug{$slug}{etag} // '') : '';
    my ($code, $body, $headers, $err) = api_repo($nwo, $prev_etag);

    if ($err) {
        warn "!! $name: $err\n";
    }
    elsif ($code == 304) {
        # Not modified under If-None-Match: the stored numbers are still
        # current. The previous record is kept verbatim (etag included).
        # Exception: the download total is a separate resource the repo ETag
        # never covered, so it is re-verified on every successful run; if the
        # read fails, the stored value survives unperturbed.
        my $keep = $prev_by_slug{$slug};
        if ($keep) {
            info("$name: 304 Not Modified — keeping stored stats");
            # GitHub just vouched the stored numbers are current: an earlier
            # network-failure staleness is cleared on the spot.
            delete $keep->{stale};
            delete $keep->{stale_since};
            delete $keep->{error};
            if (defined(my $total = fetch_shields_total($nwo))) {
                $keep->{downloads_total} = 0 + $total;
            }
            push @out, fetchable_copy($keep, $nwo, $keep->{etag} // '');
            push @unchanged, $name;
            next;
        }
        $err = 'GitHub reported 304 Not Modified but no previous stats exist.';
    }
    elsif ($code !~ /^2\d\d$/) {
        # 403 = rate limit or blocked, 404 = repo moved/removed, 5xx = GitHub down.
        if ($code == 403 || $code == 429) {
            $err = 'GitHub API rate limit or access restriction (HTTP ' . ($code // 'none') . ').';
        }
        elsif ($code == 404) {
            $err = "Repository https://github.com/$nwo was not found (HTTP 404).";
        }
        else {
            $err = 'Unexpected GitHub API response (HTTP ' . ($code // 'none') . ').';
        }
    }
    else {
        $err = validate_repo_shape($body);
        unless ($err) {
            my $repo = JSON::PP::decode_json($body);
            # Store an etag ONLY when one actually arrived (never a fabricated
            # value); it enables the 304 fast path on the next run.
            my $etag = ref $headers eq 'HASH' ? ($headers->{etag} // '') : '';
            # GitHub's release-download total for the whole repository. A
            # failed read here must not cost the record its stars: fall back
            # to this repository's previous verified total, and only omit the
            # field entirely when no previous value exists either.
            my $total = fetch_shields_total($nwo);
            if (!defined $total) {
                $total = $prev_by_slug{$slug}{downloads_total} // undef;
                warn "!! $name: the GitHub release-download total could not be read"
                   . (defined $total
                        ? '; keeping the value verified on ' . ($prev_by_slug{$slug}{fetched_at} // '?') . "\n"
                        : "; nothing previous to keep\n");
            }
            push @out, normalise_repo($p, $nwo, $repo, $etag, $total);
            info("$name: stars " . ($repo->{stargazers_count} // 0)
                 . " \x{b7} forks " . ($repo->{forks_count} // 0)
                 . " \x{b7} watchers " . ($repo->{subscribers_count} // 0)
                 . (defined $total
                      ? " \x{b7} downloads " . (0 + $total)
                      : " \x{b7} downloads unavailable this run")
                 . " \x{b7} pushed " . ($repo->{pushed_at} // 'unknown'));
            next;
        }
    }

    # --- failure path: never destroy good data -----------------------------
    if (my $keep = $prev_by_slug{$slug}) {
        my %copy = %{ fetchable_copy($keep, $nwo, $keep->{etag} // '') };
        $copy{stale}       = JSON::PP::true;
        $copy{stale_since} = iso_now();
        $copy{error}       = $err;
        info("$name: keeping the previous known-good stats (fetched "
             . ($keep->{fetched_at} // '?') . ')');
        push @out, \%copy;
        push @stale, $name;
    } else {
        warn "!! $name: $err\n" if length($err // '');
        push @out, unavailable_entry($p, $err);
        push @failed, $name;
    }
}

# attach download aggregates (computed from release data, offline, zero fetches)
my $downloads = download_aggregates();

write_json($opt{out}, {
    schema       => 1,
    generated_at => iso_now(),
    generator    => 'PwEevee/build-system/release/update-stats.pl',
    source       => 'GitHub REST API (api.github.com) — public repository and release data only; per-repo release-download totals via img.shields.io (public badge relay of GitHub counts)',
    metric_notes => {
        stars       => 'stargazers_count',
        forks       => 'forks_count',
        watchers    => 'subscribers_count (NOT watchers_count, which GitHub documents as equal to stars)',
        open_issues => 'open_issues_count (includes pull requests)',
        downloads   => 'sum of per-asset download_count over the release history tracked in website/data/releases.json (across all projects)',
        downloads_total => 'GitHub release-download count summed over EVERY release of that one repository — the exact figure shields.io badges display; verified when the repo was last fetched, carried over between runs, and omitted rather than zeroed when never verified',
    },
    downloads => $downloads,
    repos     => \@out,
});

my $fresh = grep { $_->{available} && !$_->{stale} } @out;

info('');
printf "Generated %s — %d of %d project%s %s.\n",
    $opt{out}, $fresh, scalar @out, (@out == 1 ? '' : 's'),
    ($opt{offline} ? 'reused from existing data (offline, nothing was fetched)' : 'fetched fresh');
printf "Unmodified (HTTP 304): %s\n", join(', ', @unchanged) if @unchanged;
printf "Kept previous known-good data for: %s\n", join(', ', @stale) if @stale;
if (@failed) {
    printf "No stats available for: %s\n", join(', ', @failed);
    print  "The site renders an explanatory state for these instead of fabricated zeroes.\n";
}

if (!$fresh && !@stale && !@unchanged) {
    print STDERR "\n!! FAIL: no stats could be retrieved for any project, and there was\n"
               . "   no previous data to fall back on.\n";
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

sub usage {
    print <<'USAGE';
usage: update-stats.pl [--out PATH] [--releases PATH] [--projects PATH]
                       [--strict] [--offline] [--quiet]
Generates website/data/stats.json: GitHub repository stats (stars, forks,
watchers via subscribers_count, open issues, last push) plus download
aggregates computed from the tracked release history. Failures keep the
previous known-good data and mark it stale instead of writing zeroes.
USAGE
}

# One conditional GET per repository. $etag keeps unchanged repositories cheap;
# GitHub documents If-None-Match support on the plain /repos endpoint.
sub api_repo {
    my ($nwo, $etag) = @_;
    my ($status, $body, $headers) = http_get(
        "$API/repos/$nwo",
        headers      => [ 'Accept: application/vnd.github+json',
                          'X-GitHub-Api-Version: 2022-11-28',
                          ($etag ? ("If-None-Match: $etag") : ()) ],
        with_headers => 1,
        token        => ($TOKEN && $HTTP eq 'curl') ? $TOKEN : undef,
    );
    # http_get returns (undef, ...) when the client itself failed to run.
    unless (defined $status) {
        return (undef, '', {}, 'GitHub could not be reached (network or client failure).');
    }
    my $clean = ($status // 0) + 0;
    return ($clean, $body, $headers // {}, '');
}

sub validate_repo_shape {
    my ($body) = @_;
    return 'Empty response body from GitHub.' unless defined $body && length $body;
    my $d = eval { JSON::PP::decode_json($body) };
    return 'GitHub response was not valid JSON.' unless ref $d eq 'HASH';
    for my $f (qw(stargazers_count forks_count open_issues_count)) {
        return "GitHub response missing required field '$f'."
            unless defined $d->{$f} && $d->{$f} =~ /^\d+$/;
    }
    return '';
}

# Keep every stored detail, refreshing only identity/etag bookkeeping.
# fetched_at always describes the last time real numbers were verified.
sub fetchable_copy {
    my ($keep, $nwo, $etag) = @_;
    return undef unless ref $keep eq 'HASH';
    my %copy = %$keep;
    $copy{repo_url} = "https://github.com/$nwo";
    $copy{repo}     = $copy{repo} || $nwo;
    $copy{etag}     = length $etag ? $etag : ($keep->{etag} // '');
    $copy{fetched_at} //= iso_now();
    return \%copy;
}

sub normalise_repo {
    my ($p, $nwo, $repo, $etag, $total) = @_;
    my $url  = "https://github.com/$nwo";
    my $home = $repo->{homepage};
    my %rec = (
        slug         => $p->{slug},
        name         => ($p->{name} // $p->{slug}),
        repo         => $nwo,
        repo_url     => is_safe_url($url) ? $url : '',
        available    => JSON::PP::true,
        stale        => JSON::PP::false,
        stars        => 0 + ($repo->{stargazers_count} // 0),
        forks        => 0 + ($repo->{forks_count} // 0),
        subscribers  => (defined $repo->{subscribers_count} && $repo->{subscribers_count} =~ /^\d+$/)
                      ? 0 + $repo->{subscribers_count} : 0,
        open_issues  => 0 + ($repo->{open_issues_count} // 0),
        pushed_at    => ($repo->{pushed_at} // ''),
        homepage     => (defined $home && length $home && is_safe_url($home)) ? $home : '',
        topics       => [ map { "$_" } @{ $repo->{topics} || [] } ],
        etag         => $etag,
        fetched_at   => iso_now(),
    );
    # Only a verified number from this run or an inherited previous one is
    # stored: an omitted field means the renderer may say it differently,
    # never that a zero was observed.
    $rec{downloads_total} = 0 + $total if defined $total;
    return \%rec;
}

# GitHub's own release-download count for the whole repository, served exactly
# as shields.io serves it:
#
#   <SHIELDS>/github/downloads/<nwo>/total.json
#   -> {"schemaVersion":1,"label":"downloads","value":"658"}
#
# The value is the same number those public badges display: GitHub adds up the
# asset download_count of EVERY release of the repository, not just the ones
# the tracked release history still holds. Only plain numeric values are
# accepted (with the k/M badge suffix expanded); anything else, any HTTP error
# and any network failure means "no number this run" — undef, never a guess.
sub fetch_shields_total {
    my ($nwo) = @_;
    return undef unless length($nwo // '') && $nwo =~ m{^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\z};
    my ($status, $body, $err) = http_get(
        "$SHIELDS/github/downloads/$nwo/total.json",
        headers => [ 'Accept: application/json' ],
    );
    return undef unless defined $status && ($status // 0) == 200 && defined $body;
    my $d = eval { JSON::PP::decode_json($body) };
    return undef unless ref $d eq 'HASH' && defined $d->{value} && defined $d->{message};
    my $v = $d->{value};
    $v =~ s/^\s+|\s+$//g;
    if    ($v =~ /^(\d+)\z$/)                       { return 0 + $1 }
    elsif ($v =~ /^(\d+(?:\.\d+)?)([kM])\z$/) {   # badges may compact large counts
        my ($num, $unit) = (0 + $1, lc $2);
        return int($num * ($unit eq 'k' ? 1_000 : 1_000_000) + 0.5);
    }
    warn "!! shields total for $nwo returned '$v' — not a plain download count\n";
    return undef;
}


sub unavailable_entry {
    my ($p, $why) = @_;
    return {
        slug        => $p->{slug},
        name        => ($p->{name} // $p->{slug}),
        repo        => '',
        repo_url    => '',
        available   => JSON::PP::false,
        stale       => JSON::PP::false,
        stars       => 0,
        forks       => 0,
        subscribers => 0,
        open_issues => 0,
        error       => $why,
        fetched_at  => iso_now(),
    };
}

# Download aggregates come from the tracked release history (update-releases.pl
# keeps up to --history releases per project). Each asset contributes its own
# download_count; the aggregate is the total of AVAILABLE GitHub release
# assets — the site never presents it as unique users or installs.
sub download_aggregates {
    my %per_project;
    my $grand = 0;
    for my $slug (sort keys %REL) {
        my $rp     = $REL{$slug};
        my $sum    = 0;
        my $rel_n  = 0;
        my $latest = undef;
        my %seen;          # distinct releases actually summed, keyed by tag

        if (ref $rp eq 'HASH') {
            if (ref $rp->{latest} eq 'HASH') {
                $rel_n++;
                if (ref $rp->{latest}{assets} eq 'ARRAY') {
                    my @assets;
                    for my $a (@{ $rp->{latest}{assets} }) {
                        next unless ref $a eq 'HASH';
                        my $n = ($a->{download_count} // 0) + 0;
                        $sum += $n;
                        push @assets, { name => ($a->{name} // ''), download_count => $n };
                    }
                    $latest = {
                        version         => ($rp->{latest}{version} // ''),
                        asset_downloads => \@assets,
                        downloads       => (my $lsum = 0),
                    };
                    $latest->{downloads} += $_->{download_count} // 0 for @assets;
                    $seen{ $latest->{version} } = 1 if length ($latest->{version} // '');
                }
            }
            if (ref $rp->{history} eq 'ARRAY') {
                for my $h (@{ $rp->{history} }) {
                    # update-releases.pl emits history entries with 'version'
                    # (normalise_release), not the raw GitHub 'tag_name';
                    # accept either key so no release is silently skipped.
                    my $tag = $h->{tag_name} // $h->{version} or next;
                    # update-releases.pl keeps the latest release as history[0],
                    # so skip it in the history pass — otherwise every asset of
                    # the newest release would be counted twice.
                    next if $latest && $tag eq $latest->{version};
                    $rel_n++;
                    $seen{$tag} = 1;
                    next unless ref $h->{assets} eq 'ARRAY';
                    $sum += ($_->{download_count} // 0) + 0 for @{ $h->{assets} };
                }
            }
        }

        $per_project{$slug} = {
            releases_summed   => (scalar keys %seen) || $rel_n,
            release_downloads => $sum,
            ($latest ? (latest => $latest) : ()),
        };
        $grand += $sum;
    }
    return {
        aggregate_label => 'total of available GitHub release asset download_count sums (not unique users or installs)',
        total           => $grand,
        per_project     => \%per_project,
        release_data_generated_at => ($rel->{generated_at} // ''),
        release_data_found => (scalar keys %REL) + 0,
    };
}

__END__

# The download-aggregate structure lives at the top level (not per repo) since
# it is derived from release data, not from the repository API. render-site.pl
# reads stats.json passively and decides itself what to render.
