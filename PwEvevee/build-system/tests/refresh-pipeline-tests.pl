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
use Cwd qw(abs_path);
use Fcntl qw(:flock);
use POSIX qw(strftime);
use Time::Local qw(timegm);

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

# ============================================================ D. browser check

section('D. the on-visit recheck cannot overwrite the rendered snapshot');

{
    # The browser half of the freshness story: it may report a newer release and
    # link to it, and it must never be able to do more than that. Scoped to the
    # freshSession module, since the rest of the asset legitimately mentions
    # download URLs (the copy tools, the installer workshop).
    my $js = slurp("$ROOT/website-src/assets/pweevee.js") // '';
    my ($mod) = $js =~ /(function freshSession\b.*?\}\(\)\);)/s;
    ok(defined $mod && length($mod) > 300, 'D0 the on-visit freshness module was found',
       'length ' . (defined $mod ? length($mod) : 'undef'));
    $mod //= '';

    ok($mod =~ /upstream <= h\.epoch\)\s*return/,
       'D1 a payload that is not strictly newer than the rendered epoch is ignored, '
     . 'so an equal-or-older reply can never replace the page snapshot');
    ok($mod =~ /rel\.draft\)\s*throw/,
       'D2 a draft release is rejected by the recheck, as it is by the renderer');
    ok($mod =~ /credentials:\s*['"]omit['"]/ && $mod !~ /Authorization|Bearer|GITHUB_TOKEN/i,
       'D3 the recheck stays anonymous: no credentials, no token, nothing uploaded');
    ok($mod !~ /download_url|sha256/i,
       'D4 the recheck never rewrites a download URL or a hash line from browser-side data');
    ok($mod =~ /a\.href\s*=\s*rel\.html_url/,
       'D5 what it does offer is the authoritative release page, not a rewritten download');
    ok($mod =~ /data-fresh-state['"],\s*failures\s*\?\s*'offline'/,
       'D6 a failed check is reported as offline and the rendered values stand, '
     . 'instead of presenting a false successful refresh');
}

# ==================================================== E. incident + notifications

section('E. incident state, notification decisions and the merged status');

my $iso = sub { strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($_[0])) };

