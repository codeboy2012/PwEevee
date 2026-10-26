#!/usr/bin/env perl
# ============================================================================
# render-site.pl — build website/ from website-src/ + the generated data
# ============================================================================
#
#   perl PwEvevee/build-system/release/render-site.pl [--quiet]
#
# Inputs
#   website-src/layout.html        the page shell (nav, footer, head, metadata)
#   website-src/pages/*.html       page content with [[component:…]] placeholders
#   website-src/assets/*           stylesheet and script, copied to website/assets
#   website/data/projects.json     project data model      (hand-authored facts)
#   website/data/releases.json     GitHub release data     (update-releases.pl)
#   website/data/altsource.json    AltSource IPA variants  (update-altsource.pl)
#
# Outputs
#   website/**/index.html          every route, fully rendered — the site needs
#                                  no JavaScript to show release information
#   website/assets/*               the source assets, copied verbatim
#
# There is exactly one website implementation. website-src/ is the only place to
# edit templates, CSS and JS; website/ is generated output and is never hand-
# maintained. The only files that exist solely in website/ are the ones the other
# build scripts generate there: data/*.json, assets/brand/, the derived icon
# sizes and the social card.
#
# Where downloads come from
#   GitHub releases are the source of truth for every project's release
#   information and for the PwEevee download itself. The website hosts no IPA of
#   its own and carries no locally-built "dev" release: a download button is only
#   rendered when a published release asset actually exists, and otherwise the
#   page shows an explicit unavailable state plus a link to the release on
#   GitHub.
#
#   The SideloadLabs AltSource is kept conceptually separate from GitHub: it
#   describes installable IPA variants, it is labelled as such everywhere it
#   appears, and it is never presented as a GitHub release.
#
# No version number, date, size, asset URL or release note is written by hand
# anywhere: everything comes from the two generated data files.
#
# Re-running is idempotent.
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin ();
use lib "$FindBin::Bin/lib";
use File::Path qw(make_path);
use POSIX ();
use PwSite qw(repo_root slurp spew read_json h attr fmt_bytes fmt_date fmt_date_iso
              date_epoch notes_to_html is_safe_url);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $QUIET = grep { $_ eq '--quiet' } @ARGV;
my $ROOT  = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $SRC = 'website-src';
my $OUT = 'website';

-d $SRC or die "missing $SRC — the page templates live there\n";
-f "$SRC/layout.html" or die "missing $SRC/layout.html\n";

# ---------------------------------------------------------------- assets
#
# The stylesheet and the script are SOURCE files: they live in website-src/assets
# and are copied into the generated tree. website/ is build output, so nothing in
# it is hand-maintained. Edit website-src/assets/* and re-run this script.
my @COPIED = copy_assets();

# ------------------------------------------------------------------
# Cache-busting versions for the source-owned assets.
#
# The deployed site sits behind Cloudflare (and ordinary browser caches), so
# without a URL change a returning visitor can end up with fresh HTML and a
# cached, older stylesheet or script — the two no longer agree and components
# render unstyled. Busting on content hash makes every deploy self-invalidating:
# a changed file gets a new URL, so the old cached copy is never consulted, and
# an unchanged file keeps the same URL so its cache stays useful.
#
# The hash is computed from the OUTPUT file (the bytes that will actually be
# served), not the source, so generated artwork is covered by the same rule.
# ------------------------------------------------------------------
use Digest::SHA qw(sha256_hex);
use File::Find;
my %ASSET_V;
find({
    no_chdir => 1,
    wanted   => sub {
        return if -d $File::Find::name;
        (my $name = $_) =~ s{^.*/}{};
        return if $name =~ /^\./;
        open my $h, '<:raw', $File::Find::name or die "hash $File::Find::name: $!";
        local $/; my $bytes = <$h>; close $h;
        $ASSET_V{$name} = substr(sha256_hex($bytes), 0, 8);
    },
}, "$OUT/assets");

# Appends the version query to relative /assets/… references. Absolute
# references (og:image, sitemap) keep canonical URLs and are intentionally
# untouched, as are links that already carry a query.
# ---------------------------------------------------------------- data

my $MODEL = read_json("$OUT/data/projects.json");
my $SITE  = $MODEL->{site} || {};
my @PROJECTS = @{ $MODEL->{projects} || [] };
my %PROJECT  = map { $_->{slug} => $_ } @PROJECTS;

my $GH = { projects => [] };
if (-f "$OUT/data/releases.json") {
    $GH = eval { read_json("$OUT/data/releases.json") } || { projects => [] };
} else {
    warn "!! $OUT/data/releases.json not found — run update-releases.pl to populate\n"
       . "   upstream release information. Pages will render an explanatory state.\n";
}
my %GHP = map { $_->{slug} => $_ } @{ $GH->{projects} || [] };

# AltSource variants. A missing file is not an error — only the EeveeSpotify
# project declares a source, and a page renders an explanatory state without it.
my $AS = { sources => [] };
if (-f "$OUT/data/altsource.json") {
    $AS = eval { read_json("$OUT/data/altsource.json") } || { sources => [] };
} else {
    warn "!! $OUT/data/altsource.json not found — run update-altsource.pl to populate\n"
       . "   the AltSource variant list. The EeveeSpotify download section will render\n"
       . "   an explanatory state.\n";
}
my %ASP = map { $_->{slug} => $_ } @{ $AS->{sources} || [] };

# Repository statistics (website/data/stats.json, generated by update-stats.pl).
# A missing file is not an error: the stats band renders an explanatory state
# instead of fabricated zeroes, exactly like release and AltSource data.
my $STATS = { repos => [] };
if (-f "$OUT/data/stats.json") {
    $STATS = eval { read_json("$OUT/data/stats.json") } || { repos => [] };
} else {
    warn "!! $OUT/data/stats.json not found — run update-stats.pl to populate\n"
       . "   the repository stats band. It will render an explanatory state.\n";
}
my %STP = map { $_->{slug} => $_ } @{ $STATS->{repos} || [] };

# The project the site is about. Its GitHub release is the featured download.
my $HOME_SLUG = 'pweevee';

# ------------------------------------------------------------- brand artwork
#
# Project artwork is used as-is: never recoloured, never stretched, never
# recreated. The renderer only looks for a file and builds the lit environment
# around it. Any of these names works, first match wins; drop the artwork in as
# a square PNG (or WebP/SVG) with a transparent background.
# The BARE "<slug>" name wins: PwEevee's brand slot is served by the ORIGINAL
# render (website/assets/brand/pweevee.png from make-app-icon.pl), while the
# Spotify-derived artwork that depicts the shipped app icon lives at
# pweevee-app-icon.png and is only used below for the honest "App icon"
# showcase. Nothing real was lost by that separation; both files stay.
my %ART;
for my $slug (qw(pweevee spotipw eeveespotify)) {
    # Candidates are listed explicitly rather than globbed, so a stray file in
    # the folder is never picked up. The bare name is preferred; "<slug>-logo"
    # is kept as the legacy drop-in.
    CANDIDATE: for my $base ($slug, "$slug-logo") {
        for my $ext (qw(png webp svg jpg)) {
            my $rel = "assets/brand/$base.$ext";
            if (-f "$OUT/$rel" && -s "$OUT/$rel") { $ART{$slug} = "/$rel"; last CANDIDATE }
        }
    }
}
my $HAS_ART = keys %ART ? 1 : 0;

# Icon sizes derived from the official logo by make-brand-assets.pl remain on
# disk (assets/icon-{32,180,512}.png — downscale the procedural mark, kept for
# tooling and back-compat), but the rendered site no longer links them: per the
# 2026-10-25 icon revert every PwEevee mark serves the app icon artwork below.

# The artwork that depicts the app icon inside PwEevee IPAs: a restyle derived
# from the Spotify icon (Spotify's mark — third-party artwork). Since the icon
# revert it is ALSO the site-wide mark: the favicon, the Apple touch icon, the
# small nav/footer brand marks and the release-panel badge all serve it.
my %APPICON;
for my $slug (qw(pweevee)) {
    for my $ext (qw(png webp)) {
        my $rel = "assets/brand/$slug-app-icon.$ext";
        if (-f "$OUT/$rel" && -s "$OUT/$rel") { $APPICON{$slug} = "/$rel"; last }
    }
}

my $SITE_URL  = $SITE->{canonical_url} || 'https://pweevee.skytweak.dpdns.org/';
my $OWN_REPO  = own_repo_url();

# ---------------------------------------------------------------- render

# The component table must exist before the page loop runs — a `my` declared
# further down the file would still be empty at this point.
my %COMPONENT = (
    'github-icon'        => sub { github_icon() },
    'starfield'          => sub { starfield() },
    'data-freshness'     => \&c_data_freshness,
    'brand-showcase'     => \&c_brand_showcase,
    'hero-download'      => \&c_hero_download,
    'build-facts'        => \&c_build_facts,
    'project-stats'      => \&c_project_stats,
    'ecosystem'          => \&c_ecosystem,
    'github-release'     => \&c_github_release,
    'altsource-variants' => \&c_altsource_variants,
    'altsource-source'   => \&c_altsource_source,
    'release-history'    => \&c_release_history,
    'project-hero'       => \&c_project_hero,
    'project-links'      => \&c_project_links,
    'pweevee-work'       => \&c_pweevee_work,
    'project-highlights' => \&c_project_highlights,
    'project-notes'      => \&c_project_notes,
    'star-project'       => \&c_star_project,
    'freebuff'           => \&c_freebuff,
    'attribution'        => \&c_attribution,
    'credits-upstream'   => \&c_credits_upstream,
    'license-list'       => \&c_license_list,
    'repos'              => \&c_repos,
    'dependencies'       => \&c_dependencies,
    'support'            => \&c_support,
);

my $LAYOUT = slurp("$SRC/layout.html");
utf8::decode($LAYOUT);
my @pages  = sort glob("$SRC/pages/*.html");
@pages or die "no page templates found in $SRC/pages/\n";

