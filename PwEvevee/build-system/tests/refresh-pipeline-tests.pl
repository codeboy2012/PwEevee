#!/usr/bin/env perl
# ============================================================================
# refresh-pipeline-tests.pl — the release-refresh contract, deterministically
# ============================================================================
#
#   perl PwEvevee/build-system/tests/refresh-pipeline-tests.pl
#
# Every test here answers a question that the live site has actually got wrong
# at least once, or that the refresh cycle depends on being true:
#
#   A. release discovery (update-releases.pl against a mocked GitHub API)
#      — a newer published stable release wins, including a bare `3.1.0` tag
#        with no `v` prefix, which the site once kept rendering as v2.0.0;
#      — a newer prerelease never displaces a stable release;
#      — a draft is never considered;
#      — a release with no assets renders as such instead of breaking;
#      — an API failure (rate limit, 5xx, malformed, incomplete) keeps the
#        previous known-good release and says why, and never invents one.
#
#   B. change detection (data-digest.pl)
#      — refresh timestamps are volatility, not content, so two runs over the
#        same facts have the same digest (this is what stops a commit and a
#        re-publish every fifteen minutes);
#      — a visible change always moves the digest.
#
#   C. the cycle end to end (scripts/refresh-site.sh)
#      — a stale committed snapshot is refreshed and published, and the live
#        document root then serves the release GitHub reports;
#      — a second run with the same upstream data publishes nothing;
#      — a validation failure publishes nothing and leaves the live site
#        byte-identical (the release updater can succeed and the site still
#        not move);
#      — the published artifact is the rendered one, and the previous site is
#        backed up before the swap.
#
# No test depends on live GitHub. Mock responses are served from a loopback
# server, and the pipeline's own PWEEVEE_ROOT / RELEASES_API_BASE /
# STATS_API_BASE seams are used exactly as they are meant to be: the isolation
# happens in the data paths, never in the logic under test.
# ============================================================================
use strict;
use warnings;
use utf8;
use File::Basename qw(dirname);
use File::Find ();
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use JSON::PP ();
use Digest::SHA qw(sha256_hex);

binmode STDOUT, ':encoding(UTF-8)';

my $ROOT = dirname($0) . '/../../..';
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $FIX = "$ROOT/PwEvevee/build-system/_work/refresh-pipeline-fixtures";
remove_tree($FIX) if -d $FIX;
make_path($FIX);

my (@failures, $pass);
$pass = 0;
sub ok {
    my ($cond, $what, $detail) = @_;
    if ($cond) { $pass++; return 1 }
    push @failures, defined $detail && length $detail ? "$what — $detail" : $what;
    return 0;
}
sub section { print "\n$_[0]\n" }
sub note    { print "    note: $_[0]\n" }

sub slurp { my ($p) = @_; open(my $f, '<:raw', $p) or return undef; local $/; my $d = <$f>; close $f; return $d }
sub spew  { my ($p, $d) = @_; make_path(dirname($p)); open(my $f, '>:raw', $p) or die "write $p: $!\n"; print {$f} $d; close $f }
sub read_json  { my $d = slurp($_[0]); return undef unless defined $d; return eval { JSON::PP->new->utf8->decode($d) } }
sub write_json { spew($_[0], JSON::PP->new->utf8->canonical->pretty->encode($_[1])) }

# ---------------------------------------------------------------- mock GitHub
#
# One loopback server for the whole suite. It answers from files, so a test can
# change what GitHub "says" between runs without restarting anything:
#
#   $FIX/api/releases.json   the release list (valid payload)
#   $FIX/api/repo.json       the repository object (for update-stats.pl)
#   $FIX/api/mode            '' | 403 | 500 | 429 | malformed | incomplete | tagless
#
my $SERVER_SRC = <<'SERVER_SRC';
use strict;
use warnings;
use IO::Socket::INET;
my $dir = $ARGV[0];
my $srv = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 16, ReuseAddr => 1,
) or die "mock listen: $!";
open(my $pf, '>', "$dir/port.txt") or die "port.txt: $!";
print {$pf} $srv->sockport;
close $pf;