{
    my $EH = "$FIX/health";
    remove_tree($EH) if -d $EH;
    make_path($EH);

    my $T0  = timegm(0, 0, 10, 27, 9, 2026);   # a fixed clock: cooldowns are exact
    my $hs  = "$EH/status.json";
    my $hh  = "$EH/health.json";

    my $run_health = sub {
        my (%a) = @_;
        my @args = ('--status', qq{"$hs"}, '--state', qq{"$hh"}, '--now', $a{now});
        push @args, ('--rc', $a{rc}) if exists $a{rc};
        push @args, ('--stage', qq{"$a{stage}"}) if defined $a{stage} && length $a{stage};
        push @args, ('--since', qq{"$a{since}"}) if defined $a{since};
        push @args, ('--skipped', qq{"$a{skipped}"}) if defined $a{skipped};
        push @args, ('--cooldown', $a{cooldown}) if defined $a{cooldown};
        push @args, ('--record-notification', '--result', $a{result}) if defined $a{result};
        push @args, ('--error', qq{"$a{error}"}) if defined $a{error};
        my $out = qx{perl scripts/refresh-health.pl @args 2>&1};
        return ($? >> 8, $out, read_json($hs) || {}, read_json($hh) || {});
    };
    my $ok_run = sub {
        my ($t, %extra) = @_;
        write_json($hs, {
            started => $iso->($t), finished => $iso->($t), state => 'ok', stage => 'done',
            release => '3.1.0', changed => JSON::PP::false, published => JSON::PP::false,
            note => '', %extra,
        });
    };
    my $bad_run = sub {
        my ($t, $stage, $note) = @_;
        write_json($hs, {
            started => $iso->($t), finished => $iso->($t), state => 'failed', stage => $stage,
            release => '3.1.0', changed => JSON::PP::false, published => JSON::PP::false,
            note => $note // "$stage failed (exit 1)",
        });
    };

    # ---- E1: a clean success -------------------------------------------------
    $ok_run->($T0);
    my ($e1rc, $e1out, $s, $h) = $run_health->(rc => 0, stage => 'done', since => $iso->($T0), now => $T0);
    ok($e1rc == 0 && $e1out =~ /"notify":0/,
       'E1 a clean success sends no notification', "exit $e1rc, $e1out");
    ok(($s->{last_success_at} // '') eq $iso->($T0),
       'E1 the status records the last successful refresh');
    ok(($h->{last_published_release} // '') eq '3.1.0',
       'E1 ... and the release it published, so a later failure can name it');
    ok(($s->{incident} // '') eq 'none' && ($s->{consecutive_failures} // -1) == 0,
       'E1 ... and reports no incident');
    ok(!$h->{pending_notification}, 'E1 no alert is queued');

    # ---- E2: first failure ---------------------------------------------------
    my $T2 = $T0 + 900;
    $bad_run->($T2, 'validate');
    my ($e2rc, $e2out, $s2, $h2) = $run_health->(rc => 1, since => $iso->($T2), now => $T2);
    ok($e2rc == 0 && $e2out =~ /"notify":1/ && $e2out =~ /"kind":"failure"/,
       'E2 the first failure of an incident queues one alert', $e2out);
    ok(($s2->{stage} // '') eq 'validate',
       'E2 the stage comes from the pipeline record, not from the wrapper');
    ok(($s2->{consecutive_failures} // 0) == 1 && ($s2->{incident} // '') eq 'open',
       'E2 the incident is open and counted');
    my $alert2 = ($h2->{pending_notification} || {})->{text} // '';
    ok($alert2 =~ /validating the rendered site/,
       'E2 the alert names the stage that failed', $alert2);
    ok($alert2 =~ /release 3\.1\.0/,
       'E2 ... and the release the live site still serves', $alert2);

    # ---- E3: the cooldown ----------------------------------------------------
    my $T3 = $T2 + 900;
    $bad_run->($T3, 'validate');
    my ($e3rc, $e3out, $s3) = $run_health->(rc => 1, since => $iso->($T3), now => $T3);
    ok($e3out =~ /"notify":0/ && $e3out =~ /cooldown/,
       'E3 a repeat failure inside the cooldown is not re-alerted', $e3out);
    ok(($s3->{consecutive_failures} // 0) == 2,
       'E3 ... but it is still counted');

    # ---- E4: a delivery failure keeps the incident open ----------------------
    my ($e4rc, $discard4, $s4, $h4) = $run_health->(
        result => 'failed', error => 'the notification endpoint answered HTTP 500', now => $T3 + 1);
    ok($e4rc == 0 && ($s4->{notification}{status} // '') eq 'failed',
       'E4 a failed delivery is recorded as such');
    ok(($s4->{incident} // '') eq 'open',
       'E4 ... and does not close the incident');
    ok(!$h4->{pending_notification},
       'E4 ... and does not leave the same alert queued forever');

    # ---- E5: once the cooldown elapses, a still-failing run alerts again ------
    my $T5 = $T3 + 3700;
    $bad_run->($T5, 'validate');
    my ($erc5, $e5out, $s5) = $run_health->(rc => 1, since => $iso->($T5), now => $T5);
    ok($erc5 == 0 && $e5out =~ /"notify":1/ && $e5out =~ /cooldown elapsed/,
       'E5 after the cooldown the still-failing pipeline alerts again', $e5out);
    ok(($s5->{consecutive_failures} // 0) == 3,
       'E5 the failure counter keeps climbing');

    # ---- E6: recovery --------------------------------------------------------
    my $T6 = $T5 + 60;
    $ok_run->($T6);
    my ($e6rc, $e6out, $s6, $h6) = $run_health->(rc => 0, stage => 'done', since => $iso->($T6), now => $T6);
    ok($e6rc == 0 && $e6out =~ /"kind":"recovery"/,
       'E6 a success after a failure queues exactly one recovery alert', $e6out);
    ok($e6out =~ /after 3 failed run/,
       'E6 the recovery alert states how many runs had failed', $e6out);
    ok(($s6->{incident} // '') eq 'open',
       'E6 the incident stays open until the recovery is actually delivered');
    my ($e6brc, $discard6, $s6b, $h6b) = $run_health->(result => 'ok', now => $T6 + 1);
    ok($e6brc == 0 && ($s6b->{incident} // '') eq 'none'
       && !($h6b->{incident_open} // 0),
       'E6 delivering the recovery closes the incident');
    ok(($h6b->{last_notified_at} // '') eq $iso->($T6 + 1),
       'E6 ... and records when the operator was told');

    # ---- E7: a lock skip changes nothing and alerts nobody -------------------
    my $T7 = $T6 + 300;
    my ($e7rc, $e7out, $s7) = $run_health->(skipped => 'locked', now => $T7);
    ok($e7rc == 0 && $e7out =~ /"notify":0/,
       'E7 a run skipped for the lock never alerts');
    ok(($s7->{state} // '') eq 'skipped' && ($s7->{stage} // '') eq 'lock',
       'E7 ... and is distinguishable from a success and from a failure');
    ok(($s7->{last_success_at} // '') eq $iso->($T6),
       'E7 ... leaving the last successful refresh untouched');
    ok(($s7->{consecutive_failures} // -1) == 0,
       'E7 ... and the failure counter at zero');

    # ---- E8: corrupt health file --------------------------------------------
    spew($hh, "{ this is not json\n");
    my $T8 = $T7 + 900;
    $ok_run->($T8);
    my ($e8rc, $discard8, $s8, $h8) = $run_health->(rc => 0, stage => 'done', since => $iso->($T8), now => $T8);
    ok($e8rc == 0, 'E8 a corrupt health file does not wedge the schedule');
    ok(($h8->{state_recovered} // 0) == 1,
       'E8 ... and the fact that it had to be restarted is recorded');
    ok(ref $s8 eq 'HASH' && ($s8->{state} // '') eq 'ok',
       'E8 ... while the status file stays valid JSON');

    # ---- E9: corrupt status file --------------------------------------------
    spew($hs, '{"started": "2026-10-27T23:0');
    my $T9 = $T8 + 900;
    my ($e9rc, $discard9, $s9, $h9) = $run_health->(rc => 1, stage => 'fetch', since => $iso->($T9), now => $T9);
    ok($e9rc == 0 && ref $s9 eq 'HASH' && ($s9->{state} // '') eq 'failed',
       'E9 a corrupt status file is replaced by a valid failure record');
    ok(($h9->{status_recovered} // 0) == 1,
       'E9 ... and the corruption is visible in the health file');

    # ---- E10: redaction ------------------------------------------------------
    my $T10 = $T9 + 60;
    $bad_run->($T10, 'fetch',
        'fetch failed at https://hooks.example.test/T0/B0/sekrit?token=abc123');
    my ($e10rc, $e10out, $s10) = $run_health->(rc => 1, since => $iso->($T10), now => $T10);
    ok($e10rc == 0 && ($s10->{note} // '') =~ /<url>/ && ($s10->{note} // '') !~ /abc123|sekrit/,
       'E10 an endpoint or token in an error is redacted before it is stored',
       $s10->{note} // '');
    ok($e10out !~ /abc123|sekrit/,
       'E10 ... and never reaches the decision output');

    # ---- E11: the status keeps its old keys and gains the new ones -----------
    for my $k (qw(started finished state stage release changed published note)) {
        ok(exists $s10->{$k}, "E11 the status keeps its existing key '$k'");
    }
    for my $k (qw(last_success_at last_published_release consecutive_failures incident notification checked_at)) {
        ok(exists $s10->{$k}, "E11 ... and exposes '$k'");
    }

    # ---- E12: usage errors are loud -----------------------------------------
    my $bad = qx{perl scripts/refresh-health.pl --status "$hs" 2>&1};
    ok(($? >> 8) == 64, 'E12 a missing --state is a usage error, not a silent success');
}

# ==================================================== F. the cron wrapper

section('F. the cron wrapper end to end, against a stub tree and a mock endpoint');

{
    my $G = "$FIX/wrap";
    remove_tree($G) if -d $G;
    make_path("$G/repo/scripts", "$G/site/logs", "$G/site/bin", "$G/hook", "$G/home");

    # The tree the wrapper checks out: a stand-in pipeline whose only job is to
    # write the status record the real refresh-site.sh writes and to exit the
    # way the scenario needs it to.
    my $STUB = <<'STUB';
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in --status-file) out="$2"; shift 2 ;; *) shift ;; esac
done
mode="${STUB_MODE:-ok}"
now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
case "$mode" in
  ok)       state=ok;     stage=done;     release=3.1.0; rc=0; note="" ;;
  validate) state=failed; stage=validate; release=3.1.0; rc=1; note="validating the rendered site failed (exit 1)" ;;
  publish)  state=failed; stage=publish;  release=3.1.0; rc=1; note="backup failed" ;;
  releases) state=failed; stage=releases; release=;      rc=2; note="fetching GitHub release metadata failed (exit 2)" ;;
  *)        state=ok;     stage=done;     release=3.1.0; rc=0; note="" ;;
esac
printf '{"started":"%s","finished":"%s","state":"%s","stage":"%s","release":"%s","changed":false,"published":false,"note":"%s"}\n' \
  "$now" "$now" "$state" "$stage" "$release" "$note" > "$out"
echo "stub refresh ($mode)"
exit "$rc"
STUB
    spew("$G/repo/scripts/refresh-site.sh", $STUB);

    qx{git -C "$G/repo" init -q 2>&1};
    qx{git -C "$G/repo" symbolic-ref HEAD refs/heads/main 2>&1};   # the wrapper fetches main
    qx{git -C "$G/repo" add -A 2>&1};
    qx{git -C "$G/repo" -c user.email=t\@example.test -c user.name=t commit -qm "stub tree" 2>&1};
    my $ABS = abs_path("$G/repo");
    qx{git clone -q "file://$ABS" "$G/site/src" 2>&1};

    copy("scripts/refresh-cron.sh",   "$G/site/bin/refresh-cron.sh");
    copy("scripts/refresh-health.pl", "$G/site/bin/refresh-health.pl");
    copy("scripts/refresh-notify.sh", "$G/site/bin/refresh-notify.sh");
    my $wrap_bin = "$G/site/bin/refresh-cron.sh";

    # ---- the endpoint -------------------------------------------------------
    my $HOOK = <<'HOOK';
use strict; use warnings;
use IO::Socket::INET;
my $dir = $ARGV[0];
my $srv = IO::Socket::INET->new(LocalAddr => '127.0.0.1', LocalPort => 0,
                                Listen => 8, ReuseAddr => 1) or die "hook listen: $!";
open(my $pf, '>', "$dir/port.txt") or die "port: $!"; print {$pf} $srv->sockport; close $pf;
while (my $c = $srv->accept) {
    my $req = '';
    while (defined(my $line = <$c>)) { $req .= $line; last if $line =~ /^\r?$/ }
    my ($len) = $req =~ /^Content-Length:\s*(\d+)/mi;
    my $body = '';
    if ($len) {
        my $got = 0;
        while ($got < $len) {
            my $n = $c->read(my $chunk, $len - $got);
            last unless $n;
            substr($body, $got) = $chunk; $got += $n;
        }
    }
    open(my $lf, '>>', "$dir/requests.jsonl") or die "log: $!";
    my $b = $body; $b =~ s/\r?\n/ /g;
    print {$lf} $b, "\n"; close $lf;
    my $code = -e "$dir/fail" ? 500 : 200;
    print {$c} "HTTP/1.0 $code Mock\r\nContent-Length: 0\r\n\r\n";
    close $c;
}
HOOK
    spew("$G/hook/server.pl", $HOOK);
    my $hook_pid = fork();
    defined $hook_pid or die "cannot fork the mock endpoint: $!\n";
    if (!$hook_pid) {
        # the endpoint outlives individual runs; it must not hold the caller's
        # stdout open or every qx{} that started it would wait for its exit
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec 'perl', "$G/hook/server.pl", "$G/hook" or die "exec hook: $!\n";
    }
    my $HPORT = '';
    for (1 .. 200) {
        if (open(my $pf, '<', "$G/hook/port.txt")) { $HPORT = <$pf> // ''; close $pf; chomp $HPORT; last if $HPORT =~ /^\d+$/ }
        select undef, undef, undef, 0.05;
    }
    die "the mock notification endpoint did not come up\n" unless $HPORT =~ /^\d+$/;
    my $HOOK_URL = "http://127.0.0.1:$HPORT/hook";

    my $requests = sub {
        my $d = slurp("$G/hook/requests.jsonl") // '';
        return grep { /\S/ } split /\n/, $d;
    };
    my $reset = sub {
        unlink "$G/site/logs/refresh-health.json", "$G/site/logs/refresh-status.json",
               "$G/hook/requests.jsonl", "$G/hook/fail";
    };
    my $wrap = sub {
        my (%a) = @_;
        local $ENV{PWEEVEE_SITE_DIR}        = "$G/site";
        local $ENV{STUB_MODE}               = $a{mode} // 'ok';
        local $ENV{PWEEVEE_NOTIFY_CONF}     = "$G/no-such.conf";
        local $ENV{PWEEVEE_NOTIFY_COOLDOWN} = $a{cooldown} // 3600;
        local $ENV{PWEEVEE_NOTIFY_URL}      = defined $a{url} ? $a{url} : $HOOK_URL;
        my $out = qx{bash "$wrap_bin" 2>&1};
        return ($? >> 8, $out);
    };
    my $status = sub { read_json("$G/site/logs/refresh-status.json") || {} };

    # ---- F1: a healthy run --------------------------------------------------
    $reset->();
    my ($f1rc, $f1out) = $wrap->(mode => 'ok');
    ok($f1rc == 0, 'F1 the wrapper exits 0 on a clean run', "exit $f1rc, $f1out");
    ok(($status->()->{state} // '') eq 'ok' && ($status->()->{incident} // '') eq 'none',
       'F1 ... and records a healthy status');
    ok(scalar($requests->()) == 0, 'F1 a healthy run sends no notification');

    # ---- F2: the first failure ----------------------------------------------
    my ($f2rc) = $wrap->(mode => 'validate');
    my @r2 = $requests->();
    ok($f2rc == 1, 'F2 the wrapper propagates the pipeline exit code', "exit $f2rc");
    ok(scalar(@r2) == 1, 'F2 the first failure sends exactly one notification',
       'sent ' . scalar(@r2));
    ok(($r2[0] // '') =~ /validating the rendered site/,
       'F2 the alert names the stage that failed', $r2[0] // '');
    ok(($r2[0] // '') =~ /3\.1\.0/,
       'F2 ... and the release still being served');
    ok(($status->()->{stage} // '') eq 'validate' && ($status->()->{state} // '') eq 'failed',
       'F2 the status records the failed stage');
    ok(($status->()->{notification}{status} // '') eq 'ok',
       'F2 ... and that the alert was delivered');
    ok(($status->()->{consecutive_failures} // 0) == 1,
       'F2 ... and the first consecutive failure');

    # ---- F3: dedup ----------------------------------------------------------
    my ($f3rc) = $wrap->(mode => 'validate');
    ok($f3rc == 1 && scalar($requests->()) == 1,
       'F3 a repeat failure inside the cooldown sends no second alert',
       'sent ' . scalar($requests->()));

    # ---- F4: the cooldown expires -------------------------------------------
    my ($f4rc) = $wrap->(mode => 'validate', cooldown => 0);
    ok($f4rc == 1 && scalar($requests->()) == 2,
       'F4 once the cooldown elapses the still-failing pipeline alerts again',
       'sent ' . scalar($requests->()));

    # ---- F5: recovery -------------------------------------------------------
    my ($f5rc) = $wrap->(mode => 'ok');
    my @r5 = $requests->();
    ok($f5rc == 0 && scalar(@r5) == 3, 'F5 a success after a failure sends one recovery alert',
       'sent ' . scalar(@r5));
    ok(($r5[2] // '') =~ /recovered/, 'F5 whose text says the pipeline recovered', $r5[2] // '');
    ok(($status->()->{incident} // '') eq 'none',
       'F5 the status now reports no open incident');
    ok(($status->()->{notification}{status} // '') eq 'ok',
       'F5 ... and that the recovery was delivered');

    # ---- F6: no endpoint configured -----------------------------------------
    $reset->();
    $wrap->(mode => 'ok');
    my ($f6rc) = $wrap->(mode => 'validate', url => '');
    ok($f6rc == 1, 'F6 a failure still fails the run when nothing is configured', "exit $f6rc");
    ok(scalar($requests->()) == 0, 'F6 nothing is sent when no endpoint is configured');
    ok(($status->()->{notification}{status} // '') eq 'not-configured',
       'F6 ... and the status says notifications are not configured',
       $status->()->{notification}{status} // 'none');
    ok(($status->()->{incident} // '') eq 'open',
       'F6 ... while the incident stays open');

    # ---- F7: delivery failure cannot mask the pipeline failure ---------------
    $reset->();
    $wrap->(mode => 'ok');
    spew("$G/hook/fail", "1");
    my ($f7rc) = $wrap->(mode => 'publish');
    ok($f7rc == 1, 'F7 a failed delivery does not change the pipeline exit code', "exit $f7rc");
    ok(($status->()->{state} // '') eq 'failed' && ($status->()->{stage} // '') eq 'publish',
       'F7 ... nor the recorded stage or state');
    ok(($status->()->{notification}{status} // '') eq 'failed',
       'F7 ... and the delivery failure is recorded');
    ok(($status->()->{note} // '') eq 'backup failed',
       'F7 ... with the pipeline error intact, not replaced by the delivery error',
       $status->()->{note} // '');
    unlink "$G/hook/fail";

    # ---- F8: lock contention ------------------------------------------------
    my $have_flock = qx{command -v flock 2>/dev/null};
    if ($have_flock =~ /\S/) {
        $reset->();
        $wrap->(mode => 'ok');
        my $lock_path = "$G/site/refresh.lock";
        my $held = 0;
        if (open(my $lfh, '>', $lock_path)) {
            $held = flock($lfh, LOCK_EX | LOCK_NB) ? 1 : 0;
            my ($f8rc) = $wrap->(mode => 'validate');
            ok($f8rc == 0, 'F8 a run that finds the lock held exits 0 instead of failing', "exit $f8rc");
            ok(($status->()->{state} // '') eq 'skipped' && ($status->()->{stage} // '') eq 'lock',
               'F8 ... and records a skipped attempt');
            ok(($status->()->{last_success_at} // '') ne '',
               'F8 ... preserving the last successful refresh');
            ok(scalar($requests->()) == 0, 'F8 ... without alerting');
            close $lfh;
        }
        ok($held, 'F8 (the lock was actually held for that check)');
    } else {
        note('flock is not installed on this host, so the wrapper lock check is skipped here '
             . '(it is exercised on the server that runs the schedule)');
    }

    # ---- F9: a failure before the pipeline starts ---------------------------
    $reset->();
    $wrap->(mode => 'ok');
    qx{mv "$G/site/src" "$G/site/src.hidden"};
    my ($f9rc) = $wrap->(mode => 'ok');
    ok($f9rc == 1, 'F9 a missing checkout fails the run', "exit $f9rc");
    ok(($status->()->{stage} // '') eq 'fetch', 'F9 ... at the fetch stage');
    ok(($status->()->{release} // '') eq '3.1.0',
       'F9 ... while still reporting the release the live site serves',
       $status->()->{release} // '');
    ok(scalar($requests->()) == 1, 'F9 ... and the operator is told');
    qx{mv "$G/site/src.hidden" "$G/site/src"};

    # ---- F10: no secret in the log ------------------------------------------
    my $log = slurp("$G/site/logs/refresh.log") // '';
    ok($log !~ /127\.0\.0\.1:\Q$HPORT\E/,
       'F10 the notification endpoint never appears in the refresh log');

    # ---- F11: no interactive environment -----------------------------------
    $reset->();
    my $PATH = $ENV{PATH} // '/usr/bin:/bin';
    my $bare = qx{env -i HOME="$G/home" PATH="$PATH" SHELL=/bin/sh PWEEVEE_SITE_DIR="$G/site" bash "$wrap_bin" 2>&1};
    my $bare_rc = $? >> 8;
    ok($bare_rc == 0, 'F11 the wrapper runs with only HOME/PATH (the cron environment)',
       "exit $bare_rc, $bare");

    # ---- F12: all three scripts parse ---------------------------------------
    for my $s (qw(refresh-site.sh refresh-cron.sh refresh-notify.sh)) {
        qx{bash -n "scripts/$s" 2>&1};
        ok(($? >> 8) == 0, "F12 scripts/$s parses");
    }

    kill 'TERM', $hook_pid;
    waitpid($hook_pid, 0);
}

# ==================================================== G. schedule contract

section('G. the schedule the documentation claims is the schedule that exists');

{
    my $doc = slurp("$ROOT/docs/homelab-deployment.md") // '';
    ok($doc =~ m{^\*/15 \* \* \* \* /home/sleepy/pweevee-site/bin/refresh-cron\.sh}m,
       'G1 the operator doc states the real fifteen-minute entry');
    ok($doc =~ /refresh-health\.pl/ && $doc =~ /notify\.conf/,
       'G2 ... and how incident state and the notification endpoint are configured');
    ok($doc =~ /\@reboot/,
       'G3 ... and the boot-time entry that starts the server');
    ok(-f "$ROOT/scripts/refresh-cron.sh" && -f "$ROOT/scripts/refresh-health.pl"
       && -f "$ROOT/scripts/refresh-notify.sh",
       'G4 the three deployed pieces have a tracked source in the repository');
}

# ==================================================== H. the notifier

section('H. the notifier picks a payload shape and never leaks the endpoint');

{
    my $G = "$FIX/wrap";
    my $dry = sub {
        my ($url) = @_;
        local $ENV{PWEEVEE_NOTIFY_URL}   = $url;
        local $ENV{PWEEVEE_NOTIFY_CONF}  = "$G/no-such.conf";
        local $ENV{PWEEVEE_NOTIFY_TITLE} = 'PwEevee website refresh failed';
        local $ENV{PWEEVEE_NOTIFY_TEXT}  = 'see https://x.test/y?token=zzz';
        my $out = qx{bash scripts/refresh-notify.sh --dry-run 2>&1};
        return ($? >> 8, $out);
    };

    my ($h1rc, $h1) = $dry->('https://hooks.slack.com/services/T/B/x');
    ok($h1rc == 0 && $h1 =~ /^format=slack\n/ && $h1 =~ /"text"/,
       'H1 a Slack webhook gets a text payload', $h1);
    my (undef, $h2) = $dry->('https://discord.com/api/webhooks/1/x');
    ok($h2 =~ /^format=discord\n/ && $h2 =~ /"content"/,
       'H2 a Discord webhook gets a content payload', $h2);
    my (undef, $h3) = $dry->('https://ntfy.sh/pweevee');
    ok($h3 =~ /^format=ntfy\n/, 'H3 an ntfy topic gets a plain body', $h3);
    my (undef, $h4) = $dry->('https://example.test/hook');
    ok($h4 =~ /^format=generic\n/ && $h4 =~ /"source":"pweevee-website"/,
       'H4 anything else gets the documented generic JSON', $h4);
    ok($h4 =~ /<url>/ && $h4 !~ /zzz/,
       'H5 the message is redacted before it can leave the process');
    ok($h4 !~ /example\.test/, 'H6 the endpoint itself is never printed');

    {
        local $ENV{PWEEVEE_NOTIFY_URL}  = '';
        local $ENV{PWEEVEE_NOTIFY_CONF} = "$G/no-such.conf";
        qx{bash scripts/refresh-notify.sh 2>&1};
        ok(($? >> 8) == 2, 'H7 no endpoint is a distinct exit code, not a silent success');
    }

    spew("$G/notify.conf", "PWEEVEE_NOTIFY_URL=https://ntfy.sh/from-file\n");
    {
        delete local $ENV{PWEEVEE_NOTIFY_URL};
        local $ENV{PWEEVEE_NOTIFY_CONF} = "$G/notify.conf";
        my $out = qx{bash scripts/refresh-notify.sh --dry-run 2>&1};
        ok($out =~ /^format=ntfy\n/, 'H8 the endpoint may come from the 0600 config file');
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
