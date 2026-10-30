#!/usr/bin/env perl
# ============================================================================
# update-altsource.pl — generate website/data/altsource.json from an AltSource
# ============================================================================
#
#   perl PwEvevee/build-system/release/update-altsource.pl [options]
#
# An AltSource is the JSON manifest format AltStore / SideStore consume. It is a
# DIFFERENT kind of thing from a GitHub release, and this script keeps it that
# way: it never writes into website/data/releases.json and never pretends an
# AltSource entry is a release.
#
#   GitHub releases   -> website/data/releases.json   (update-releases.pl)
#   AltSource apps    -> website/data/altsource.json  (this script)
#
# Source URLs are declared per project in website/data/projects.json under
# "altsource". Nothing about the source is hardcoded here — not the URL, not the
# variant names, not the versions, not the sizes, not the dates.
#
# What this script does:
#   1. reads every project that declares an "altsource"
#   2. fetches the manifest
#   3. validates the shape (name/identifier/apps) instead of trusting it
#   4. PARSES each app into a variant: family, variant type, Spotify version,
#      EeveeSpotify version, size, date, description, download URL
#   5. groups variants into families so the site can show them as one build with
#      Standard / Patched options rather than four unrelated apps
#   6. rejects any download URL that is not https
#   7. writes the file atomically, keeping previous known-good data on failure
#
# Options
#   --out PATH         output file (default website/data/altsource.json)
#   --projects PATH    project data model (default website/data/projects.json)
#   --verify-assets    HEAD-check every variant download URL
#   --strict           exit non-zero if any source did not update cleanly
#   --offline          do not fetch; revalidate and rewrite existing data
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
              text_excerpt is_safe_url slugify);
use PwHttp qw(http_init http_get http_head http_cleanup);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $TRUE  = JSON::PP::true;
my $FALSE = JSON::PP::false;

my %opt = (
    out      => 'website/data/altsource.json',
    projects => 'website/data/projects.json',
);
while (@ARGV) {
    my $a = shift @ARGV;
    if    ($a eq '--out')           { $opt{out}      = shift @ARGV }
    elsif ($a eq '--projects')      { $opt{projects} = shift @ARGV }
    elsif ($a eq '--verify-assets') { $opt{verify}   = 1 }
    elsif ($a eq '--strict')        { $opt{strict}   = 1 }
    elsif ($a eq '--offline')       { $opt{offline}  = 1 }
    elsif ($a eq '--quiet')         { $opt{quiet}    = 1 }
    elsif ($a eq '-h' || $a eq '--help') { usage(); exit 0 }
    else  { die "unknown option: $a (try --help)\n" }
}

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $HTTP = $opt{offline} ? 'none'
         : http_init(tmp_dir => 'PwEvevee/build-system/_work/net',
                     user_agent => 'PwEevee-altsource-updater');
END { http_cleanup() }

info('PwEevee AltSource updater');
info("  repository root : $ROOT");
info("  http client     : $HTTP");
info('');

# ---------------------------------------------------------------- inputs

-f $opt{projects} or die "missing project data model: $opt{projects}\n";
my $model = read_json($opt{projects});
ref $model eq 'HASH' && ref $model->{projects} eq 'ARRAY'
    or die "$opt{projects}: expected an object with a 'projects' array\n";

my %prev_by_slug;
if (-f $opt{out}) {
    my $previous = eval { read_json($opt{out}) };
    if (ref $previous eq 'HASH' && ref $previous->{sources} eq 'ARRAY') {
        $prev_by_slug{ $_->{slug} } = $_ for grep { $_->{slug} } @{ $previous->{sources} };
    }
}

my @declared = grep { ref $_->{altsource} eq 'HASH' && $_->{altsource}{url} }
               @{ $model->{projects} };

unless (@declared) {
    info('No project declares an "altsource" — nothing to do.');
    write_json($opt{out}, {
        schema       => 1,
        generated_at => iso_now(),
        generator    => 'PwEvevee/build-system/release/update-altsource.pl',
        source_kind  => 'AltStore-format source manifest (NOT a GitHub release)',
        sources      => [],
    });
    exit 0;
}

# ---------------------------------------------------------------- fetch loop

my (@out, @failed, @stale);

