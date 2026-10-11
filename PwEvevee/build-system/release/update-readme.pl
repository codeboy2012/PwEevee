#!/usr/bin/env perl
# ============================================================================
# update-readme.pl — refresh ONLY the delimited release block in README.md
# ============================================================================
#
#   perl PwEvevee/build-system/release/update-readme.pl [options]
#
# What it does
#   1. reads website/data/projects.json for the repo slug(s) it serves
#   2. picks the newest PUBLISHED, NON-PRERELEASE release from the GitHub API
#      (drafts are never used)
#   3. rewrites ONLY the content between <!-- releases:begin --> and
#      <!-- releases:end --> in README.md; everything outside stays untouched
#   4. asset links come from the release payload itself — nothing hardcoded
#   5. writes atomically (tmp file + rename); skips the write when content
#      would be byte-identical (no redundant commits)
#
# Failure policy (fail loud, write nothing)
#   - missing/invalid release metadata, unreachable API, or a malformed
#     delimited block => non-zero exit, README untouched
#
# Options
#   --repo OWNER/NAME   override the repo to query (default: pweevee project)
#   --readme PATH       README to edit (default: README.md at repo root)
#   --data PATH         projects.json (default: website/data/projects.json)
#   --offline           do not call the network; repopulate from existing data
#                       in website/data/releases.json instead (for testing)
#
# The script NEVER publishes, pushes, or commits. A caller does that.
# ============================================================================
use strict;
use warnings;
# NO `use utf8` here: the README body is handled as raw bytes end-to-end
# (slurp '>:raw' both ways). Marking the source as UTF-8 would turn the
# block's literal glyphs into wide characters that never compare equal to the
# byte-oriented README splice and would double-encode it on write.
use FindBin ();
use lib "$FindBin::Bin/lib";
use JSON::PP qw(decode_json encode_json);
use PwSite   qw(repo_root read_json slurp text_excerpt);
use PwHttp   qw(http_init http_get http_cleanup);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $ROOT   = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
my $README = "$ROOT/README.md";
my $DATA   = "$ROOT/website/data/projects.json";
my $OFFLINE = 0;
my $FORCE_REPO;
my %opts = ();

my @args = @ARGV;
while (@args) {
    my $a = shift @args;
    if    ($a eq '--readme')  { $README = shift @args; }
    elsif ($a eq '--data')    { $DATA   = shift @args; $opts{data} = $DATA; }
    elsif ($a eq '--repo')    { $FORCE_REPO = shift @args; }
    elsif ($a eq '--offline') { $OFFLINE = 1; }
    else { die "unknown option: $a\n"; }
}
-f $README or die "no README: $README\n";