my $written = 0;
my @sitemap;
for my $file (@pages) {
    my ($meta, $body) = parse_page($file);
    my $route = $meta->{route} or die "$file: no 'route:' in its meta block\n";
    push @sitemap, $route unless ($meta->{robots} // '') =~ /noindex/;

    my $target = target_for($meta);

    my %tok = (
        title       => $meta->{title}       // 'PwEevee',
        og_title    => $meta->{og_title}    // $meta->{title} // 'PwEevee',
        description => $meta->{description} // ($SITE->{description} // ''),
        canonical   => canonical_for($route),
        site_url    => $SITE_URL,
        robots      => $meta->{robots} // 'index,follow',
        github_icon => github_icon(),
        data_freshness => c_data_freshness(),
        brand_mark  => brand_mark(),
        icons       => icon_links(),
        starfield   => starfield(),
        theme_control        => theme_control(),
        theme_control_drawer => theme_control(labelled_by => 'theme-label-drawer'),
    );

    # ------------------------------------------------------------------
    # Order matters for safety. The layout and the page template are fully
    # resolved FIRST, and only then is generated content spliced in. If content
    # were inserted before the token pass, a GitHub release note containing
    # "{{title}}" would be substituted, and one containing "[[component:x]]"
    # would abort the build — upstream text must never steer the renderer.
    # ------------------------------------------------------------------

    my $shell = $LAYOUT;
    $shell =~ s{\{\{(\w+)\}\}}{
        $1 eq 'content' ? "\0CONTENT\0"
                        : (exists $tok{$1} ? $tok{$1}
                                           : die "$SRC/layout.html: unknown token {{$1}}\n")
    }ge;
    # {{cur:key}} becomes aria-current on the matching nav entry
    my $nav = $meta->{nav} // '';
    $shell =~ s/\{\{cur:(\w+)\}\}/$1 eq $nav ? ' aria-current="page"' : ''/ge;

    if ($shell =~ /(\{\{[^}\n]*\}\})/) {
        die "$SRC/layout.html: unresolved token $1\n";
    }
    if ($body =~ /(\{\{[^}\n]*\}\})/) {
        die "$file: page templates cannot use layout tokens ($1)\n";
    }

    my $content = expand($body, $file);

    # single literal splice; the value is inserted verbatim, never re-parsed
    my $at = index($shell, "\0CONTENT\0");
    die "$SRC/layout.html: no {{content}} placeholder\n" if $at < 0;
    my $doc = substr($shell, 0, $at) . $content
            . substr($shell, $at + length("\0CONTENT\0"));

    # cache-bust the copied assets (no-op for any URL the map has no entry for).
    # All capture context is copied into lexicals FIRST: an inner substitution
    # would otherwise clobber $1/$2/$& before they are used.
    $doc =~ s{(href|src)="/assets/([^"?]+)"}{
        my ($attr, $path) = ($1, $2);
        my $name = $path;
        $name =~ s{^.*/}{};
        my $orig = qq{$attr="/assets/$path"};
        defined $ASSET_V{$name}
            ? qq{$attr="/assets/$path?v=$ASSET_V{$name}"}
            : $orig
    }ge;

    make_path(dir_of($target));
    utf8::encode($doc);          # pages are written as UTF-8 bytes
    spew($target, $doc);
    $written++;
    say_it(sprintf('  %-28s -> %s', $route, $target));
}

write_sitemap(\@sitemap);
write_robots();

say_it('');
printf "Rendered %d page%s from %s.\n", $written, ($written == 1 ? '' : 's'), $SRC;
printf "GitHub release data : %s\n",
    (%GHP ? "website/data/releases.json (" . scalar(keys %GHP) . ' projects)'
          : 'MISSING — run update-releases.pl');