for my $p (@declared) {
    my $slug = $p->{slug};
    my $as   = $p->{altsource};
    my $url  = $as->{url};

    info("Fetching AltSource for $p->{name} ...");
    info("  $url");

    unless (is_safe_url($url)) {
        warn "!! $p->{name}: the declared AltSource URL is not an https URL; refusing to fetch\n";
        push @out, unavailable_entry($p, 'The declared source URL is not a valid https URL.');
        push @failed, $p->{name};
        next;
    }

    if ($opt{offline}) {
        if (my $keep = $prev_by_slug{$slug}) {
            info('  - offline: keeping existing data (' . scalar(@{ $keep->{variants} || [] }) . ' variants)');
            push @out, $keep;
        } else {
            warn "!! $p->{name}: offline mode and no previously generated data\n";
            push @out, unavailable_entry($p, 'Offline mode and no previously generated data.');
            push @failed, $p->{name};
        }
        next;
    }

    my ($src, $err) = fetch_source($url);

    if (!$err) {
        my $entry = build_entry($p, $src, $url);
        if (!@{ $entry->{variants} }) {
            $err = 'The source was reachable but listed no usable applications.';
        } else {
            info(sprintf('  %s %s — %d variant%s in %d famil%s',
                "\x{2713}", $entry->{source_name},
                scalar @{ $entry->{variants} }, (@{ $entry->{variants} } == 1 ? '' : 's'),
                scalar @{ $entry->{families} }, (@{ $entry->{families} } == 1 ? 'y' : 'ies')));
            for my $f (@{ $entry->{families} }) {
                info(sprintf('      %s: %s', $f->{label},
                    join(', ', map { $_->{variant_label} } @{ $f->{variants} })));
            }
            for my $v (@{ $entry->{variants} }) {
                info(sprintf('      - %-38s %-10s Spotify %-8s Eevee %s',
                    $v->{name}, $v->{size_label},
                    ($v->{spotify_version} // '?'), ($v->{eevee_version} // '?')));
            }

            if ($opt{verify}) {
                for my $v (@{ $entry->{variants} }) {
                    my $code = http_head($v->{download_url});
                    my $good = ($code && $code =~ /^(?:200|302)$/) ? 1 : 0;
                    $v->{verified} = $good ? $TRUE : $FALSE;
                    warn "!! $p->{name}: '$v->{name}' HEAD returned " . ($code // 'no response') . "\n"
                        unless $good;
                }
                info('    variant URLs verified');
            }

            push @out, $entry;
            next;
        }
    }

    # --- failure path: never destroy good data -----------------------------
    warn "!! $p->{name}: $err\n";
    if (my $keep = $prev_by_slug{$slug}) {
        my %copy = %$keep;
        $copy{stale}       = $TRUE;
        $copy{stale_since} = iso_now();
        $copy{error}       = $err;
        info('  - keeping the previous known-good variant list');
        push @out, \%copy;
        push @stale, $p->{name};
    } else {
        push @out, unavailable_entry($p, $err);
        push @failed, $p->{name};
    }
}

# ---------------------------------------------------------------- output

write_json($opt{out}, {
    schema       => 1,
    generated_at => iso_now(),
    generator    => 'PwEvevee/build-system/release/update-altsource.pl',
    source_kind  => 'AltStore-format source manifest (NOT a GitHub release)',
    sources      => \@out,
});

my $fresh = grep { $_->{available} && !$_->{stale} } @out;

info('');
printf "Generated %s — %d of %d source%s %s.\n",
    $opt{out}, $fresh, scalar @out, (@out == 1 ? '' : 's'),
    ($opt{offline} ? 'reused from existing data (offline, nothing was fetched)' : 'fetched fresh');
printf "Kept previous known-good data for: %s\n", join(', ', @stale) if @stale;
printf "No source data available for: %s\n", join(', ', @failed) if @failed;

if (!$fresh && !@stale) {
    print STDERR "\n!! FAIL: no AltSource data could be retrieved, and there was no previous\n"
               . "   data to fall back on. $opt{out} now describes the failure.\n";
    exit 2;
}
if ($opt{strict} && (@failed || @stale)) {
    my $n = scalar(@failed) + scalar(@stale);
    print STDERR "\n!! FAIL: --strict was requested and $n source(s) did not update cleanly.\n";
    exit 2;
}
info('Done.');
exit 0;

# ============================================================ subroutines

sub info { print "$_[0]\n" unless $opt{quiet} }

sub iso_now { return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(time)) }

sub usage {
    print <<'USAGE';
usage: perl PwEvevee/build-system/release/update-altsource.pl [options]

  --out PATH         output file        (default website/data/altsource.json)
  --projects PATH    project data model (default website/data/projects.json)
  --verify-assets    HEAD-check every variant download URL
  --strict           exit non-zero if any source did not update cleanly
  --offline          do not fetch; revalidate and rewrite existing data
  --quiet            print warnings and errors only

Source URLs come from the "altsource" block of each project in the data model.
USAGE
}

# GET the manifest — returns (hashref, undef) or (undef, message).
sub fetch_source {
    my ($url) = @_;
    my ($code, $raw) = http_get($url, headers => [ 'Accept: application/json' ]);

    return (undef, 'network error: the source host could not be reached.') unless defined $code;
    return (undef, 'The source returned 404 — the manifest is not at that path.') if $code == 404;
    return (undef, "The source returned HTTP $code.") if $code != 200;
    return (undef, 'The source returned an empty response body.') unless defined $raw && length $raw;

    my $data = eval { JSON::PP->new->utf8->relaxed->decode($raw) };
    return (undef, 'The source returned a response that is not valid JSON.') unless defined $data;
    return (undef, 'The source manifest is not a JSON object.') unless ref $data eq 'HASH';
    return (undef, 'The source manifest has no "apps" array.') unless ref $data->{apps} eq 'ARRAY';
    return (undef, 'The source manifest lists no applications.') unless @{ $data->{apps} };
    return ($data, undef);
}

# Turn a validated manifest into the shape the renderer consumes.
sub build_entry {
    my ($p, $src, $url) = @_;
    my $as = $p->{altsource};

    my @variants;
    my $order = 0;
    for my $app (@{ $src->{apps} }) {
        next unless ref $app eq 'HASH';
        my $v = parse_app($app, $as, $order);
        unless ($v) { $order++; next }
        $v->{order} = $order++;
        push @variants, $v;
    }

    # Group into families so "Standard" and "Patched" read as two options on one
    # build rather than two unrelated apps.
    my (%fam, @fam_order);
    for my $v (@variants) {
        my $key = $v->{family_slug};
        unless ($fam{$key}) {
            $fam{$key} = {
                slug     => $key,
                label    => $v->{family},
                note     => $v->{family_note},
                variants => [],
            };
            push @fam_order, $key;
        }
        push @{ $fam{$key}{variants} }, $v;
    }
    # inside a family, Standard first, then Patched
    for my $key (@fam_order) {
        @{ $fam{$key}{variants} } = sort {
            $a->{patched} <=> $b->{patched} || $a->{order} <=> $b->{order}
        } @{ $fam{$key}{variants} };
        my ($newest) = sort { ($b->{date_epoch} || 0) <=> ($a->{date_epoch} || 0) }
                       @{ $fam{$key}{variants} };
        $fam{$key}{spotify_version} = $newest->{spotify_version};
        $fam{$key}{eevee_version}   = $newest->{eevee_version};
        $fam{$key}{updated_label}   = $newest->{date_label};
        $fam{$key}{variant_count}   = scalar @{ $fam{$key}{variants} };
    }

    my $icon = is_safe_url($src->{iconURL} // '') ? $src->{iconURL} : undef;

    return {
        slug               => $p->{slug},
        project            => $p->{name},
        available          => $TRUE,
        stale              => $FALSE,
        source_name        => defined $src->{name} && $src->{name} =~ /\S/ ? $src->{name}
                                                                          : ($as->{name} // 'AltSource'),
        source_identifier  => $src->{identifier},
        source_subtitle    => $src->{subtitle},
        source_description => $src->{description},
        source_icon_url    => $icon,
        source_url         => $url,
        # The declared repository path is used exactly as published upstream.
        repo               => $as->{repo},
        repo_url           => (is_safe_url($as->{repo_url} // '') ? $as->{repo_url} : undef),
        note               => $as->{note},
        families           => [ map { $fam{$_} } @fam_order ],
        variants           => \@variants,
        variant_count      => scalar @variants,
    };
}

# One AltSource app entry -> one installable variant.
#
# The manifest carries the interesting facts inside free text, so they are
# extracted with explicit patterns and left undef when they are not there. No
# value is ever invented.
sub parse_app {
    my ($app, $as, $i) = @_;

    my $name = $app->{name};
    return undef unless defined $name && $name =~ /\S/;

    my $url = $app->{downloadURL};
    unless (is_safe_url($url)) {
        warn "!! AltSource app '$name' has no usable https downloadURL; skipped\n";
        return undef;
    }

    my ($family, $family_note) = family_for($name, $as);
    my $patched = $name =~ /patch/i ? 1 : 0;

    my $desc = $app->{localizedDescription} // '';

    # "Spotify Version: v9.1.76, EeveeSpotify Version: 6.6.8(2) Unpatched ..."
    my ($spotify) = $desc =~ /Spotify\s*Version\s*:?\s*v?([0-9][0-9A-Za-z.()_-]*?)\s*(?:,|$|\s)/i;
    my ($eevee)   = $desc =~ /EeveeSpotify\s*Version\s*:?\s*v?([0-9][0-9A-Za-z.()_-]*?)\s*(?:,|\.\s|$|\s)/i;
    for ($spotify, $eevee) { s/[.,]+$// if defined }

    # The manifest's own "version" field is the Spotify version for this source;
    # it is used only as a fallback for the parsed value, never over it.
    $spotify = $app->{version} if !defined $spotify && defined $app->{version};

    my $date  = $app->{versionDate};
    my $epoch = defined $date ? date_epoch($date =~ /T/ ? $date : "${date}T00:00:00Z") : 0;

    my $size = ($app->{size} // 0) =~ /^\d+$/ ? $app->{size} + 0 : 0;

    return {
        name             => $name,
        slug             => slugify($name),
        family           => $family,
        family_slug      => slugify($family),
        family_note      => $family_note,
        patched          => $patched,
        variant          => $patched ? 'patched' : 'standard',
        variant_label    => $patched ? 'Patched' : 'Standard',
        variant_note     => $patched
            ? 'Requires a paid certificate, a jailbreak or TrollStore.'
            : 'Works with a free certificate in AltStore or SideStore.',
        bundle_id        => $app->{bundleIdentifier},
        developer        => $app->{developerName},
        download_url     => $url,
        icon_url         => (is_safe_url($app->{iconURL} // '') ? $app->{iconURL} : undef),
        size             => $size,
        size_label       => fmt_bytes($size),
        spotify_version  => $spotify,
        eevee_version    => $eevee,
        version          => $app->{version},
        release_date     => $date,
        date_label       => (defined $date ? fmt_date($date =~ /T/ ? $date : "${date}T00:00:00Z")
                                           : undef),
        date_epoch       => $epoch,
        description      => $desc =~ /\S/ ? $desc : undef,
        summary          => text_excerpt($desc, 190),
        subtitle         => $app->{subtitle},
        release_notes    => $app->{versionDescription},
    };
}

# Which family does this app belong to? Declared families win, so the site's
# grouping is a data decision rather than a guess. Longest match first, so
# "ESR Liquid Glass" is not swallowed by a shorter pattern.
sub family_for {
    my ($name, $as) = @_;
    my @fams = ref $as->{families} eq 'ARRAY' ? @{ $as->{families} } : ();
    for my $f (sort { length($b->{match} // '') <=> length($a->{match} // '') } @fams) {
        my $m = $f->{match} or next;
        if (index(lc $name, lc $m) == 0) {
            return ($f->{label} // $m, $f->{note});
        }
    }
    # Undeclared app: fall back to the name with any variant suffix removed, so a
    # new upstream entry still groups sensibly instead of disappearing.
    (my $base = $name) =~ s/\s*\(?\s*patched\s*\)?\s*$//i;
    $base =~ s/\s+$//;
    return (length $base ? $base : $name, undef);
}

sub unavailable_entry {
    my ($p, $reason) = @_;
    my $as = ref $p->{altsource} eq 'HASH' ? $p->{altsource} : {};
    return {
        slug          => $p->{slug},
        project       => $p->{name},
        available     => $FALSE,
        stale         => $FALSE,
        error         => $reason,
        source_name   => $as->{name},
        source_url    => $as->{url},
        repo          => $as->{repo},
        repo_url      => (is_safe_url($as->{repo_url} // '') ? $as->{repo_url} : undef),
        note          => $as->{note},
        families      => [],
        variants      => [],
        variant_count => 0,
    };
}