sub slurp { my ($p) = @_; open(my $f, '<:raw', $p) or return undef; local $/; my $d = <$f>; close $f; return $d }

while (my $c = $srv->accept) {
    my $request = '';
    while (defined(my $line = <$c>)) { $request .= $line; last if $line =~ /^\r?$/ }
    my ($path) = $request =~ m{^\S+\s+(\S+)};
    $path //= '';

    open(my $lf, '>>', "$dir/requests.log");
    print {$lf} $request;
    close $lf;

    chomp(my $mode = slurp("$dir/mode") // '');
    my ($status, $body) = (200, '{}');

    if    ($mode eq '403')    { $status = 403; $body = '{"message":"API rate limit exceeded for 1.2.3.4."}' }
    elsif ($mode eq '429')    { $status = 429; $body = '{"message":"Too many requests"}' }
    elsif ($mode eq '500')    { $status = 500; $body = '{"message":"Server Error"}' }
    elsif ($mode eq 'malformed') { $body = '{"oops": not-json' }
    elsif ($mode eq 'incomplete') { $body = '[{"name":"a release with no tag_name"}]' }
    elsif ($mode eq 'tagless') { $body = '[{"tag_name":"9.9.9"},{"name":"no tag"}]' }
    elsif ($path =~ m{/releases}) { $body = slurp("$dir/releases.json") // '[]' }
    elsif ($path =~ m{/total\.json}) { $body = '{"value":4242,"label":"downloads"}' }
    else { $body = slurp("$dir/repo.json") // '{}' }

    print {$c} "HTTP/1.0 $status Mock\r\n"
            . "Content-Type: application/json\r\n"
            . 'Content-Length: ' . length($body) . "\r\n\r\n";
    print {$c} $body unless $status == 304;
    close $c;
}
exit 0;
SERVER_SRC

make_path("$FIX/api");
spew("$FIX/api/releases.json", "[]\n");
spew("$FIX/api/mode", "\n");
write_json("$FIX/api/repo.json", {
    name => 'pweevee', full_name => 'mock-org/pweevee',
    stargazers_count => 41, forks_count => 3, subscribers_count => 5,
    open_issues_count => 2, pushed_at => '2026-10-27T20:00:00Z',
    html_url => 'https://github.com/mock-org/pweevee',
});
spew("$FIX/server.pl", $SERVER_SRC);

my $server_pid = fork();
defined $server_pid or die "cannot fork the mock server: $!\n";
if (!$server_pid) { exec 'perl', "$FIX/server.pl", "$FIX/api" or die "exec mock: $!\n" }

my $PORT = '';
for (1 .. 200) {
    if (open my $pf, '<', "$FIX/api/port.txt") { $PORT = <$pf> // ''; close $pf; chomp $PORT; last if $PORT =~ /^\d+$/ }
    select undef, undef, undef, 0.05;
}
die "the mock GitHub server did not come up\n" unless $PORT =~ /^\d+$/;
my $BASE = "http://127.0.0.1:$PORT";
END { kill 'TERM', $server_pid if $server_pid }

# ---------------------------------------------------------------- fixtures

my $NWO = 'mock-org/pweevee';

sub release {
    my (%a) = @_;
    my $tag = $a{tag} or die "release needs a tag\n";
    my $rel = {
        tag_name     => $tag,
        name         => $a{name} // "Release $tag",
        draft        => $a{draft} ? JSON::PP::true : JSON::PP::false,
        prerelease   => $a{prerelease} ? JSON::PP::true : JSON::PP::false,
        published_at => $a{published} // '2026-01-01T00:00:00Z',
        html_url     => "https://github.com/$NWO/releases/tag/$tag",
        body         => $a{body} // "Notes for $tag.",
        author       => { login => 'mock-author' },
        assets       => $a{assets} // [ {
            name => "PwEevee-$tag.ipa", size => 147039801,
            content_type => 'application/x-itunes-ipa',
            browser_download_url => "https://github.com/$NWO/releases/download/$tag/PwEevee-$tag.ipa",
            download_count => 7, updated_at => '2026-01-01T00:00:00Z',
            digest => 'sha256:' . ('ab' x 32),
        } ],
    };
    $rel->{assets} = [] if $a{no_assets};
    delete $rel->{published_at} if $a{no_date};
    return $rel;
}
sub serve_releases { write_json("$FIX/api/releases.json", [ @_ ]) }

my $PROJECTS = {
    projects => [ {
        slug => 'pweevee', name => 'PwEevee',
        github => { owner => 'mock-org', repo => 'pweevee', available => JSON::PP::true },
    } ],
};
write_json("$FIX/projects.json", $PROJECTS);

# The committed snapshot the site was actually serving: v2.0.0 as "latest".
my $PREVIOUS = {
    schema => 1, generated_at => '2026-10-26T20:53:19Z',
    projects => [ {
        slug => 'pweevee', name => 'PwEevee', repo => $NWO, available => JSON::PP::true,
        stale => JSON::PP::false,
        latest => { version => 'v2.0.0', version_label => 'v2.0.0', published_at => '2026-10-06T01:48:48Z' },
        history => [], assets => [],
    } ],
};
write_json("$FIX/previous.json", $PREVIOUS);

# Runs the real updater against the mock. One string, never a concatenation:
# a qx{...} . qq{...} would run only the first piece and lose every argument.
my $run_updater = sub {
    my (%a) = @_;
    my $out      = $a{out} or die "run_updater needs out\n";
    # previous => '' models a host with no known-good snapshot at all
    my $previous = defined $a{previous} ? $a{previous} : "$FIX/previous.json";
    my $mode     = $a{mode} // '';
    my $strict   = $a{strict} ? ' --strict' : '';
    spew("$FIX/api/mode", $mode . "\n");
    local $ENV{RELEASES_API_BASE} = $BASE;
    my $cmd = 'perl PwEvevee/build-system/release/update-releases.pl'
            . " --out \"$out\" --projects \"$FIX/projects.json\" --history 12$strict --quiet 2>&1";
    # the previous snapshot has to look like the file the real run reads
    copy($previous, $out) if length($previous // '') && -f $previous && $previous ne $out;
    my $stdout = qx{$cmd};
    my $exit   = $? >> 8;
    spew("$FIX/api/mode", "\n");
    return ($exit, $stdout, $out);
};

# Reads one project (and its latest release) back out of a generated file.
# Written as subroutines rather than `(grep ...)->[0]`: that idiom applies the
# arrow to a single parenthesized term, so it silently means something else the
# moment the grep matches exactly one row.
my $project_of = sub {
    my ($file, $slug) = @_;
    my $d = read_json($file) || {};
    my ($p) = grep { ($_->{slug} // '') eq $slug } @{ $d->{projects} || [] };
    return $p || {};
};
my $latest_of = sub { (($project_of->($_[0], 'pweevee'))->{latest} || {}) };

# ============================================================ A. discovery

section('A. release discovery (update-releases.pl, mocked GitHub API)');

{
    # ---- A1: the reported bug — a bare `3.1.0` tag published after v2.0.0 ----
    serve_releases(
        release(tag => '3.1.0', name => 'PwEevee v3.1.0', published => '2026-10-27T21:44:22Z'),
        release(tag => 'v2.2.0-pre', published => '2026-10-23T19:28:17Z'),
        release(tag => 'v2.0.0', published => '2026-10-06T01:48:48Z'),
    );
    my ($exit, $stdout, $out) = $run_updater->(out => "$FIX/A1.json");
    ok($exit == 0, 'A1 the updater exits 0 on a clean fetch', "exit $exit");
    my $d = read_json($out);
    my ($p) = grep { $_->{slug} eq 'pweevee' } @{ $d->{projects} || [] };
    my $latest = $p->{latest} || {};
    ok(($latest->{version} // '') eq '3.1.0',
       'A1 the newest published stable release wins over the committed v2.0.0',
       'got ' . ($latest->{version} // 'none'));
    ok(($latest->{version_label} // '') eq 'v3.1.0',
       'A1 a bare numeric tag is displayed with a leading v',
       'got ' . ($latest->{version_label} // 'none'));
    ok(($latest->{published_label} // '') eq '27 October 2026',
       'A1 the publication date is the one GitHub reported',
       'got ' . ($latest->{published_label} // 'none'));
    ok(($p->{history}[0]{version} // '') eq '3.1.0', 'A1 history[0] is the same release');
    ok((grep { ($_->{version} // '') eq 'v2.0.0' } @{ $p->{history} || [] }),
       'A1 the superseded release stays in the history rather than vanishing');
    ok(!$p->{stale} && $p->{available}, 'A1 a clean fetch is fresh and available');
    my ($asset) = @{ $latest->{assets} || [] };
    ok(($asset->{sha256} // '') eq ('ab' x 32),
       'A1 the sha256 GitHub publishes for an asset is carried through');
    ok(($asset->{kind} // '') eq 'ipa', 'A1 the asset is classified as an IPA');
    ok($stdout =~ /Latest release: 3\.1\.0/, 'A1 the run reports what it discovered');

    # ---- A2: an even newer stable release ----
    serve_releases(
        release(tag => 'v4.0.0', published => '2026-11-02T09:00:00Z'),
        release(tag => '3.1.0', published => '2026-10-27T21:44:22Z'),
    );
    (my $e2, undef, my $o2) = $run_updater->(out => "$FIX/A2.json");
    my $l2 = $latest_of->($o2);
    ok($e2 == 0 && ($l2->{version} // '') eq 'v4.0.0',
       'A2 a newer stable release becomes the latest',
       'got ' . ($l2->{version} // 'none'));

    # ---- A3: a newer prerelease must not displace the stable release ----
    serve_releases(
        release(tag => 'v9.9.9-rc1', published => '2026-12-01T00:00:00Z', prerelease => 1),
        release(tag => 'v4.0.0', published => '2026-11-02T09:00:00Z'),
        release(tag => '3.1.0', published => '2026-10-27T21:44:22Z'),
    );
    (undef, undef, my $o3) = $run_updater->(out => "$FIX/A3.json");
    my $l3 = $latest_of->($o3);
    ok(($l3->{version} // '') eq 'v4.0.0',
       'A3 a flagged prerelease does not become the latest stable release',
       'got ' . ($l3->{version} // 'none'));

    # a prerelease that is not flagged as one, but says so in its tag
    serve_releases(
        release(tag => '5.0.0-beta', published => '2026-12-05T00:00:00Z'),
        release(tag => 'v4.0.0', published => '2026-11-02T09:00:00Z'),
    );
    (undef, undef, my $o3b) = $run_updater->(out => "$FIX/A3b.json");
    my $l3b = $latest_of->($o3b);
    ok(($l3b->{version} // '') eq 'v4.0.0',
       'A3b a -beta tag with prerelease:false is still not presented as stable',
       'got ' . ($l3b->{version} // 'none'));

    # ---- A4: with no stable release at all, the newest prerelease is shown ----
    serve_releases(
        release(tag => 'v9.9.9-rc1', published => '2026-12-01T00:00:00Z', prerelease => 1),
        release(tag => 'v9.0.0-beta', published => '2026-11-20T00:00:00Z'),
    );
    (undef, undef, my $o4) = $run_updater->(out => "$FIX/A4.json");
    my $l4 = $latest_of->($o4);
    ok(($l4->{version} // '') eq 'v9.9.9-rc1' && $l4->{prerelease},
       'A4 a repository with only prereleases presents the newest one, flagged',
       'got ' . ($l4->{version} // 'none'));

    # ---- A5: drafts are never considered ----
    serve_releases(
        release(tag => 'v5.0.0', published => '2026-12-10T00:00:00Z', draft => 1),
        release(tag => 'v4.0.0', published => '2026-11-02T09:00:00Z'),
    );
    (undef, undef, my $o5) = $run_updater->(out => "$FIX/A5.json");
    my $l5 = $latest_of->($o5);
    ok(($l5->{version} // '') eq 'v4.0.0', 'A5 a draft release is never the latest',
       'got ' . ($l5->{version} // 'none'));

    # ---- A6: a release with no downloadable assets ----
    serve_releases(release(tag => 'v4.0.1', published => '2026-11-03T00:00:00Z', no_assets => 1));
    (my $e6, undef, my $o6) = $run_updater->(out => "$FIX/A6.json");
    my $p6 = $project_of->($o6, 'pweevee');
    ok($e6 == 0 && ($p6->{latest}{asset_count} // -1) == 0,
       'A6 a release carrying no assets is published as such, not as a failure',
       'exit ' . $e6 . ', asset_count ' . ($p6->{latest}{asset_count} // 'missing'));
}

# ---- A7-A10: failures keep the previous known-good release ---------------

for my $case (
    [ '403',        'A7',  qr/rate limited/i ],
    [ '429',        'A7b', qr/rate limited/i ],
    [ '500',        'A8',  qr/HTTP 500/ ],
    [ 'malformed',  'A9',  qr/not valid JSON/i ],
    [ 'incomplete', 'A10', qr/tag_name/i ],
) {
    my ($mode, $id, $expect) = @$case;
    serve_releases(release(tag => 'v2.0.0', published => '2026-10-06T01:48:48Z'));
    my ($exit, $stdout, $out) = $run_updater->(out => "$FIX/$id.json", mode => $mode);
    my $p = $project_of->($out, 'pweevee');
    ok($exit == 0, "$id an unreachable or broken GitHub does not fail the run", "exit $exit");
    ok(($p->{latest}{version} // '') eq 'v2.0.0',
       "$id the previous known-good release is kept verbatim",
       'got ' . ($p->{latest}{version} // 'none'));
    ok($p->{stale}, "$id the kept data is marked stale so the site says so");
    ok(($p->{error} // '') =~ $expect,
       "$id the failure is reported in words a visitor could read",
       'got ' . ($p->{error} // 'none'));
    ok(!defined $p->{latest}{assets}[0] || $p->{latest}{assets}[0]{name},
       "$id nothing is invented to replace the missing data");
}

{
    # --strict turns the same condition into a hard failure
    my ($exit) = $run_updater->(out => "$FIX/A7-strict.json", mode => '403', strict => 1);
    ok($exit == 2, 'A7c --strict turns a rate-limited fetch into a non-zero exit', "exit $exit");

    # and with no previous data at all, the run fails loudly instead of writing
    # an empty site
    my $empty = "$FIX/A7-none.json";
    spew($empty, "{}\n");
    my ($exit_none, $stdout_none, $out_none) = $run_updater->(out => $empty, previous => '', mode => '403');
    ok($exit_none == 2,
       'A7d with no previous data a total failure exits non-zero rather than publishing nothing',
       "exit $exit_none");
    my $out_d = read_json($out_none);
    ok(($out_d->{projects}[0]{available} // 1) == 0 && length($out_d->{projects}[0]{error} // ''),
       'A7d the written file explains the failure instead of claiming a release');
}

# ============================================================ B. digest

section('B. change detection (data-digest.pl)');

{
    my $mk = sub {
        my ($dir, $rel_version, $extra) = @_;
        remove_tree($dir) if -d $dir;
        make_path("$dir/data");
        write_json("$dir/data/releases.json", {
            schema => 1, generated_at => $extra->{at},
            projects => [ { slug => 'pweevee', latest => { version => $rel_version } } ],
        });
        write_json("$dir/data/stats.json", {
            generated_at => $extra->{at},
            repos => [ { slug => 'pweevee', stars => 41,
                         fetched_at => $extra->{at}, stale_since => $extra->{since},
                         etag => $extra->{etag} } ],
        });
        my $at  = $extra->{at};
        my $day = $extra->{day};
        spew("$dir/index.html",
             '<time datetime="' . $at . '">' . $day . '</time> version ' . $rel_version . "\n");
        return $dir;
    };
    my $digest = sub {
        my ($tree) = @_;
        my $out = qx{perl PwEvevee/build-system/release/data-digest.pl --tree "$tree" --quiet 2>&1};
        my $exit = $? >> 8;
        return ($exit, $out =~ /^([0-9a-f]{64})/ ? $1 : ($out =~ /^([0-9a-f]{64})\s/ ? $1 : ''));
    };

    my $early = { at => '2026-10-27T22:01:00Z', since => '', etag => 'W/"aaa"', day => '27 October 2026' };
    my $later = { at => '2026-10-27T22:16:00Z', since => '', etag => 'W/"bbb"', day => '27 October 2026' };

    my ($e1, $a) = $digest->($mk->("$FIX/B/same-a", '3.1.0', $early));
    my ($e2, $b) = $digest->($mk->("$FIX/B/same-b", '3.1.0', $later));
    ok($e1 == 0 && $e2 == 0 && length $a, 'B1 the digest runs and prints a sha256', "exit $e1/$e2");
    ok($a eq $b && length $a,
       'B1 two runs over the same facts with different refresh timestamps have the same digest',
       "$a vs $b");

    (undef, my $c) = $digest->($mk->("$FIX/B/changed", '3.2.0', $later));
    ok($c ne $a, 'B2 a new release version always moves the digest');

    # a change in a rendered page, with the data untouched
    my $page_dir = $mk->("$FIX/B/page", '3.1.0', $later);
    spew("$page_dir/index.html", slurp("$page_dir/index.html") . "<p>an extra visible line</p>\n");
    (undef, my $d) = $digest->($page_dir);
    ok($d ne $b, 'B3 a change that only a page shows still moves the digest');

    # broken JSON is a change, not something normalized away
    my $broken = $mk->("$FIX/B/broken", '3.1.0', $later);
    spew("$broken/data/releases.json", '{"projects": [');
    (undef, my $e) = $digest->($broken);
    ok($e ne $b, 'B4 unparseable data counts as a change instead of being normalized away');

    # the visible date moving is a real change
    my $next_day = $mk->("$FIX/B/day", '3.1.0',
        { at => '2026-10-28T09:00:00Z', since => '', etag => 'W/"bbb"', day => '28 October 2026' });
    (undef, my $f) = $digest->($next_day);
    ok($f ne $b, 'B5 the rendered date moving to the next day moves the digest');
}

# ============================================================ C. the cycle

section('C. the cycle end to end (scripts/refresh-site.sh)');

my $SITE   = "$FIX/site";
my $LIVE   = "$FIX/live";
my $BACKUP = "$FIX/backups";
make_path($LIVE);

sub copy_tree { my ($from, $to) = @_; make_path($to); system('cp', '-r', "$from/.", $to) == 0 or die "copy $from -> $to failed\n" }
copy_tree("$ROOT/website",     "$SITE/website");
copy_tree("$ROOT/website-src", "$SITE/website-src");

# the site the world was actually being served: v2.0.0 as the latest release
my $site_projects = {
    projects => [
        map {
            my %p = %$_;
            $p{github} = { owner => 'mock-org', repo => $p{slug}, available => JSON::PP::true };
            delete $p{altsource};
            \%p;
        } @{ (read_json("$ROOT/website/data/projects.json") || { projects => [] })->{projects} }
    ],
};
write_json("$SITE/website/data/projects.json", $site_projects);
write_json("$SITE/website/data/releases.json", {
    schema => 1, generated_at => '2026-10-26T20:53:19Z',
    projects => [ map {
        { slug => $_->{slug}, name => $_->{name}, available => JSON::PP::true, stale => JSON::PP::false,
          latest => { version => 'v2.0.0', version_label => 'v2.0.0', published_at => '2026-10-06T01:48:48Z',
                      published_label => '6 October 2026', published_epoch => 1791251328,
                      prerelease => JSON::PP::false, name => 'PwEevee v2.0.0', url => 'https://github.com/mock-org/pweevee/releases/tag/v2.0.0',
                      assets => [], asset_count => 0 },
          history => [] }
    } @{ $site_projects->{projects} } ],
});
copy_tree("$SITE/website", $LIVE);   # the old artifact, already live

my $refresh = sub {
    my (%a) = @_;
    local $ENV{PWEEVEE_ROOT}       = $SITE;
    local $ENV{RELEASES_API_BASE}  = $BASE;
    local $ENV{STATS_API_BASE}     = $BASE;
    local $ENV{STATS_SHIELDS_BASE} = $BASE;
    # the validator stand-in is a plain command word: a quoted shell command
    # here would be re-split by the shell and the script would see a stray
    # argument (it did: exit 64, unknown option)
    my $cmd = 'bash scripts/refresh-site.sh --publish "' . $LIVE . '"'
            . ' --backups "' . $BACKUP . '"'
            . ' --tests-cmd ' . ($a{tests} // 'true')
            . ($a{status} ? ' --status-file "' . $a{status} . '"' : '')
            . ($a{extra} ? ' ' . $a{extra} : '')
            . ' 2>&1';
    my $stdout = qx{$cmd};
    return ($? >> 8, $stdout);
};
my $tree_hash = sub {
    my ($dir) = @_;
    my $h = Digest::SHA->new(256);
    my @files;
    File::Find::find({ no_chdir => 1, wanted => sub { push @files, $File::Find::name if -f $File::Find::name } }, $dir);
    for my $f (sort @files) {
        (my $rel = $f) =~ s{^\Q$dir\E/?}{};
        $h->add($rel, "\0", slurp($f), "\0");
    }
    return $h->hexdigest;
};
my $backups = sub { my @b = glob("$BACKUP/site-*.tar.gz"); return scalar @b };

serve_releases(
    release(tag => '3.1.0', name => 'PwEevee v3.1.0', published => '2026-10-27T21:44:22Z'),
    release(tag => 'v2.2.0-pre', published => '2026-10-23T19:28:17Z'),
    release(tag => 'v2.0.0', published => '2026-10-06T01:48:48Z'),
);

# ---- C1: refresh + publish -------------------------------------------------
my $live_before = $tree_hash->($LIVE);
my ($rc1, $out1) = $refresh->(status => "$FIX/status-1.json");
ok($rc1 == 0, 'C1 a refresh with a working validator exits 0', "exit $rc1");
my $s1 = read_json("$FIX/status-1.json") || {};
ok(($s1->{release} // '') eq '3.1.0', 'C1 the run records the release it found',
   'got ' . ($s1->{release} // 'none'));
ok($s1->{published} && $s1->{changed}, 'C1 the validated site is published');
ok(index(slurp("$LIVE/index.html") // '', '3.1.0') >= 0,
   'C1 the live homepage now serves the release GitHub reported');
ok(index(slurp("$LIVE/index.html") // '', 'v2.0.0') < 0,
   'C1 the superseded release is no longer offered as the latest');
ok(index(slurp("$LIVE/data/releases.json") // '', '3.1.0') >= 0,
   'C1 the live data file is the refreshed one, not the old artifact');
ok($tree_hash->($LIVE) ne $live_before, 'C1 the live document root really changed');
ok($backups->() == 1, 'C1 the previous site was backed up before the swap', 'backups: ' . $backups->());
my $tarball = (glob("$BACKUP/site-*.tar.gz"))[0];
ok(defined $tarball && (qx{tar -tzf "$tarball" 2>/dev/null} =~ m{\./index\.html}),
   'C1 the backup contains the site it replaced');
ok(-f "$LIVE/data/stats.json" && -f "$LIVE/index.html",
   'C1 the published tree is a complete site, not a partial copy');

# ---- C2: the same upstream data, run again --------------------------------
my ($rc2, $out2) = $refresh->(status => "$FIX/status-2.json");
my $s2 = read_json("$FIX/status-2.json") || {};
ok($rc2 == 0, 'C2 a second run with unchanged upstream data exits 0', "exit $rc2");
ok(!$s2->{changed} && !$s2->{published},
   'C2 a second run over unchanged data publishes nothing (no churn)');
ok($backups->() == 1, 'C2 a second run adds no backup', 'backups: ' . $backups->());
ok($out2 =~ /already this exact site/, 'C2 the run says why it did nothing');

# ---- C3: the updater succeeds and validation fails ------------------------
my $live_before_fail = $tree_hash->($LIVE);
serve_releases(
    release(tag => '3.2.0', name => 'PwEevee v3.2.0', published => '2026-11-10T12:00:00Z'),
    release(tag => '3.1.0', published => '2026-10-27T21:44:22Z'),
);
my ($rc3, $out3) = $refresh->(tests => 'false', status => "$FIX/status-3.json");
my $s3 = read_json("$FIX/status-3.json") || {};
ok($rc3 != 0, 'C3 a failing validator fails the run', "exit $rc3");
ok(($s3->{state} // '') eq 'failed', 'C3 the run record says the refresh failed',
   'state ' . ($s3->{state} // 'none'));
ok($tree_hash->($LIVE) eq $live_before_fail,
   'C3 the live site is byte-identical after a failed validation');
ok(index(slurp("$LIVE/index.html") // '', '3.2.0') < 0,
   'C3 the unvalidated release is not served');
ok($backups->() == 1, 'C3 no backup is taken for a site that was never swapped');
ok($out3 =~ /nothing was published/, 'C3 the failure says that nothing was published');

# ---- C4: publish is opt-in, and --digest-only touches nothing --------------
my $before_digest_only = $tree_hash->($SITE);
my $digest_out = qx{PWEEVEE_ROOT="$SITE" bash scripts/refresh-site.sh --digest-only 2>&1};
my $digest_exit = $? >> 8;
ok($digest_exit == 0 && $digest_out =~ /^([0-9a-f]{64})\s*$/, 'C4 --digest-only prints one bare digest',
   "exit $digest_exit, output '$digest_out'");
ok($tree_hash->($SITE) eq $before_digest_only, 'C4 --digest-only does not touch the tree');

# ---- C5: two runs at once cannot interleave --------------------------------
{
    my $flock = qx{command -v flock 2>/dev/null};
    if ($flock =~ /\S/) {
        my $lock = "$FIX/overlap.lock";
        my $hold = qx{bash -c 'exec 9>"$lock"; flock -n 9 && (sleep 20) & echo started'};
        select undef, undef, undef, 0.5;
        my $out = qx{PWEEVEE_ROOT="$SITE" RELEASES_API_BASE="$BASE" STATS_API_BASE="$BASE" STATS_SHIELDS_BASE="$BASE" bash scripts/refresh-site.sh --no-test --lock "$lock" 2>&1};
        my $exit = $? >> 8;
        ok($exit == 0 && $out =~ /another refresh is already running/,
           'C5 a run that overlaps a held lock declines instead of racing', "exit $exit");
    } else {
        note('flock is not installed on this host, so the overlap test is skipped here '
             . '(the lock is exercised on the server that runs the schedule)');
        $pass += 0;
    }
}

# ---------------------------------------------------------------- summary

print "\n" . ('-' x 62) . "\n";
if (@failures) {
    print "FAILED\n";
    print "  - $_\n" for @failures;
    printf "%d passed, %d FAILED\n", $pass, scalar @failures;
    exit 1;
}
printf "OK    %d checks passed\n", $pass;
exit 0;