# ----------------------------------------------------------- release source
my ($rel, $src_label);
if ($OFFLINE) {
    # OFFLINE TESTS: the fixture file path arrives through --data (reused as
    # the releases source in offline mode). The fixture holds exactly one
    # project record: { releases: [ {...release...} ] }.
    my $releases_file = defined $opts{data} ? $opts{data} : "$ROOT/website/data/releases.json";
    -f $releases_file or die "--offline needs $releases_file\n";
    my $all = eval { decode_json(slurp($releases_file)) };
    my @candidate;
    if (ref $all eq 'HASH' && ref $all->{releases} eq 'ARRAY') {
        @candidate = @{ $all->{releases} };
    } elsif (ref $all eq 'ARRAY') {
        @candidate = @$all;
    } else {
        die "offline fixture must be {releases:[…]} or [ … ]: " . ($@ || 'unparseable') . "\n";
    }
    my ($rd) = grep { ref $_ eq 'HASH' } @candidate;
    $rd or die "no release entries in $releases_file\n";
    $rel = {
        name    => $rd->{name},
        tag     => $rd->{tag_name} || $rd->{tag},
        url     => $rd->{url} || $rd->{html_url},
        date    => $rd->{published_at} || $rd->{date},
        notes   => $rd->{notes} || '',
        prerelease => ($rd->{prerelease} ? 1 : 0),
        assets  => [ map { { name => $_->{name}, size => ($_->{size}||0),
                             url  => $_->{url} || $_->{download_url} } } @{ $rd->{assets} || [] } ],
    };
    $src_label = "offline:$releases_file";
} else {
    my $projects = read_json($DATA);
    my $pweevee;
    for my $p (@{ $projects->{projects} || [] }) {
        # one authoritative project entry drives the README: the unified build
        $pweevee = $p if ($p->{repo} || '') =~ m{/PwEevee$} || ($p->{name} || '') eq 'pweevee';
    }
    $pweevee ||= { repo => ($FORCE_REPO || 'codeboy2012/PwEevee') };
    my $repo = $FORCE_REPO || $pweevee->{repo} or die "no repo in $DATA; use --repo\n";
    http_init(user_agent => 'PwEevee-readme-updater');
    my $body = http_get("https://api.github.com/repos/$repo/releases?per_page=30")
        or die "cannot reach GitHub releases API for $repo\n";
    http_cleanup();
    my @rels = eval { @{ decode_json($body) } };
    @rels or die "no usable releases payload for $repo\n";

    REL: for my $r (@rels) {
        next REL if $r->{draft};          # drafts are never stable
        next REL if $r->{prerelease};     # prereleases are never stable
        # Some authors ship pre-releases without the API flag (observed:
        # v2.1.0-pre). Treat the usual suffixes as prerelease too.
        next REL if ($r->{tag_name} // '') =~ /-(pre|beta|alpha|rc)([.-]|\d|$)/i;
        $rel = {
            name       => $r->{name},
            tag        => $r->{tag_name},
            url        => $r->{html_url},
            date       => $r->{published_at},
            notes      => $r->{body} // '',
            prerelease => ($r->{prerelease} ? 1 : 0),
            assets     => $r->{assets} // [],
        };
        last REL;
    }
    $rel or die "no stable (non-draft, non-prerelease) release found for $repo\n";
    $src_label = "github:$repo";
}

# ----------------------------------------------------------- sanity guards
defined $rel->{tag} && length $rel->{tag} or die "release has no tag; refusing to edit README\n";
defined $rel->{url} && length $rel->{url} or die "release has no URL; refusing to edit README\n";
die "refusing to write a prerelease as stable\n" if $rel->{prerelease};

# ----------------------------------------------------------- IPA asset pick
my ($ipa) = grep { $_->{name} && $_->{name} =~ /\.ipa$/i } @{ $rel->{assets} || [] };

# ----------------------------------------------------------- block rendering
my $date = $rel->{date} // '';
$date =~ s/T.*//;                       # '2026-09-23T12:00:00Z' -> '2026-09-23'

my $display_name = (defined $rel->{name} && length $rel->{name}) ? $rel->{name} : $rel->{tag};

my $block = <<"MKDOWN";
<!-- releases:begin (generated by PwEvevee/build-system/release/update-readme.pl — do not edit inside) -->
## Releases

**Latest stable release:** [$display_name]($rel->{url}) — released `$date`.
MKDOWN

if (defined $ipa) {
    my $dl = $ipa->{browser_download_url} || $ipa->{url};
    # API asset URLs need auth; browser URLs are the public download links.
    die "asset without a usable download URL\n" unless $dl && $dl =~ m{^https://};
    my $mb = $ipa->{size} ? sprintf('%.0f', ($ipa->{size} / 1_048_576)) : '?';
    $block .= <<"MKDOWN";
**Download:** [$ipa->{name}]($dl) ($mb MB)

MKDOWN
} else {
    $block .= <<"MKDOWN";
**Downloads:** no IPA asset was attached to this release; see the [release page]($rel->{url}) for what is available.

MKDOWN
}

$block .= <<"MKDOWN";
All downloads belong to their GitHub release — this README links, never mirrors, them.
<!-- releases:end -->
MKDOWN
chomp $block;   # splice boundary keeps the manual '\n' that follows the end marker

# ----------------------------------------------------------- splice
my $body = slurp($README);
my $bpos = index($body, '<!-- releases:begin');
my $epos = index($body, '<!-- releases:end -->');
if ($bpos < 0 || $epos < 0 || $epos < $bpos) {
    die sprintf("README.md must contain a <!-- releases:begin --> … <!-- releases:end --> pair (begin at %d, end at %d)\n", $bpos, $epos);
}
$epos += length('<!-- releases:end -->');
# The block itself does not end in a newline: whatever follows the end marker
# (its own '\n' plus manual content) stays untouched.

my $new = substr($body, 0, $bpos) . $block . substr($body, $epos);
unless ($new eq $body) {
    my $tmp = "$README.$$";
    # Body was raw-read (bytes); write raw too. Going through an encoding layer
    # here would treat each UTF-8 byte as a character and double-encode every
    # non-ASCII glyph in the manual README (observed: 151 mojibake sequences).
    open my $f, '>:raw', $tmp or die "write $tmp: $!";
    print $f $new; close $f;
    rename $tmp, $README or die "rename failed: $!";
    print "updated README.md (from $src_label; release $rel->{tag},", (defined $ipa ? " with $ipa->{name}" : " no IPA asset"), ")\n";
} else {
    print "README.md already up to date (from $src_label) — nothing written\n";
}
1;