printf "AltSource data      : %s\n",
    (%ASP ? 'website/data/altsource.json ('
            . join(', ', map { ($ASP{$_}{variant_count} // 0) . " variants for $_" } sort keys %ASP)
            . ')'
          : 'MISSING — run update-altsource.pl');
printf "Downloads           : GitHub release assets and AltSource URLs only — no locally hosted IPA.\n";
printf "Source assets       : %s\n",
    (@COPIED ? join(', ', @COPIED) . ' copied from ' . "$SRC/assets"
             : "already current from $SRC/assets");

# ============================================================ page plumbing

sub say_it { print "$_[0]\n" unless $QUIET }

# Copy website-src/assets/** into website/assets/**.
#
# Only the files the source tree owns are touched. Generated brand artwork
# (assets/brand/, the derived icon sizes, the social card) is produced by the
# other build scripts and lives only in the output tree, so it is never removed
# here. Files are rewritten only when the bytes differ, which keeps re-runs
# idempotent and leaves mtimes alone for unchanged assets.
sub copy_assets {
    my $from = "$SRC/assets";
    return () unless -d $from;

    my @changed;
    for my $path (sort glob("$from/*")) {
        next if -d $path;
        my $name = $path;
        $name =~ s{^.*/}{};
        next if $name =~ /^\./;

        my $target = "$OUT/assets/$name";
        my $new    = slurp($path);
        my $old    = -f $target ? slurp($target) : undef;
        next if defined $old && $old eq $new;

        spew($target, $new);   # spew() creates the directory itself
        push @changed, $name;
    }
    return @changed;
}

# A page starts with <!--PwEevee key: value … --> followed by its content.
sub parse_page {
    my ($file) = @_;
    my $raw = slurp($file);
    utf8::decode($raw);
    $raw =~ s/^\x{FEFF}//;
    my %meta;
    if ($raw =~ s{\A\s*<!--PwEevee\s*(.*?)-->\s*}{}s) {
        my $block = $1;
        for my $line (split /\n/, $block) {
            next unless $line =~ /^\s*([a-z_]+)\s*:\s*(.*?)\s*$/;
            $meta{$1} = $2;
        }
    } else {
        die "$file: missing the <!--PwEevee … --> meta block\n";
    }
    return (\%meta, $raw);
}

sub target_for {
    my ($meta) = @_;
    return "$OUT/" . $meta->{file} if $meta->{file};
    my $route = $meta->{route};
    return "$OUT/index.html" if $route eq '/';
    (my $path = $route) =~ s{^/|/$}{}g;
    return "$OUT/$path/index.html";
}

sub dir_of {
    my ($p) = @_;
    $p =~ s{/[^/]+$}{};
    return $p;
}

sub canonical_for {
    my ($route) = @_;
    (my $base = $SITE_URL) =~ s{/$}{};
    return "$base/" if $route eq '/';
    return $base . $route;
}

# A sitemap listing only the indexable routes, so the canonical URLs are the ones
# crawlers find. lastmod uses the release-data generation time, which is when the
# pages last actually changed.
sub write_sitemap {
    my ($routes) = @_;
    my $lastmod = fmt_date_iso($GH->{generated_at})
                || fmt_date_iso(POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(time)));
    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n}
            . qq{<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};
    for my $route (sort @$routes) {
        $xml .= '  <url><loc>' . h(canonical_for($route)) . '</loc>'
              . "<lastmod>$lastmod</lastmod>"
              . '<priority>' . ($route eq '/' ? '1.0' : $route =~ m{^/(downloads|releases)$} ? '0.9' : '0.7')
              . "</priority></url>\n";
    }
    $xml .= "</urlset>\n";
    utf8::encode($xml);          # this file is declared UTF-8; write bytes
    spew("$OUT/sitemap.xml", $xml);
}

sub write_robots {
    (my $base = $SITE_URL) =~ s{/$}{};
    my $txt = <<"TXT";
# PwEevee — $base/
User-agent: *
Allow: /

# the generated data files are for this site's own pages, not for search results
Disallow: /data/

Sitemap: $base/sitemap.xml
TXT
    utf8::encode($txt);          # the em dash above is a real character
    spew("$OUT/robots.txt", $txt);
}

sub own_repo_url {
    my $p = $PROJECT{pweevee};
    my $gh = $p && ref $p->{github} eq 'HASH' ? $p->{github} : undef;
    return 'https://github.com/codeboy2012/spoti.pw-builds'
        unless $gh && $gh->{owner} && $gh->{repo};
    return "https://github.com/$gh->{owner}/$gh->{repo}";
}

# ---------------------------------------------------------- component engine

sub expand {
    my ($body, $file) = @_;
    $body =~ s{\[\[component:([a-z-]+)(?:\s+([a-z0-9._-]+))?\]\]}{
        my ($name, $arg) = ($1, $2);
        my $fn = $COMPONENT{$name}
            or die "$file: unknown component '[[component:$name]]'\n";
        $fn->($arg);
    }ge;
    return $body;
}

# ============================================================ components

# The small mark beside the wordmark in the nav and footer, and — since the icon
# revert — the favicon, apple-touch icon and release badge too: all serve the
# app icon artwork.
sub brand_mark {
    my $src = $APPICON{pweevee} // $ART{pweevee} // '/assets/favicon.svg';
    return qq{<img class="brand__mark" src="@{[ attr($src) ]}" alt="" aria-hidden="true" }
         . qq{width="28" height="28" decoding="async">};
}

# <link> tags for the favicon and Apple touch icon — both point at the app icon
# artwork. Falls back to the SVG mark only if that file is missing.
sub icon_links {
    my @out;
    my $app = $APPICON{pweevee};
    if ($app) {
        push @out, qq{<link rel="icon" type="image/png" href="$app">};
        push @out, qq{<link rel="apple-touch-icon" href="$app">};
    } elsif (-f "$OUT/assets/favicon.svg") {
        push @out, '<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">';
    }
    return join("\n", @out);
}

# References the sprite symbol defined once in layout.html.
sub github_icon {
    return '<svg class="btn__icon" aria-hidden="true" focusable="false">'
         . '<use href="#i-github"></use></svg>';
}

# ---- the theme control ------------------------------------------------------
#
# Three segments: follow the device, light, dark. Rendered with "system" marked
# as pressed, which is the correct static answer — the page with no stored
# override does follow the device. assets/theme.js applies a stored override
# before the first paint and pweevee.js then corrects the pressed state.
#
# Hidden by CSS until the `js` class is present, because without a script the
# buttons cannot do anything; the theme still follows prefers-color-scheme then.
#
# $labelled_by lets the drawer copy point at its visible "Theme" heading instead
# of repeating an aria-label, and keeps the two instances from sharing an id.
sub theme_control {
    my (%o) = @_;
    # h(), not attr(): attr() is the URL escaper and returns empty for plain text.
    my $group = $o{labelled_by}
        ? qq{aria-labelledby="@{[ h($o{labelled_by}) ]}"}
        : 'aria-label="Colour theme"';

    my @modes = (
        [ 'system', 'i-auto', 'Match the system theme' ],
        [ 'light',  'i-sun',  'Light theme' ],
        [ 'dark',   'i-moon', 'Dark theme' ],
    );

    my $html = qq{<div class="theme" role="group" $group data-theme-control>};
    for my $m (@modes) {
        my ($value, $icon, $label) = @$m;
        my $pressed = $value eq 'system' ? 'true' : 'false';
        $html .= qq{<button class="theme__btn" type="button" data-theme-set="$value" }
               . qq{aria-pressed="$pressed" title="@{[ h($label) ]}">}
               . qq{<svg class="theme__icon" aria-hidden="true" focusable="false">}
               . qq{<use href="#$icon"></use></svg>}
               . qq{<span class="visually-hidden">@{[ h($label) ]}</span>}
               . '</button>';
    }
    return $html . '</div>';
}

# ---- the falling-star field -------------------------------------------------
#
# A very quiet field of drifting specks for the inverted (dark) regions only: the
# footer and the page's dark bands. It is decorative and additive — the canvas is
# empty until pweevee.js paints it, so nothing shifts, nothing blocks rendering,
# and a visitor with JavaScript off or `prefers-reduced-motion: reduce` simply
# gets a plain dark surface.
#
# `data-starfield` is the hook pweevee.js looks for. The element is hidden from
# assistive technology because it carries no information.
sub starfield {
    return '<div class="starfield" data-starfield aria-hidden="true">'
         . '<canvas class="starfield__canvas"></canvas>'
         . '</div>';
}

# ---- the hero figure -------------------------------------------------------

# The official artwork, presented as what it is: an iOS app icon. A square frame,
# a hairline rule and a factual caption — no halo, no floor rings, no mirrored
# reflection, no drifting specks. The artwork carries the image on its own.
sub c_brand_showcase {
    # the showcase figure is the "App icon" slot: prefer the artwork that
    # actually depicts the shipped icon; brand art only as a fallback
    my $art = $APPICON{pweevee} // $ART{pweevee};
    my $inner;

    if ($art) {
        # One image, at its natural aspect, never recoloured or cropped.
        $inner = qq{<img class="showcase__art" src="@{[ attr($art) ]}" }
               . qq{alt="PwEevee project artwork" width="512" height="512" }
               . qq{decoding="async" fetchpriority="high">};
    } else {
        # Original stand-in, not a reproduction of the project artwork. It holds
        # the composition until the real asset is added to website/assets/brand/.
        # `currentColor` so it reads correctly on a light or a dark surface.
        $inner = '<div class="showcase__standin" role="img" aria-label="PwEevee mark">'
               . '<svg viewBox="0 0 64 64" aria-hidden="true" fill="none" stroke="currentColor" '
               . 'stroke-width="5" stroke-linecap="round" stroke-linejoin="round">'
               . '<path d="M18 27 32 16l14 11"/><path d="M18 40 32 29l14 11"/>'
               . '<path d="M20 50h24" stroke-width="3.5" stroke-opacity="0.55"/>'
               . '</svg></div>';
    }

    return join('',
        '<figure class="showcase">',
          '<div class="showcase__frame">', $inner, '</div>',
          '<figcaption class="showcase__caption">',
            '<span class="showcase__label">App icon</span>',
            '<span class="showcase__meta">PwEevee for iOS</span>',
          '</figcaption>',
        '</figure>');
}

# The small logo that labels a release/download panel. Since the icon revert it
# serves the app icon artwork for PwEevee; other projects use their artwork if
# present, and otherwise keep the text-only glyph.
sub project_badge {
    my ($p) = @_;
    my $src = ($p->{slug} // '') eq 'pweevee' ? ($APPICON{pweevee} // $ART{pweevee})
                                              : $ART{ $p->{slug} // '' };
    return qq{<img class="download__logo" src="@{[ attr($src) ]}" alt="" aria-hidden="true" }
         . qq{width="22" height="22" decoding="async"> }
        if $src;
    return '<span aria-hidden="true">' . h($p->{glyph} // '&#9670;') . '</span> ';
}

# Artwork for a project card / project hero, with the same "give it presence"
# treatment. Falls back to the project's glyph on a lit panel tile.
sub project_art {
    my ($p, $class) = @_;
    my $art = $ART{ $p->{slug} };
    return qq{<img class="$class" src="@{[ attr($art) ]}" alt="@{[ h($p->{name}) ]} artwork" }
         . qq{width="256" height="256" loading="lazy" decoding="async">}
        if $art;
    return '<span class="project-card__glyph" aria-hidden="true">'
         . h($p->{glyph} // '&#9670;') . '</span>';
}

sub c_data_freshness {
    my @parts;
    push @parts, 'GitHub release data generated ' . h(fmt_date($GH->{generated_at}))
        if $GH->{generated_at};
    push @parts, 'SideloadLabs AltSource read ' . h(fmt_date($AS->{generated_at}))
        if $AS->{generated_at};
    push @parts, 'Repository stats generated ' . h(fmt_date($STATS->{generated_at}))
        if $STATS->{generated_at};
    return 'Release data has not been generated yet' unless @parts;
    return join(' &middot; ', @parts);
}

# ---- the featured PwEevee release ------------------------------------------

# The home and downloads pages lead with PwEevee's newest GitHub release. It is
# the same renderer as any other project's release panel, asked for at feature
# size — so there is one implementation of "what a release looks like" and no
# second, locally-maintained notion of a current build.
sub c_hero_download {
    return release_panel($HOME_SLUG, featured => 1);
}

sub sha_block {
    my ($sha, $id) = @_;
    return '' unless defined $sha && $sha =~ /^[0-9a-f]{64}$/i;
    return join('',
        '<div class="download__files">',
          '<div class="kv__row">',
            '<span class="kv__k">SHA-256 of the file</span>',
            '<div class="hash">',
              qq{<code class="hash__value" id="@{[ h($id) ]}">}, h($sha), '</code>',
              qq{<button class="copy" type="button" data-copy-from="@{[ h($id) ]}" }
              . qq{aria-label="Copy the SHA-256 checksum"><span data-copy-label>Copy</span></button>},
            '</div>',
          '</div>',
        '</div>');
}

# ---- hero stats strip ------------------------------------------------------

# Facts about the current state of the ecosystem, each one read from the release
# data of the project it belongs to and labelled with that project. Nothing here
# is typed in, and a project whose data did not resolve simply does not appear.
sub c_build_facts {
    my @facts;

    my $own = latest_of($HOME_SLUG);
    push @facts, [ 'Latest release', ($own->{version_label} // $own->{version}) ] if $own;
    push @facts, [ 'Published', $own->{published_label} ] if $own;

    for my $slug (qw(spotipw eeveespotify)) {
        my $r = latest_of($slug) or next;
        my $p = $PROJECT{$slug} or next;
        push @facts, [ $p->{name}, ($r->{version_label} // $r->{version}) ];
    }

    return '' unless @facts;
    my $html = '<dl class="hero__stats reveal">';
    for my $f (@facts) {
        next unless defined $f->[1] && length $f->[1];
        $html .= '<div class="hero__stat"><dt>' . h($f->[0]) . '</dt>'
               . '<dd><span class="mono">' . h($f->[1]) . '</span></dd></div>';
    }
    return $html . '</dl>';
}

# ---- repository statistics band -------------------------------------------

# Live GitHub repository statistics rendered from website/data/stats.json.
# A project whose stats did not resolve does not appear at all: the band never
# shows a fabricated zero. The refresh timestamp is explicit; these numbers
# are as fresh as the most recent update run (every 15 minutes), not a
# real-time query.
sub c_project_stats {
    my @stats;

    my $own = $STP{$HOME_SLUG};
    if ($own && $own->{available}) {
        push @stats, [ 'Stars', $own->{stars}, 'stargazers on GitHub' ];
        push @stats, [ 'Forks', $own->{forks}, 'forks on GitHub' ];
        push @stats, [ 'Watchers', $own->{subscribers},
            'real watchers, via subscribers_count (GitHub counts watchers, not stars)' ];
        push @stats, [ 'Open issues & PRs', $own->{open_issues},
            'open issues and pull requests (GitHub counts PRs in open_issues_count)' ];
    }
    # Downloads: the band is about one repository, so it leads with that
    # repository's own verified GitHub total — GitHub counts every release,
    # tracked release history or not (this is the same number the public
    # shields.io badge displays). Fallbacks degrade honestly, each labelled:
    #   2. the tracked release-history sum for this slug alone.
    # The cross-project grand total is deliberately never shown here: upstream
    # releases used to outnumber ours 80:1 and made the figure meaningless for
    # this project — a number is not real just because it is large.
    my $own_slug  = $own->{slug} // $HOME_SLUG;
    my $own_total = $own->{downloads_total} // 0;
    my $own_sum   = $STATS->{downloads}{per_project}{$own_slug}{release_downloads} // 0;
    if ($own_total > 0) {
        push @stats, [ 'Release downloads', $own_total,
            'GitHub total across every release of this repository — the exact count the public badges show, not unique users or installs' ];
    }
    elsif ($own_sum > 0) {
        push @stats, [ 'Release downloads', $own_sum,
            'release-asset download_count summed over the release history tracked in releases.json (the GitHub total was unavailable on the last run), not unique users or installs' ];
    }

    unless (@stats) {
        my $why = (ref $own eq 'HASH' && !$own->{available})
            ? 'Repository statistics are unavailable right now'
            : 'Repository statistics have not been generated yet';
        return '<dl class="stats-band">'
             . '<div class="stats-band__missing">' . h($why) . '. '
             . 'GitHub is the authoritative place to check.</div></dl>';
    }

    my $html = '<dl class="stats-band">';
    for my $s (@stats) {
        $html .= '<div class="stats-band__item" title="' . h($s->[2] // '') . '">'
               . '<dt>' . h($s->[0]) . '</dt>'
               . '<dd class="stats-band__num">' . fmt_count(0 + ($s->[1] // 0)) . '</dd></div>';
    }
    $html .= '</dl>';

    if (my $gen = $STATS->{generated_at}) {
        $html .= '<p class="stats-band__fresh">'
               . 'Stats refreshed <time datetime="' . h($gen) . '">'
               . h(fmt_date($gen)) . '</time> (updated every 15 min). '
               . 'This page loads a shared snapshot; your browser never calls GitHub.</p>';
    }
    return $html;
}

# Pure display formatting over exact integers; nothing here rounds or estimates.
sub fmt_count {
    my ($n) = @_;
    $n = 0 + ($n // 0);
    my $s = sprintf('%d', $n);
    1 while $s =~ s/^(\d+)(\d{3})\z/$1,$2/;
    return $s;
}

# The newest published release for a project, or undef.
sub latest_of {
    my ($slug) = @_;
    my $g = $GHP{$slug} or return undef;
    return ref $g->{latest} eq 'HASH' ? $g->{latest} : undef;
}

# ---- the three project cards ----------------------------------------------

sub c_ecosystem {
    my $html = '<div class="grid grid--3">';
    for my $p (@PROJECTS) {
        $html .= project_card($p);
    }
    return $html . '</div>';
}

sub project_card {
    my ($p) = @_;
    my $slug = $p->{slug};
    my $g    = $GHP{$slug};
    my $rel  = ($g && ref $g->{latest} eq 'HASH') ? $g->{latest} : undef;
    my $accent = 'accent-' . ($p->{accent} // 'brand');

    my $role = $p->{role} eq 'integration'
        ? '<span class="badge badge--maintained"><span class="badge__dot"></span>'
          . h($p->{role_label} // 'Maintained here') . '</span>'
        : '<span class="badge badge--upstream">' . h($p->{role_label} // 'Upstream project') . '</span>';

    my $version = $rel
        ? '<span class="meta__v mono">' . h($rel->{version_label} // $rel->{version}) . '</span>'
        : '<span class="meta__v muted">unavailable</span>';
    my $date = $rel
        ? '<span class="meta__v">' . h($rel->{published_label}) . '</span>'
        : '<span class="meta__v muted">&mdash;</span>';

    my $repo_url = $g && $g->{repo_url} ? $g->{repo_url} : repo_url_of($p);
    my $rel_url  = $rel ? $rel->{url} : ($g ? $g->{releases_url} : undef);

    my @actions = (
        qq{<a class="btn btn--outline btn--sm" href="@{[ attr($p->{page}) ]}">Project page</a>},
    );
    push @actions, qq{<a class="btn btn--quiet btn--sm" href="@{[ attr($repo_url) ]}" rel="noopener">}
                 . github_icon() . '<span>Repository</span></a>' if $repo_url;
    push @actions, qq{<a class="btn btn--quiet btn--sm" href="@{[ attr($rel_url) ]}" rel="noopener">}
                 . 'Latest release</a>' if $rel_url && is_safe_url($rel_url);

    my $stale = ($g && $g->{stale})
        ? '<span class="badge badge--stale" title="GitHub could not be reached during the last '
          . 'update; this is the last known-good value">cached</span>' : '';

    # EeveeSpotify also has installable variants published through an AltSource,
    # which is a different kind of thing from a GitHub release. Both are shown,
    # each labelled with where it came from.
    my $extra = '';
    if (my $as = $ASP{$slug}) {
        $extra = '<div><span class="meta__k">AltSource variants</span>'
               . '<span class="meta__v">'
               . ($as->{available} && $as->{variant_count}
                     ? h($as->{variant_count}) . ' available'
                     : '<span class="muted">unavailable</span>')
               . '</span></div>';
    }

    return join('',
        qq{<article class="panel panel--hover project-card $accent reveal" data-reveal-group="eco">},
          '<div class="project-card__art">', project_art($p, 'project-card__icon'), '</div>',
          '<div class="project-card__top">',
            '<div>',
              '<h3 class="project-card__name">', h($p->{name}), '</h3>',
              '<div class="project-card__role">', $role, '</div>',
            '</div>',
          '</div>',
          '<p class="project-card__tagline">', h($p->{tagline}), '</p>',
          '<p class="project-card__body">', h($p->{description}), '</p>',
          '<div class="project-card__meta">',
            '<div><span class="meta__k">Latest GitHub release ', $stale, '</span>', $version, '</div>',
            '<div><span class="meta__k">Published</span>', $date, '</div>',
            $extra,
          '</div>',
          '<div class="project-card__actions">', join('', @actions), '</div>',
        '</article>');
}

sub repo_url_of {
    my ($p) = @_;
    my $gh = ref $p->{github} eq 'HASH' ? $p->{github} : return undef;
    return undef unless $gh->{owner} && $gh->{repo};
    return "https://github.com/$gh->{owner}/$gh->{repo}";
}

# ---- a GitHub release panel ----------------------------------------------

sub c_github_release {
    my ($slug) = @_;
    $slug or die "[[component:github-release]] needs a project slug\n";
    return release_panel($slug);
}

# One release, rendered from GitHub data.
#
# featured => 1 raises it to the page's headline download: an h2 instead of an
# h3, a slightly fuller action row. The rules about what may be offered are
# identical either way, because a featured download that does not exist is worse
# than a quiet one.
sub release_panel {
    my ($slug, %o) = @_;
    my $featured = $o{featured} ? 1 : 0;
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $g = $GHP{$slug};
    my $own = ($p->{role} // '') eq 'integration';

    # data file missing entirely -> let the JS fallback try, with a no-JS state inside
    unless ($g) {
        return qq{<div data-hydrate="@{[ h($slug) ]}">}
             . state_block('warn', '?', 'Release information is not available for ' . h($p->{name}) . '.',
                 'The generated release data has not been produced yet. The project\'s own GitHub '
               . 'releases page always has the authoritative list.',
                 [[ 'View releases on GitHub', (repo_url_of($p) // $OWN_REPO) . '/releases', 'outline' ]])
             . '</div>';
    }

    unless (ref $g->{latest} eq 'HASH') {
        return state_block('error', '!',
            'Release information is temporarily unavailable.',
            h($g->{error} // 'No published release could be read for this project.'),
            [[ 'View release on GitHub', ($g->{releases_url} // "$OWN_REPO/releases"), 'outline' ]]);
    }

    my $r = $g->{latest};
    my $accent = 'accent-' . ($p->{accent} // 'brand');

    # Only offer what actually exists: an asset must be present and its URL must
    # survive the safe-URL check, or no download button is rendered at all.
    my @assets = grep { is_safe_url($_->{download_url} // '') } @{ $r->{assets} || [] };
    my $primary = $assets[0];

    my @badges = ('<span class="badge badge--latest"><span class="badge__dot"></span>Latest release</span>');
    push @badges, '<span class="badge badge--prerelease">Prerelease</span>' if $r->{prerelease};
    push @badges, '<span class="badge badge--upstream">Upstream project</span>'
        if ($p->{role} // '') eq 'upstream';
    push @badges, '<span class="badge badge--stale">Cached data</span>' if $g->{stale};

    my $size = $featured ? ' btn--lg' : ' btn--lg';
    my $action = $primary
        ? qq{<a class="btn btn--primary$size btn--stack" href="@{[ attr($primary->{download_url}) ]}" rel="noopener" }
          . qq{aria-label="Download @{[ h($primary->{name}) ]} from the @{[ h($p->{name}) ]} GitHub release">}
          . '<span>Download ' . h(kind_label($primary)) . '</span>'
          . '<span class="btn__sub">' . h($primary->{size_label})
          . ($own ? ' &middot; unsigned' : '') . '</span></a>'
        : qq{<a class="btn btn--outline$size" href="@{[ attr($r->{url}) ]}" rel="noopener">}
          . github_icon() . '<span>View release on GitHub</span></a>';

    # No asset means no download, stated plainly rather than as a dead button.
    my $no_asset = $primary ? '' : join('',
        '<div class="state state--warn">',
          '<div class="state__icon" aria-hidden="true">!</div>',
          '<h3>Download currently unavailable.</h3>',
          '<p>', ($own
              ? 'The newest published release has no attached package right now. The release page on '
              . 'GitHub is the authoritative place to check, and a download appears here as soon as '
              . 'an asset is published.'
              : 'The upstream project published this release without attached files. The release page '
              . 'on GitHub has the notes and any instructions the author provided.'), '</p>',
          '<div class="state__actions">',
            qq{<a class="btn btn--outline" href="@{[ attr($r->{url}) ]}" rel="noopener">}
            . 'View release on GitHub</a>',
          '</div>',
        '</div>');

    my $stale_note = $g->{stale} ? join('',
        '<p class="small muted">GitHub could not be reached during the last update, so this is the '
      . 'last known-good release information for this project.</p>') : '';

    my $heading = $featured ? 'h2' : 'h3';

    return join('',
        qq{<div class="panel panel--raised panel--hover download $accent reveal">},
          '<div class="download__head">',
            '<div class="download__ident">',
              '<span class="download__project">', project_badge($p),
                h($p->{name}),
                ($featured ? ' release' : ''), '</span>',
              "<$heading class=\"download__version\">", h($r->{version_label} // $r->{version}),
                "</$heading>",
              ($r->{name} && $r->{name} ne $r->{version}
                  ? '<p class="download__title">' . h($r->{name}) . '</p>' : ''),
              '<p class="download__date">Released ', h($r->{published_label}), '</p>',
            '</div>',
            '<div class="download__badges">', join('', @badges), '</div>',
          '</div>',
          $no_asset,
          $stale_note,
          '<div class="download__actions">',
            $action,
            qq{<a class="btn btn--outline" href="@{[ attr($r->{url}) ]}" rel="noopener">Release notes</a>},
            ($featured ? '<a class="btn btn--outline" href="/releases">Release history</a>' : ''),
            qq{<a class="btn btn--quiet" href="@{[ attr($g->{repo_url}) ]}" rel="noopener">}, github_icon(),
              '<span>GitHub repository</span></a>',
          '</div>',
          asset_list(\@assets),
          ($primary ? sha_block($primary->{sha256}, "sha-$slug") : ''),
          gh_meta($p, $g, $r),
          notes_details($r),
        '</div>');
}

# ---- AltSource variants ---------------------------------------------------

# The installable IPA variants a project publishes through an AltStore-format
# source. This is deliberately NOT styled or worded as a GitHub release: it is a
# separate source of a separate kind of artefact, and the panel says so, names
# the publisher, and links the source manifest itself.
sub c_altsource_variants {
    my ($slug) = @_;
    $slug or die "[[component:altsource-variants]] needs a project slug\n";
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $as = $ASP{$slug};
    my $decl = ref $p->{altsource} eq 'HASH' ? $p->{altsource} : {};

    unless ($as && $as->{available} && @{ $as->{variants} || [] }) {
        my $why = ($as && $as->{error})
            ? h($as->{error})
            : 'The variant list has not been generated yet. Run <code>update-altsource.pl</code> to '
            . 'fetch it.';
        my @actions;
        push @actions, [ 'Open the source manifest', ($as->{source_url} // $decl->{url}), 'outline' ]
            if ($as && $as->{source_url}) || $decl->{url};
        return state_block('warn', '?',
            'Variant downloads are temporarily unavailable.', $why, \@actions);
    }

    my $accent = 'accent-' . ($p->{accent} // 'neutral');
    my $html = '';

    for my $fam (@{ $as->{families} }) {
        my @cards = map { variant_card($_, $accent) } @{ $fam->{variants} };

        $html .= join('',
            qq{<section class="variant-family $accent reveal" data-reveal-group="variants">},
              '<div class="variant-family__head">',
                '<div>',
                  '<h3 class="variant-family__name">', h($fam->{label}), '</h3>',
                  ($fam->{note} ? '<p class="variant-family__note">' . h($fam->{note}) . '</p>' : ''),
                '</div>',
                '<dl class="variant-family__facts">',
                  ($fam->{spotify_version}
                      ? '<div><dt>Spotify</dt><dd class="mono">' . h($fam->{spotify_version})
                      . '</dd></div>' : ''),
                  ($fam->{eevee_version}
                      ? '<div><dt>EeveeSpotify</dt><dd class="mono">' . h($fam->{eevee_version})
                      . '</dd></div>' : ''),
                  ($fam->{updated_label}
                      ? '<div><dt>Published</dt><dd>' . h($fam->{updated_label}) . '</dd></div>' : ''),
                '</dl>',
              '</div>',
              '<div class="variant-grid">', join('', @cards), '</div>',
            '</section>');
    }

    return $html;
}

sub variant_card {
    my ($v, $accent) = @_;

    # A variant with no usable URL is not offered. The generator already drops
    # those, so this is the second guard rather than the only one.
    my $has_url = is_safe_url($v->{download_url} // '');

    my $badge = $v->{patched}
        ? '<span class="badge badge--prerelease">Patched</span>'
        : '<span class="badge badge--upstream">Standard</span>';

    my @rows = (
        [ 'Variant',      $v->{variant_label},   0 ],
        [ 'Spotify',      $v->{spotify_version}, 1 ],
        [ 'EeveeSpotify', $v->{eevee_version},   1 ],
        [ 'Size',         $v->{size_label},      0 ],
        [ 'Published',    $v->{date_label},      0 ],
    );
    my $meta = '<dl class="meta">';
    for my $r (@rows) {
        my ($k, $val, $mono) = @$r;
        next unless defined $val && length $val;
        $meta .= '<div><dt>' . h($k) . '</dt><dd class="meta__v' . ($mono ? ' mono' : '') . '">'
               . h($val) . '</dd></div>';
    }
    $meta .= '</dl>';

    my $action = $has_url
        ? qq{<a class="btn btn--primary btn--stack" href="@{[ attr($v->{download_url}) ]}" rel="noopener" }
          . qq{aria-label="Download @{[ h($v->{name}) ]} (@{[ h($v->{variant_label}) ]}) from the SideloadLabs source">}
          . '<span>Download IPA</span>'
          . '<span class="btn__sub">' . h($v->{size_label}) . ' &middot; ' . h(lc $v->{variant_label})
          . '</span></a>'
        : '<p class="small muted mb-0">Download currently unavailable for this variant.</p>';

    return join('',
        qq{<article class="panel panel--hover variant $accent">},
          '<div class="variant__head">',
            '<div class="variant__ident">',
              '<h4 class="variant__name">', h($v->{variant_label}), '</h4>',
              '<p class="variant__source-name mono">', h($v->{name}), '</p>',
            '</div>',
            '<div class="variant__badges">', $badge, '</div>',
          '</div>',
          '<p class="variant__note">', h($v->{variant_note}), '</p>',
          $meta,
          '<div class="variant__actions">', $action, '</div>',
          ($v->{description}
              ? '<details class="disclose"><summary>Description from the source</summary>'
              . '<div class="disclose__body"><p class="small muted mb-0">'
              . h($v->{description}) . '</p>'
              . ($v->{release_notes}
                    ? '<div class="kv__row"><span class="kv__k">Release description</span>'
                    . '<span class="kv__v">' . h($v->{release_notes}) . '</span></div>' : '')
              . ($v->{bundle_id}
                    ? '<div class="kv__row"><span class="kv__k">Bundle identifier</span>'
                    . '<span class="kv__v mono break">' . h($v->{bundle_id}) . '</span></div>' : '')
              . ($v->{icon_url}
                    ? '<div class="kv__row"><span class="kv__k">Icon</span>'
                    . qq{<span class="kv__v"><a class="break" href="@{[ attr($v->{icon_url}) ]}" }
                    . 'rel="noopener nofollow">' . h($v->{icon_url}) . '</a></span></div>' : '')
              . '</div></details>'
              : ''),
        '</article>');
}

# Who published the AltSource, said plainly. The site does not own it and does
# not mirror it; it reads it and links back to it.
sub c_altsource_source {
    my ($slug) = @_;
    $slug or die "[[component:altsource-source]] needs a project slug\n";
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $as = $ASP{$slug};
    my $decl = ref $p->{altsource} eq 'HASH' ? $p->{altsource} : {};

    my $name = ($as && $as->{source_name}) || $decl->{name} || 'AltSource';
    my $url  = ($as && $as->{source_url})  || $decl->{url};
    my $repo = ($as && $as->{repo_url})    || $decl->{repo_url};
    my $nwo  = ($as && $as->{repo})        || $decl->{repo};

    my @rows;
    push @rows, [ 'Source', h($name) ];
    push @rows, [ 'Identifier', '<span class="mono">' . h($as->{source_identifier}) . '</span>' ]
        if $as && $as->{source_identifier};
    push @rows, [ 'Published by', h($as->{variants}[0]{developer}) ]
        if $as && ref $as->{variants} eq 'ARRAY' && @{ $as->{variants} }
           && $as->{variants}[0]{developer};
    push @rows, [ 'Repository',
                  ($repo && is_safe_url($repo)
                      ? qq{<a class="mono break" href="@{[ attr($repo) ]}" rel="noopener">}
                        . h($nwo // $repo) . '</a>'
                      : '<span class="mono break">' . h($nwo // '(not published)') . '</span>') ];
    push @rows, [ 'Manifest',
                  ($url && is_safe_url($url)
                      ? qq{<a class="mono break" href="@{[ attr($url) ]}" rel="noopener">}
                        . h($url) . '</a>'
                      : '<span class="muted">unavailable</span>') ];
    push @rows, [ 'Variants listed',
                  h(($as && $as->{variant_count}) ? $as->{variant_count} : 0) ]
        if $as;
    push @rows, [ 'Kind', 'AltStore-format source manifest — not a GitHub release' ];
    push @rows, [ 'Subtitle', h($as->{source_subtitle}) ] if $as && $as->{source_subtitle};
    push @rows, [ 'Description', h($as->{source_description}) ]
        if $as && $as->{source_description};
    # The icon is referenced, not embedded: the site's Content-Security-Policy is
    # img-src 'self', so no third-party image is ever loaded into the page.
    push @rows, [ 'Source icon',
                  qq{<a class="mono break" href="@{[ attr($as->{source_icon_url}) ]}" }
                  . 'rel="noopener nofollow">' . h($as->{source_icon_url}) . '</a>' ]
        if $as && $as->{source_icon_url} && is_safe_url($as->{source_icon_url});

    my $kv = '<div class="kv mt-5">';
    for my $r (@rows) {
        $kv .= '<div class="kv__row"><span class="kv__k">' . $r->[0] . '</span>'
             . '<span class="kv__v">' . $r->[1] . '</span></div>';
    }
    $kv .= '</div>';

    my $note = ($as && $as->{note}) || $decl->{note};

    return join('',
        '<div class="panel pad accent-neutral">',
          '<p class="eyebrow">Source</p>',
          '<h3>Where these variants come from</h3>',
          ($note ? '<p class="muted mt-4 measure">' . h($note) . '</p>' : ''),
          $kv,
          ($as && $as->{stale}
              ? '<p class="small muted mt-4 mb-0">The source could not be reached during the last '
              . 'update, so this is the last known-good variant list.</p>' : ''),
        '</div>');
}

sub kind_label {
    my ($a) = @_;
    my %label = (ipa => 'IPA', tipa => 'TIPA', deb => 'DEB', archive => 'archive', other => 'file');
    return $label{ $a->{kind} // 'other' } // 'file';
}

sub asset_list {
    my ($assets) = @_;
    return '' unless @$assets;
    my $html = '<div class="download__files">';
    for my $a (@$assets) {
        next unless is_safe_url($a->{download_url});
        $html .= join('',
            '<div class="asset">',
              '<span class="asset__kind" aria-hidden="true">', h(lc kind_label($a)), '</span>',
              '<span class="asset__info">',
                '<span class="asset__name">', h($a->{name}), '</span>',
                '<span class="asset__sub">', h($a->{size_label}),
                  ($a->{sha256} ? ' &middot; sha256 ' . h(substr($a->{sha256}, 0, 16)) . '&hellip;' : ''),
                '</span>',
              '</span>',
              '<span class="asset__action">',
                qq{<a class="btn btn--outline btn--sm" href="@{[ attr($a->{download_url}) ]}" rel="noopener" }
                . qq{aria-label="Download @{[ h($a->{name}) ]}">Download</a>},
              '</span>',
            '</div>');
    }
    return $html . '</div>';
}

sub gh_meta {
    my ($p, $g, $r) = @_;
    my @rows = (
        [ 'Version',   ($r->{version_label} // $r->{version}), 1 ],
        [ 'Published', $r->{published_label}, 0 ],
        [ 'Repository', $g->{repo}, 1 ],
        [ 'Files',     scalar(@{ $r->{assets} || [] }) . ' asset'
                       . (@{ $r->{assets} || [] } == 1 ? '' : 's'), 0 ],
        [ 'Source',    'GitHub releases API', 0 ],
    );
    my $html = '<dl class="meta">';
    for my $r2 (@rows) {
        my ($k, $v, $mono) = @$r2;
        next unless defined $v && length $v;
        $html .= '<div><dt>' . h($k) . '</dt><dd class="meta__v' . ($mono ? ' mono' : '') . '">'
               . h($v) . '</dd></div>';
    }
    return $html . '</dl>';
}

sub notes_details {
    my ($r) = @_;
    my $notes = notes_to_html($r->{notes}, limit => 5000);
    return '' unless length $notes;
    return '<details class="disclose"><summary>Release notes from the author</summary>'
         . '<div class="disclose__body"><div class="notes">' . $notes . '</div></div></details>';
}

# ---- combined release history --------------------------------------------

# Every published release across the ecosystem, read from GitHub only.
#
# The filter is rendered in its DEFAULT state rather than "show everything":
# PwEevee is pre-selected, non-PwEevee entries carry the hidden attribute, and
# month sections that end up empty are hidden too. That means the page arrives
# already filtered, with no flash of the wrong content and no dependence on
# JavaScript to reach the intended default. pweevee.js then takes over: it
# re-applies the filter, keeps ?project= in the URL, and answers back/forward.
sub c_release_history {
    my @entries;

    for my $p (@PROJECTS) {
        my $g = $GHP{ $p->{slug} } or next;
        for my $r (@{ $g->{history} || [] }) {
            push @entries, {
                epoch  => ($r->{published_epoch} || 0),
                slug   => $p->{slug},
                search => lc join(' ', ($p->{name} // ''), ($p->{slug} // ''),
                                       ($r->{version} // ''), ($r->{name} // '')),
                html   => history_card($p, $g, $r),
            };
        }
    }

    unless (@entries) {
        return state_block('error', '!', 'Release information is temporarily unavailable.',
            'No release data could be read. Run <code>update-releases.pl</code> to regenerate it, '
          . 'or go straight to the repositories.',
            [[ 'View releases on GitHub', "$OWN_REPO/releases", 'outline' ]]);
    }

    @entries = sort { $b->{epoch} <=> $a->{epoch} } @entries;

    my $default = (grep { $_->{slug} eq $HOME_SLUG } @entries) ? $HOME_SLUG : 'all';
    my $shown   = $default eq 'all' ? scalar(@entries)
                                    : scalar(grep { $_->{slug} eq $default } @entries);

    # ---- filter toolbar ---------------------------------------------------
    my @chip_defs = ([ 'all', 'All projects' ]);
    for my $p (@PROJECTS) {
        next unless grep { $_->{slug} eq $p->{slug} } @entries;
        push @chip_defs, [ $p->{slug}, $p->{name} ];
    }

    my $chips = '';
    for my $c (@chip_defs) {
        my ($value, $label) = @$c;
        my $on = $value eq $default ? 'true' : 'false';
        $chips .= qq{<button class="chip" type="button" data-filter="@{[ h($value) ]}" }
                . qq{aria-pressed="$on">@{[ h($label) ]}</button>};
    }

    my $toolbar = join('',
        '<div class="toolbar">',
          '<div class="chips" role="group" aria-label="Filter releases by project">', $chips, '</div>',
          '<div class="row">',
            '<label class="search">',
              '<span class="visually-hidden">Search releases by version or project</span>',
              '<svg class="search__icon" viewBox="0 0 16 16" aria-hidden="true" fill="none" '
              . 'stroke="currentColor" stroke-width="1.6"><circle cx="6.8" cy="6.8" r="4.6"/>'
              . '<path d="m10.4 10.4 3.2 3.2"/></svg>',
              '<input class="search__input" type="search" data-filter-search '
              . 'placeholder="Search versions…" autocomplete="off">',
            '</label>',
            '<span class="small dim" data-filter-count aria-live="polite">',
              filter_count_text($shown, scalar @entries), '</span>',
          '</div>',
        '</div>');

    # ---- grouped timeline, pre-filtered to the default --------------------
    my $html = qq{<div data-filter-scope data-filter-default="@{[ h($default) ]}" }
             . qq{data-filter-param="project">$toolbar};

    # group by calendar month, newest first
    my @groups;
    my $current = '';
    for my $e (@entries) {
        my $month = month_key($e->{epoch});
        push @groups, { month => $month, items => [] } if $month ne $current;
        $current = $month;
        push @{ $groups[-1]{items} }, $e;
    }

    my $first_visible = 1;
    for my $grp (@groups) {
        my $visible = grep { $default eq 'all' || $_->{slug} eq $default } @{ $grp->{items} };
        $html .= '<section data-release-group' . ($visible ? '' : ' hidden') . '>'
        # h2: the month groups the releases under it, so it is a section of the
        # page, and the release cards inside it are the h3 level. As an h3 it sat
        # at the same level as the cards it contains and skipped a level after
        # the page's h1.
               . '<div class="group-head"><h2>' . h($grp->{month}) . '</h2>'
               . '<span class="group-head__line" aria-hidden="true"></span></div>'
               . '<div class="timeline">';
        for my $e (@{ $grp->{items} }) {
            my $on = ($default eq 'all' || $e->{slug} eq $default) ? 1 : 0;
            my $mark = ($on && $first_visible) ? ' timeline__item--first' : '';
            $first_visible = 0 if $on;
            $html .= qq{<div class="timeline__item$mark" data-release-item }
                   . qq{data-project="@{[ h($e->{slug}) ]}" data-search="@{[ h($e->{search}) ]}"}
                   . ($on ? '' : ' hidden') . '>'
                   . $e->{html} . '</div>';
        }
        $html .= '</div></section>';
    }

    $html .= '<div data-filter-empty hidden>'
           . state_block('warn', '?', 'Nothing matches that filter.',
               'Try a different project or clear the search box.', [])
           . '</div>';

    return $html . '</div>';
}

# Kept identical to the wording pweevee.js produces, so the count does not
# change phrasing the moment JavaScript takes over.
sub filter_count_text {
    my ($shown, $total) = @_;
    return $shown == $total ? "$total releases" : "$shown of $total releases";
}

sub month_key {
    my ($epoch) = @_;
    return 'Undated' unless $epoch;
    my @t = gmtime($epoch);
    my @m = qw(January February March April May June July August September October November December);
    return sprintf('%s %d', $m[ $t[4] ], $t[5] + 1900);
}

sub history_card {
    my ($p, $g, $r) = @_;
    my $accent = 'accent-' . ($p->{accent} // 'brand');
    my @assets = grep { is_safe_url($_->{download_url}) } @{ $r->{assets} || [] };
    my $primary = $assets[0];
    my $is_latest = ref $g->{latest} eq 'HASH'
                 && ($g->{latest}{version} // '') eq ($r->{version} // '');

    my @badges;
    push @badges, '<span class="badge badge--latest"><span class="badge__dot"></span>Latest</span>'
        if $is_latest;
    push @badges, '<span class="badge badge--prerelease">Prerelease</span>' if $r->{prerelease};
    push @badges, '<span class="badge badge--upstream">Upstream</span>'
        if ($p->{role} // '') eq 'upstream';

    my $action = $primary
        ? qq{<a class="btn btn--outline btn--sm" href="@{[ attr($primary->{download_url}) ]}" rel="noopener" }
          . qq{aria-label="Download @{[ h($primary->{name}) ]} from @{[ h($p->{name}) ]} }
          . qq{@{[ h($r->{version_label} // $r->{version}) ]}">}
          . 'Download ' . h(kind_label($primary)) . '</a>'
        : '';

    # The filter attributes live on the timeline wrapper (see c_release_history),
    # not here: hiding the wrapper also hides the timeline marker beside it.
    return join('',
        qq{<article class="panel release $accent">},
          '<div class="release__head">',
            '<div class="release__ident">',
              '<h3 class="release__version">', h($p->{name}), ' ',
                h($r->{version_label} // $r->{version}), '</h3>',
              ($r->{name} && $r->{name} ne $r->{version}
                  ? '<p class="release__name">' . h($r->{name}) . '</p>' : ''),
              '<p class="release__when">', h($r->{published_label}),
                (@assets ? ' &middot; ' . scalar(@assets) . ' file'
                           . (@assets == 1 ? '' : 's') : ' &middot; no files'), '</p>',
            '</div>',
            (@badges ? '<div class="release__badges">' . join('', @badges) . '</div>' : ''),
          '</div>',
          ($r->{summary} ? '<p class="release__summary">' . h($r->{summary}) . '</p>' : ''),
          '<div class="release__actions">',
            $action,
            qq{<a class="btn btn--quiet btn--sm" href="@{[ attr($r->{url}) ]}" rel="noopener">}
            . 'GitHub release</a>',
          '</div>',
          (@assets ? '<details class="disclose"><summary>' . scalar(@assets) . ' file'
                     . (@assets == 1 ? '' : 's') . '</summary><div class="disclose__body">'
                     . asset_list(\@assets) . '</div></details>' : ''),
          notes_details($r),
        '</article>');
}

# ---- project pages -------------------------------------------------------

sub c_project_hero {
    my ($slug) = @_;
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $g = $GHP{$slug};
    my $rel = ($g && ref $g->{latest} eq 'HASH') ? $g->{latest} : undef;
    my $accent = 'accent-' . ($p->{accent} // 'brand');

    my $role = ($p->{role} // '') eq 'integration'
        ? '<span class="badge badge--maintained"><span class="badge__dot"></span>'
          . h($p->{role_label} // 'Maintained here') . '</span>'
        : '<span class="badge badge--upstream">' . h($p->{role_label} // 'Upstream project') . '</span>';

    my @stats;
    push @stats, [ 'Latest release', ($rel->{version_label} // $rel->{version}) ] if $rel;
    push @stats, [ 'Published', $rel->{published_label} ] if $rel;
    push @stats, [ 'Repository', ($g ? $g->{repo} : ($p->{github}{owner} . '/' . $p->{github}{repo})) ]
        if $g || (ref $p->{github} eq 'HASH' && $p->{github}{owner});

    my $stats = '';
    if (@stats) {
        $stats = '<dl class="hero__stats">';
        for my $s (@stats) {
            next unless defined $s->[1] && length $s->[1];
            $stats .= '<div class="hero__stat"><dt>' . h($s->[0]) . '</dt>'
                    . '<dd><span class="mono">' . h($s->[1]) . '</span></dd></div>';
        }
        $stats .= '</dl>';
    }

    my $repo = $g && $g->{repo_url} ? $g->{repo_url} : repo_url_of($p);

    my $art = '<div class="hero__figure"><div class="project-hero__art">'
            . project_art($p, 'project-hero__icon')
            . '</div></div>';

    return join('',
        qq{<section class="hero $accent"><div class="wrap">},
          '<div class="hero__grid">',
            '<div class="hero__copy">',
              '<p class="eyebrow">', h($p->{role_label} // 'Project'), '</p>',
              '<h1 class="display">', h($p->{name}), '</h1>',
              '<p class="lead mt-5">', h($p->{tagline}), ' ', h($p->{description}), '</p>',
              '<div class="row mt-5">', $role, '</div>',
              '<div class="btn-row hero__actions">',
                ($p->{slug} eq 'pweevee'
                    ? '<a class="btn btn--primary btn--lg" href="/downloads">Downloads</a>'
                    : ($rel ? qq{<a class="btn btn--primary btn--lg" href="@{[ attr($rel->{url}) ]}" rel="noopener">}
                              . 'Latest release</a>' : '')),
                ($repo ? qq{<a class="btn btn--outline btn--lg" href="@{[ attr($repo) ]}" rel="noopener">}
                         . github_icon() . '<span>Repository</span></a>' : ''),
                '<a class="btn btn--quiet btn--lg" href="/projects">All projects</a>',
              '</div>',
              '<p class="hero__note">', h($p->{relationship}), '</p>',
            '</div>',
            $art,
          '</div>',
          $stats,
        '</div></section>');
}

sub c_project_links {
    my ($slug) = @_;
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $g = $GHP{$slug};
    my $repo = $g && $g->{repo_url} ? $g->{repo_url} : repo_url_of($p);

    my $authors = '';
    for my $a (@{ $p->{authors} || [] }) {
        my $name = $a->{url} && is_safe_url($a->{url})
            ? qq{<a href="@{[ attr($a->{url}) ]}" rel="noopener">@{[ h($a->{name}) ]}</a>}
            : h($a->{name});
        $authors .= '<li>' . $name
                  . ($a->{handle} ? ' <span class="dim">(' . h($a->{handle}) . ')</span>' : '')
                  . ($a->{note} ? ' — <span class="muted">' . h($a->{note}) . '</span>' : '')
                  . '</li>';
    }

    my $support = '';
    if (ref $p->{support} eq 'HASH') {
        my $s = $p->{support};
        # A project can have several upstream parties, so the row is about
        # supporting upstream rather than "the author" singular.
        my $slabel = (($p->{role} // '') eq 'integration') ? 'Support' : 'Support upstream';
        $support = $s->{url} && is_safe_url($s->{url})
            ? qq{<div class="kv__row"><span class="kv__k">$slabel</span>}
              . qq{<span class="kv__v"><a href="@{[ attr($s->{url}) ]}" rel="noopener">}
              . h($s->{label} // 'Donate') . '</a>'
              . ($s->{note} ? ' — <span class="muted">' . h($s->{note}) . '</span>' : '')
              . '</span></div>'
            : qq{<div class="kv__row"><span class="kv__k">$slabel</span>}
              . '<span class="kv__v muted">' . h($s->{note} // 'No official donation link was found.')
              . '</span></div>';
    }

    my @links;
    push @links, [ 'Repository', $repo, 'Browse the source' ] if $repo;
    push @links, [ 'Releases', ($g ? $g->{releases_url} : ($repo ? "$repo/releases" : undef)),
                   'Every published release' ];
    push @links, [ 'Issues', ($g ? $g->{issues_url} : ($repo ? "$repo/issues" : undef)),
                   'Report a problem to the right project' ];

    my $cards = '';
    for my $l (@links) {
        next unless $l->[1] && is_safe_url($l->[1]);
        $cards .= qq{<a class="feature" href="@{[ attr($l->[1]) ]}" rel="noopener">}
                . '<span class="feature__icon" aria-hidden="true">' . github_icon() . '</span>'
                . '<h3>' . h($l->[0]) . '</h3>'
                . '<p>' . h($l->[2]) . '</p>'
                . '<span class="small mono dim break">'
                . h($l->[1]) . '</span></a>';
    }

    # "Upstream authors" rather than a bare "Authors", so the list can never be
    # read as covering PwEevee's own integration work. The row that follows says
    # what PwEevee does with the component, which is a different claim.
    my $upstream = ($p->{role} // '') ne 'integration';
    my $authors_label = $upstream ? 'Upstream authors' : 'Authors';

    return join('',
        '<div class="grid grid--3">', $cards, '</div>',
        '<div class="panel pad mt-6"><div class="kv">',
          ($authors ? '<div class="kv__row"><span class="kv__k">' . $authors_label . '</span>'
                      . '<span class="kv__v"><ul class="list-plain">' . $authors . '</ul></span></div>' : ''),
          ($p->{package} ? '<div class="kv__row"><span class="kv__k">Upstream package</span>'
                           . '<span class="kv__v">' . h($p->{package}) . '</span></div>' : ''),
          '<div class="kv__row"><span class="kv__k">License</span>'
            . '<span class="kv__v">' . h($p->{license}) . '</span></div>',
          '<div class="kv__row"><span class="kv__k">How PwEevee uses it</span>'
            . '<span class="kv__v">' . h($p->{contribution}) . '</span></div>',
          $support,
        '</div></div>');
}

# ---- PwEevee's own contribution, stated apart from upstream credit ----------
#
# An upstream component and the integration built around it are two different
# pieces of work by two different parties. Listing only the upstream authors
# invites the reader to assume they also produced the packaging shown here, so
# the data model carries PwEevee's side explicitly and this renders it next to
# the upstream block rather than mixed into it.
sub c_pweevee_work {
    my ($slug) = @_;
    $slug or die "[[component:pweevee-work]] needs a project slug\n";
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $w = ref $p->{pweevee_work} eq 'HASH' ? $p->{pweevee_work} : undef;
    return '' unless $w && ref $w->{items} eq 'ARRAY' && @{ $w->{items} };

    my $items = '';
    for my $item (@{ $w->{items} }) {
        # "Label — detail": the label is the claim, the detail is the evidence
        my ($label, $detail) = split /\s+—\s+/, $item, 2;
        $items .= '<div class="feature accent-brand"><h3>' . h($label) . '</h3>'
                . ($detail ? '<p class="mb-0">' . h($detail) . '</p>' : '')
                . '</div>';
    }

    return join('',
        '<div class="grid grid--2">', $items, '</div>',
        ($w->{summary} ? '<p class="note mt-6">' . h($w->{summary}) . '</p>' : ''));
}

sub c_project_highlights {
    my ($slug) = @_;
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my @h = @{ $p->{highlights} || [] };
    return '' unless @h;
    my $accent = 'accent-' . ($p->{accent} // 'brand');
    # No decorative glyph: the accent rule along the top of each block already
    # marks it, and repeating one diamond fourteen times is noise, not design.
    my $html = qq{<div class="grid grid--2 $accent">};
    for my $item (@h) {
        $html .= '<div class="feature"><p class="mb-0 ink">' . h($item) . '</p></div>';
    }
    return $html . '</div>';
}

sub c_project_notes {
    my ($slug) = @_;
    my $p = $PROJECT{$slug} or die "unknown project slug '$slug'\n";
    my $gh = ref $p->{github} eq 'HASH' ? $p->{github} : {};
    my @blocks;

    if ($gh->{note}) {
        push @blocks, '<div class="panel pad"><h3>Repository history</h3>'
                    . '<p class="muted mt-4 mb-0">' . h($gh->{note}) . '</p></div>';
    }
    for my $n (@{ $p->{notes} || [] }) {
        push @blocks, '<div class="panel pad"><h3>Versions</h3>'
                    . '<p class="muted mt-4 mb-0">' . h($n) . '</p></div>';
    }
    return '' unless @blocks;
    return '<div class="split">' . join('', @blocks) . '</div>';
}

# ---- shared blocks -------------------------------------------------------

# Upstream credit cards, rendered from the data model so the author, repository
# and license facts exist in exactly one place.
sub c_credits_upstream {
    my @cards;
    for my $p (@PROJECTS) {
        next if ($p->{role} // '') eq 'integration';
        my $g = $GHP{ $p->{slug} };
        my $repo = $g && $g->{repo_url} ? $g->{repo_url} : repo_url_of($p);
        my $gh = ref $p->{github} eq 'HASH' ? $p->{github} : {};
        my $accent = 'accent-' . ($p->{accent} // 'brand');

        my @rows;
        my @authors;
        for my $a (@{ $p->{authors} || [] }) {
            my $name = ($a->{url} && is_safe_url($a->{url}))
                ? qq{<a href="@{[ attr($a->{url}) ]}" rel="noopener">@{[ h($a->{name}) ]}</a>}
                : h($a->{name});
            push @authors, $name
                . ($a->{handle} ? ' <span class="dim">(' . h($a->{handle}) . ')</span>' : '')
                . ($a->{note} ? ' — <span class="muted">' . h($a->{note}) . '</span>' : '');
        }
        push @rows, [ 'Author &amp; maintainer', join('<br>', @authors) ] if @authors;
        push @rows, [ 'Package used', h($p->{package}) ] if $p->{package};
        push @rows, [ 'Repository',
                      ($repo ? qq{<a href="@{[ attr($repo) ]}" rel="noopener">}
                               . h($repo =~ s{^https://}{}r) . '</a>' : '(none published)')
                      . ($gh->{note} ? ' — <span class="muted">' . h($gh->{note}) . '</span>' : '') ];
        push @rows, [ 'What it is', h($p->{description}) ];
        push @rows, [ 'License', h($p->{license}) ];

        my $s = ref $p->{support} eq 'HASH' ? $p->{support} : {};
        push @rows, [ 'Support the author',
            ($s->{url} && is_safe_url($s->{url}))
                ? qq{<a href="@{[ attr($s->{url}) ]}" rel="noopener">@{[ h($s->{label} // 'Donate') ]}</a>}
                  . ($s->{note} ? ' — <span class="muted">' . h($s->{note}) . '</span>' : '')
                : '<span class="muted">' . h($s->{note} // 'No official donation link was found.')
                  . '</span>' ];

        my $kv = '<div class="kv mt-5">';
        for my $r (@rows) {
            $kv .= '<div class="kv__row"><span class="kv__k">' . $r->[0] . '</span>'
                 . '<span class="kv__v">' . $r->[1] . '</span></div>';
        }
        $kv .= '</div>';

        push @cards, qq{<div class="panel panel--hover pad $accent">}
                   . '<h3>' . h($p->{name}) . '</h3>' . $kv . '</div>';
    }
    return '<div class="grid grid--2">' . join('', @cards) . '</div>';
}

# The licence list on the legal page, also from the data model.
sub c_license_list {
    my $html = '<ul>';
    for my $p (@PROJECTS) {
        $html .= '<li><strong>' . h($p->{name})
               . (($p->{role} // '') eq 'integration' ? ' (this project)' : '')
               . '</strong> — ' . h($p->{license}) . '</li>';
    }
    for my $d (@{ $MODEL->{dependencies} || [] }) {
        next if ($d->{name} // '') eq 'Spotify';
        $html .= '<li><strong>' . h($d->{name}) . '</strong> — ' . h($d->{note})
               . ' Its own license remains applicable.</li>';
    }
    return $html . '</ul>';
}

# ---- starring the project -------------------------------------------------
#
# The one thing this project asks for, and it costs nothing. The repository URL
# comes from own_repo_url() — the same value the nav and footer use — so there is
# no second place for it to go stale, and no chance of inventing one.
sub c_star_project {
    my $repo = $OWN_REPO;
    return '' unless $repo && is_safe_url($repo);

    return join('',
        '<div class="panel panel--raised pad-lg accent-brand">',
          '<h3>Enjoying PwEevee?</h3>',
          '<p class="muted mt-4 measure">',
            'Star the project on GitHub to help more people discover it — and to show that this ',
            'project matters to you.',
          '</p>',
          '<div class="btn-row mt-5">',
            qq{<a class="btn btn--primary" href="@{[ attr($repo) ]}" rel="noopener">},
              '<span aria-hidden="true">&#9733;</span>',
              '<span>Star PwEevee on GitHub</span>',
            '</a>',
          '</div>',
          '<p class="small dim mt-4 mb-0">',
            'Entirely optional, and nothing on this site changes either way.',
          '</p>',
        '</div>');
}

# ---- an optional, unaffiliated tool recommendation ------------------------
#
# A referral link, presented as exactly that. It is deliberately quiet, it sits
# below everything about PwEevee itself, and the disclaimer is not fine print:
# Freebuff is not part of this project, does not sponsor it, and is not needed to
# download, sign or install anything here.
sub c_freebuff {
    my $url = 'https://freebuff.com/?ref=ref-4a833bdc-4d33-4512-b5a6-cdb94b9800a6';
    return '' unless is_safe_url($url);

    return join('',
        '<div class="panel pad accent-neutral">',
          '<p class="meta__k">Unaffiliated recommendation</p>',
          '<h3 class="mt-4">Freebuff</h3>',
          '<p class="muted mt-4 measure">',
            'A separate service, mentioned here because it is useful — not because PwEevee needs ',
            'it. The link below is a referral link.',
          '</p>',
          '<p class="small muted measure mt-4">',
            '<strong>Earn 15 Freebucks when a friend starts using Freebuff.</strong> A referral ',
            'counts once they sign up with a GitHub account at least 4 months old and actually use ',
            "it \x{2014} signing up alone isn't enough. Each full-access activation is worth 15 ",
            'Freebucks, and they are cashed out on Freebuff, into your wallet, while your account ',
            'is on full access.',
          '</p>',
          '<div class="btn-row mt-5">',
            qq{<a class="btn btn--outline btn--sm" href="@{[ attr($url) ]}" }
            . 'rel="noopener nofollow sponsored">Open Freebuff</a>',
          '</div>',
          '<p class="small dim mt-4 mb-0 measure">',
            'Not required, not affiliated with PwEevee, and not a sponsor of it. PwEevee does not ',
            'need Freebuff to build, publish or install anything.',
          '</p>',
        '</div>');
}

sub c_attribution {
    my $text = $SITE->{attribution} // '';
    my $spotipw = repo_url_of($PROJECT{spotipw} || {});
    my $eevee   = repo_url_of($PROJECT{eeveespotify} || {});
    return join('',
        '<div class="panel pad-lg accent-brand">',
          '<p class="eyebrow">Attribution</p>',
          '<h2 class="h-sub">Who made what</h2>',
          '<p class="muted mt-4 measure">', h($text), '</p>',
          '<div class="btn-row mt-5">',
            ($spotipw ? qq{<a class="btn btn--quiet btn--sm" href="@{[ attr($spotipw) ]}" rel="noopener">}
                        . github_icon() . '<span>spoti.pw repository</span></a>' : ''),
            ($eevee ? qq{<a class="btn btn--quiet btn--sm" href="@{[ attr($eevee) ]}" rel="noopener">}
                      . github_icon() . '<span>EeveeSpotify repository</span></a>' : ''),
            '<a class="btn btn--quiet btn--sm" href="/credits">Full credits</a>',
          '</div>',
        '</div>');
}

sub c_repos {
    my $html = '<div class="grid grid--3">';
    for my $p (@PROJECTS) {
        my $g = $GHP{ $p->{slug} };
        my $repo = $g && $g->{repo_url} ? $g->{repo_url} : repo_url_of($p);
        next unless $repo && is_safe_url($repo);
        my $accent = 'accent-' . ($p->{accent} // 'brand');
        my $nwo = $g ? $g->{repo} : ($p->{github}{owner} . '/' . $p->{github}{repo});
        $html .= qq{<a class="feature $accent" href="@{[ attr($repo) ]}" rel="noopener">}
               . '<span class="feature__icon" aria-hidden="true">' . github_icon() . '</span>'
               . '<h3>' . h($p->{name}) . '</h3>'
               . '<p class="mono small break">' . h($nwo) . '</p>'
               . '<p>' . h(($p->{role} // '') eq 'integration'
                           ? 'Maintained here — build system, releases and this site.'
                           : 'Separate upstream project with its own author and license.')
               . '</p></a>';
    }
    return $html . '</div>';
}

sub c_dependencies {
    my @d = @{ $MODEL->{dependencies} || [] };
    return '' unless @d;
    my $html = '<div class="grid grid--2">';
    for my $d (@d) {
        my $name = ($d->{url} && is_safe_url($d->{url}))
            ? qq{<a href="@{[ attr($d->{url}) ]}" rel="noopener">@{[ h($d->{name}) ]}</a>}
            : h($d->{name});
        $html .= '<div class="feature"><h3>' . $name . '</h3><p>' . h($d->{note}) . '</p></div>';
    }
    return $html . '</div>';
}

sub c_support {
    my @cards;
    for my $p (@PROJECTS) {
        next if ($p->{role} // '') eq 'integration';
        my $s = ref $p->{support} eq 'HASH' ? $p->{support} : {};
        my $accent = 'accent-' . ($p->{accent} // 'brand');
        my $body = ($s->{url} && is_safe_url($s->{url}))
            ? qq{<p class="mb-0"><a class="btn btn--outline btn--sm" href="@{[ attr($s->{url}) ]}" }
              . qq{rel="noopener">Support on @{[ h($s->{label} // 'their page') ]}</a></p>}
              . ($s->{note} ? '<p class="small dim mt-4 mb-0">' . h($s->{note}) . '</p>' : '')
            : '<p class="small muted mb-0">' . h($s->{note} // 'No official donation link was found.')
              . '</p>';
        # The names are labelled as upstream authors. Unlabelled, a bare list of
        # names under a project heading reads as "these people made everything
        # you see", which would sweep PwEevee's own integration in with them.
        push @cards, qq{<div class="panel pad $accent"><h3>@{[ h($p->{name}) ]}</h3>}
                   . '<p class="meta__k mt-4">Upstream authors</p>'
                   . '<p class="muted">' . h(join_authors($p)) . '</p>'
                   . $body . '</div>';
    }
    return '' unless @cards;
    return '<div class="split">' . join('', @cards) . '</div>';
}

sub join_authors {
    my ($p) = @_;
    my @names = map { $_->{name} } @{ $p->{authors} || [] };
    return @names ? join(' · ', @names) : 'Upstream author';
}

# ---- generic state block -------------------------------------------------

sub state_block {
    my ($kind, $icon, $title, $body, $actions) = @_;
    my $cls = $kind eq 'error' ? ' state--error' : $kind eq 'warn' ? ' state--warn' : '';
    my $html = qq{<div class="state$cls">}
             . qq{<div class="state__icon" aria-hidden="true">@{[ h($icon) ]}</div>}
             . '<h3>' . $title . '</h3>'
             . '<p>' . $body . '</p>';
    if ($actions && @$actions) {
        $html .= '<div class="state__actions">';
        for my $a (@$actions) {
            my ($label, $url, $style) = @$a;
            next unless $url;
            my $external = $url =~ m{^https://} ? ' rel="noopener"' : '';
            $html .= qq{<a class="btn btn--@{[ $style // 'outline' ]}" href="@{[ attr($url) ]}"$external>}
                   . h($label) . '</a>';
        }
        $html .= '</div>';
    }
    return $html . '</div>';
}
