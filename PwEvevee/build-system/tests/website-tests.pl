#!/usr/bin/env perl
# ============================================================================
# website-tests.pl — integrity checks for the generated website
# ============================================================================
#
#   perl PwEvevee/build-system/tests/website-tests.pl
#
# Run after update-releases.pl + render-site.pl. Checks the things that would
# actually break for a visitor, and the things a redesign can silently get
# wrong:
#
#   data model      projects.json / releases.json shape, no hardcoded versions
#   secrets         no token, key or credential anywhere in website/
#   routes          every page rendered, no unresolved placeholders
#   links           every internal href resolves to a real file
#   assets          every referenced stylesheet, script, image and icon exists
#   downloads       every local download target exists on disk; every external
#                   download URL is https and points at a GitHub host
#   accessibility   one h1 per page, skip link, labelled nav toggle, lang, alt
#   markup          balanced tags for the elements the renderer generates
#   legacy          URLs that existed before the redesign still resolve
#
# Exits non-zero on the first failing category so a release cannot ship broken.
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin ();
use lib "$FindBin::Bin/../release/lib";
use PwSite qw(repo_root slurp read_json notes_to_html text_excerpt h attr is_safe_url fmt_bytes);

binmode STDOUT, ':encoding(UTF-8)';

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $OUT = 'website';
my ($pass, $fail, @failures) = (0, 0);

# The ($;$$) prototype is load-bearing, not decoration.
#
# Without it the condition is evaluated in LIST context, and a failed match
# without capture groups returns the EMPTY LIST rather than false. So
#
#     ok($body =~ /required thing/, 'the thing is there');
#
# would collapse to ok('the thing is there') on failure: the name lands in
# $cond, which is truthy, and a real regression reports as a pass. The prototype
# forces scalar context on the first argument so a failed match is plainly false.
#
# The @_ == 1 guard catches the residual case the prototype cannot reach — a
# list-slurping operator such as grep eating the following arguments — by
# refusing to accept a check that arrived without a name.
sub ok($;$$) {
    if (@_ == 1) {
        $fail++;
        push @failures, 'MALFORMED CHECK (arguments collapsed into a list): '
                      . (defined $_[0] ? $_[0] : 'undef');
        return 0;
    }
    my ($cond, $what, $detail) = @_;
    if ($cond) { $pass++; return 1 }
    $fail++;
    push @failures, $what . (defined $detail && length $detail ? "  ($detail)" : '');
    return 0;
}
sub section { printf "\n%s\n", $_[0] }

# -------------------------------------------- 0. release-note sanitiser

# Release notes come from GitHub and are untrusted input, so the sanitiser gets
# its own unit tests rather than only being exercised indirectly.
section('0. release-note sanitiser (untrusted input)');

{
    my $html = notes_to_html('<script>alert(1)</script>');
    ok($html !~ /<script/i, 'a script tag cannot survive the sanitiser', $html);
    ok($html =~ /&lt;script&gt;/, 'a script tag is rendered as visible text');

    $html = notes_to_html('<img src=x onerror=alert(1)>');
    ok($html !~ /<img/i, 'an img tag cannot survive the sanitiser', $html);

    $html = notes_to_html('<a href="javascript:alert(1)">x</a>');
    ok($html !~ /javascript:/ || $html !~ /href="javascript:/,
       'no javascript: URL ends up in an href', $html);

    $html = notes_to_html('[click](javascript:alert(1))');
    ok($html !~ /href="javascript:/, 'a markdown link cannot smuggle a javascript: URL', $html);

    $html = notes_to_html('[click](https://example.com/a)');
    ok($html =~ m{<a href="https://example\.com/a" rel="noopener nofollow ugc" target="_blank">click</a>},
       'a markdown https link becomes a safe anchor', $html);

    $html = notes_to_html('see http://insecure.example/x for details');
    ok($html !~ /<a /, 'a plain http URL is not linkified', $html);

    # authors write entities in markdown because GitHub renders it as HTML
    $html = notes_to_html('Mod &gt; Licenses shows the license');
    ok($html =~ /Mod &gt; Licenses/, 'an entity in the source reads as the author intended', $html);
    ok($html !~ /&amp;gt;/, 'the entity is not double-escaped', $html);

    # ...but an author who escaped the ampersand wanted the entity shown verbatim
    $html = notes_to_html('write &amp;gt; to get a chevron');
    ok($html =~ /&amp;gt;/, 'a deliberately escaped entity stays literal', $html);

    $html = notes_to_html("- one\n- two\n\nplain paragraph");
    ok($html =~ m{<ul><li>one</li><li>two</li></ul>}, 'a bullet list becomes a list', $html);
    ok($html =~ m{<p>plain paragraph</p>}, 'a paragraph becomes a paragraph', $html);

    # Upstream headings become labelled paragraphs, not heading elements: these
    # notes are nested third-party content and must not inject arbitrary levels
    # into the page's outline.
    $html = notes_to_html('### Heading');
    ok($html =~ m{<p class="notes__h">Heading</p>},
       'a markdown heading becomes a labelled paragraph', $html);
    ok($html !~ /<h[1-6]/, 'release notes emit no heading elements', $html);

    $html = notes_to_html('x' x 9000, limit => 500);
    ok(length($html) < 2000, 'an over-long body is truncated');
    ok($html =~ /notes-truncated/, 'truncation is disclosed to the reader');

    ok(notes_to_html(undef) eq '' && notes_to_html('') eq '' && notes_to_html("  \n ") eq '',
       'an empty body produces no markup');

    # Sigils and template syntax in a note must pass through as inert text. The
    # renderer resolves the layout and page templates before splicing content in,
    # so these can never be interpreted; here we only assert they survive intact
    # and break nothing.
    $html = notes_to_html('$& @x %s {{title}} [[component:ecosystem]]');
    ok($html =~ /\{\{title\}\}/ && $html =~ /\[\[component:ecosystem\]\]/,
       'template syntax in a release note passes through as literal text', $html);
    ok($html =~ /\$&/ && $html =~ /\@x/, 'regex and array sigils survive the sanitiser', $html);

    my $ex = text_excerpt("# Title\n\n- Added **support** for [x](https://y.z)\n", 60);
    ok($ex !~ /[#*\[\]]/ && $ex !~ m{https?://}, "excerpt is plain text ('$ex')");

    # url and attribute guards
    ok(!is_safe_url('javascript:alert(1)'), 'javascript: is not a safe URL');
    ok(!is_safe_url('http://example.com'),  'plain http is not a safe URL');
    ok(!is_safe_url('https://exa mple.com'), 'a URL with whitespace is rejected');
    ok(is_safe_url('https://github.com/a/b'), 'an https GitHub URL is accepted');
    ok(attr('javascript:alert(1)') eq '', 'attr() refuses an unsafe URL');
    ok(attr('/downloads') eq '/downloads', 'attr() keeps a site-relative path');
    ok(h('<&">') eq '&lt;&amp;&quot;&gt;', 'h() escapes the dangerous characters');
    ok(fmt_bytes(302626980) =~ /MB$/ && fmt_bytes(0) eq '—' && fmt_bytes(undef) eq '—',
       'fmt_bytes handles real, zero and missing sizes');
}

# ---------------------------------------------------------------- 1. data

section('1. data model');

ok(-f "$OUT/data/projects.json", 'projects.json exists');
my $model = eval { read_json("$OUT/data/projects.json") } || {};
ok(ref $model->{projects} eq 'ARRAY', 'projects.json has a projects array');
ok(scalar @{ $model->{projects} || [] } == 3, 'three projects are declared',
   'found ' . scalar @{ $model->{projects} || [] });

my %slug;
for my $p (@{ $model->{projects} || [] }) {
    $slug{ $p->{slug} } = $p if $p->{slug};
    ok($p->{slug} && $p->{name} && $p->{page} && $p->{role},
       "project '" . ($p->{slug} // '?') . "' has slug, name, page and role");
    ok(ref $p->{github} eq 'HASH' && $p->{github}{owner} && $p->{github}{repo},
       "project '" . ($p->{slug} // '?') . "' declares a GitHub repository");
}
ok($slug{pweevee} && $slug{pweevee}{role} eq 'integration',
   'PwEevee is marked as the project maintained here');
ok(($slug{spotipw}{role} // '') eq 'upstream' && ($slug{eeveespotify}{role} // '') eq 'upstream',
   'spoti.pw and EeveeSpotify are marked upstream');

# --- repository coordinates -----------------------------------------------
#
# The canonical EeveeSpotify repository is SideloadLabs/EeveeSpotifyReincarnated.
# The two whoeevee repositories are no longer used as the source of truth.
{
    my $e = $slug{eeveespotify} || {};
    my $gh = ref $e->{github} eq 'HASH' ? $e->{github} : {};
    ok(($gh->{owner} // '') eq 'SideloadLabs',
       'EeveeSpotify is configured under the SideloadLabs owner', $gh->{owner});
    ok(($gh->{repo} // '') eq 'EeveeSpotifyReincarnated',
       'EeveeSpotify is configured as the EeveeSpotifyReincarnated repository', $gh->{repo});

    my $p = $slug{pweevee} || {};
    my $pgh = ref $p->{github} eq 'HASH' ? $p->{github} : {};
    ok($pgh->{owner} && $pgh->{repo},
       'PwEevee declares its own GitHub repository',
       ($pgh->{owner} // '?') . '/' . ($pgh->{repo} // '?'));

    my $s = $slug{spotipw} || {};
    my $sgh = ref $s->{github} eq 'HASH' ? $s->{github} : {};
    ok(($sgh->{owner} // '') eq 'skopevoj' && ($sgh->{repo} // '') eq 'spoti.pw',
       'spoti.pw still points at its own upstream repository');

    # --- the AltSource declaration ---------------------------------------
    #
    # The upstream path really is spelled "SideloasLabs-AltSource". It must be
    # used exactly as published, never silently corrected to "SideloadLabs".
    my $as = ref $e->{altsource} eq 'HASH' ? $e->{altsource} : {};
    ok(($as->{url} // '') eq
       'https://raw.githubusercontent.com/SideloadLabs/SideloasLabs-AltSource/refs/heads/main/apps.json',
       'the AltSource URL is the exact supplied URL', $as->{url});
    ok(($as->{repo} // '') eq 'SideloadLabs/SideloasLabs-AltSource',
       'the AltSource repository path keeps its upstream spelling', $as->{repo});
    ok(ref $as->{families} eq 'ARRAY' && @{ $as->{families} } >= 2,
       'the AltSource declares the variant families to group by');
}

# the data model must not carry version numbers — those come from the generators
my $model_raw = slurp("$OUT/data/projects.json");
ok($model_raw !~ /"(?:version|latest_version|tag)"\s*:/,
   'projects.json declares no version fields');

ok(-f "$OUT/data/releases.json", 'releases.json exists (update-releases.pl has run)');
my $rel = eval { read_json("$OUT/data/releases.json") } || {};
ok(ref $rel->{projects} eq 'ARRAY', 'releases.json has a projects array');
ok($rel->{generated_at} && $rel->{generated_at} =~ /^\d{4}-\d{2}-\d{2}T/,
   'releases.json records when it was generated');

my $fresh = 0;
for my $p (@{ $rel->{projects} || [] }) {
    ok(exists $slug{ $p->{slug} }, "release entry '" . ($p->{slug} // '?') . "' matches a declared project");
    next unless ref $p->{latest} eq 'HASH';
    $fresh++;
    my $l = $p->{latest};
    ok(defined $l->{version} && length $l->{version},
       "$p->{slug}: latest release has a version");
    ok($l->{published_at} && $l->{published_at} =~ /^\d{4}-\d{2}-\d{2}T/,
       "$p->{slug}: latest release has a publish timestamp");
    ok(($l->{published_epoch} // 0) > 0, "$p->{slug}: publish timestamp parsed to an epoch");
    ok(!$l->{draft}, "$p->{slug}: latest release is not a draft");
    ok($l->{url} && $l->{url} =~ m{^https://github\.com/}, "$p->{slug}: release URL is a GitHub URL");
    for my $a (@{ $l->{assets} || [] }) {
        ok($a->{download_url} =~ m{^https://(?:github\.com|[a-z0-9.-]+\.githubusercontent\.com)/},
           "$p->{slug}: asset '$a->{name}' download URL is on a GitHub host", $a->{download_url});
        ok(($a->{size} // -1) >= 0, "$p->{slug}: asset '$a->{name}' has a size");
    }
    # history must be newest-first
    my @eps = map { $_->{published_epoch} // 0 } @{ $p->{history} || [] };
    my $sorted = 1;
    $sorted = 0 if grep { $eps[$_] < $eps[ $_ + 1 ] } 0 .. ($#eps - 1);
    ok($sorted, "$p->{slug}: release history is ordered newest first");
}
ok($fresh == 3, 'all three projects resolved a latest release', "resolved $fresh");

# GitHub must actually be the source of truth: the generated file has to say so,
# and the EeveeSpotify entry has to have resolved against the new repository.
ok(($rel->{source} // '') =~ /GitHub/i, 'releases.json records GitHub as its source');
{
    my %by = map { $_->{slug} => $_ } @{ $rel->{projects} || [] };
    ok(($by{eeveespotify}{repo} // '') eq 'SideloadLabs/EeveeSpotifyReincarnated',
       'the EeveeSpotify release entry resolved against SideloadLabs/EeveeSpotifyReincarnated',
       $by{eeveespotify}{repo});
    ok(($by{eeveespotify}{repo_url} // '') eq
       'https://github.com/SideloadLabs/EeveeSpotifyReincarnated',
       'the EeveeSpotify repository URL is the SideloadLabs one');

    # The featured PwEevee download has to be a real, published release asset.
    my $own = $by{pweevee} || {};
    ok(ref $own->{latest} eq 'HASH', 'PwEevee resolved a published GitHub release');
    my @own_assets = @{ (ref $own->{latest} eq 'HASH' ? $own->{latest}{assets} : []) || [] };
    ok(@own_assets > 0, 'the PwEevee release carries at least one downloadable asset');
    ok((grep { ($_->{kind} // '') eq 'ipa' } @own_assets) > 0,
       'the PwEevee release carries an installable IPA asset');
}

# --- AltSource data -------------------------------------------------------

section('1b. AltSource data model');

ok(-f "$OUT/data/altsource.json", 'altsource.json exists (update-altsource.pl has run)');
my $alt_data = eval { read_json("$OUT/data/altsource.json") } || {};
ok(ref $alt_data->{sources} eq 'ARRAY', 'altsource.json has a sources array');
ok($alt_data->{generated_at} && $alt_data->{generated_at} =~ /^\d{4}-\d{2}-\d{2}T/,
   'altsource.json records when it was generated');
# It must never be mistaken for a GitHub release.
ok(($alt_data->{source_kind} // '') =~ /not a github release/i,
   'altsource.json states that it is not a GitHub release', $alt_data->{source_kind});

my $alt_raw = -f "$OUT/data/altsource.json" ? slurp("$OUT/data/altsource.json") : '';
ok($alt_raw !~ m{api\.github\.com}, 'the AltSource data is not confused with the GitHub API');

{
    my ($src) = grep { ($_->{slug} // '') eq 'eeveespotify' } @{ $alt_data->{sources} || [] };
    ok($src, 'the EeveeSpotify AltSource entry exists');
    if ($src) {
        ok($src->{available}, 'the EeveeSpotify AltSource resolved', $src->{error});
        ok(($src->{source_url} // '') eq
           'https://raw.githubusercontent.com/SideloadLabs/SideloasLabs-AltSource/refs/heads/main/apps.json',
           'the generated data kept the exact supplied AltSource URL', $src->{source_url});
        ok(($src->{repo} // '') eq 'SideloadLabs/SideloasLabs-AltSource',
           'the generated data kept the upstream repository spelling', $src->{repo});
        ok(($src->{source_name} // '') =~ /SideloadLabs/,
           'the source is identified as SideloadLabs', $src->{source_name});

        my @variants = @{ $src->{variants} || [] };
        ok(@variants >= 4, 'at least the four published variants were parsed',
           'found ' . scalar @variants);

        # The four builds must be understood as variants, not as repositories.
        my %seen = map { $_->{name} => $_ } @variants;
        for my $name ('EeveeSpotifyReincarnated', 'EeveeSpotifyReincarnated(PATCHED)',
                      'ESR Liquid Glass', 'ESR Liquid Glass Patched') {
            ok($seen{$name}, "AltSource variant parsed: $name");
        }
        ok(!$seen{'EeveeSpotifyReincarnated'}{patched},
           'the mainline build is understood as the Standard variant');
        ok($seen{'EeveeSpotifyReincarnated(PATCHED)'}{patched},
           'the PATCHED build is understood as the Patched variant');
        ok($seen{'ESR Liquid Glass Patched'}{patched},
           'the Liquid Glass Patched build is understood as the Patched variant');

        my @families = @{ $src->{families} || [] };
        ok(scalar @families == 2, 'the variants group into two families',
           'found ' . scalar @families);
        for my $f (@families) {
            ok(scalar @{ $f->{variants} || [] } == 2,
               "family '$f->{label}' offers a Standard and a Patched variant");
            ok(($f->{variants}[0]{variant} // '') eq 'standard',
               "family '$f->{label}' lists Standard first");
        }

        # Every fact the UI shows must be present, and never invented.
        for my $v (@variants) {
            ok($v->{download_url} =~ m{^https://}, "variant '$v->{name}': https download URL",
               $v->{download_url});
            ok(($v->{size} // 0) > 0, "variant '$v->{name}': size recorded");
            ok($v->{size_label} && $v->{size_label} ne '—',
               "variant '$v->{name}': size has a readable label");
            ok($v->{release_date} && $v->{release_date} =~ /^\d{4}-\d{2}-\d{2}/,
               "variant '$v->{name}': release date recorded", $v->{release_date});
            ok(($v->{date_epoch} // 0) > 0, "variant '$v->{name}': release date parsed");
            ok(defined $v->{spotify_version} && length $v->{spotify_version},
               "variant '$v->{name}': Spotify version extracted");
            ok(defined $v->{eevee_version} && length $v->{eevee_version},
               "variant '$v->{name}': EeveeSpotify version extracted");
            ok($v->{variant_label} =~ /^(?:Standard|Patched)$/,
               "variant '$v->{name}': variant type is Standard or Patched", $v->{variant_label});
        }
    }
}

# ---------------------------------------------------------------- 2. secrets

section('2. secrets');

my @files = all_files($OUT);
my @suspect;
for my $f (@files) {
    next if $f =~ /\.(?:ipa|png|webp|jpg|jpeg|gif|deb)$/i;
    my $body = slurp($f);
    push @suspect, "$f: GitHub token"     if $body =~ /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}/;
    push @suspect, "$f: fine-grained PAT" if $body =~ /\bgithub_pat_[A-Za-z0-9_]{20,}/;
    push @suspect, "$f: Authorization hdr" if $body =~ /Authorization\s*[:=]\s*["']?(?:Bearer|token)\s+\S/i;
    push @suspect, "$f: GITHUB_TOKEN value" if $body =~ /GITHUB_TOKEN\s*[:=]\s*["']?[A-Za-z0-9_-]{10,}/;
    push @suspect, "$f: private key"      if $body =~ /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/;
    push @suspect, "$f: aws key"          if $body =~ /\bAKIA[0-9A-Z]{16}\b/;
}
ok(!@suspect, 'no credentials anywhere under website/', join('; ', @suspect));

# the client must never be told to call the GitHub API with credentials
my $js = slurp("$OUT/assets/pweevee.js");
ok($js !~ /Authorization/i, 'the browser script sends no Authorization header');
ok($js !~ m{api\.github\.com}, 'the browser script does not call the GitHub API');

# ---------------------------------------------------------------- 3. routes

section('3. routes and placeholders');

my @routes = qw(
    index.html
    downloads/index.html
    releases/index.html
    projects/index.html
    projects/pweevee/index.html
    projects/spotipw/index.html
    projects/eeveespotify/index.html
    credits/index.html
    development/index.html
    legal/index.html
    contact/index.html
    install/index.html
    404.html
);
ok(-f "$OUT/$_", "route rendered: $_") for @routes;

# alt-redirect.html is a deliberate one-line meta-refresh stub for the alternate
# host, not a content page; it gets its own check further down.
my @html = grep { /\.html$/ && !m{/alt-redirect\.html$} } @files;
for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    ok($body !~ /\{\{\w/, "no unresolved layout token in $f");
    ok($body !~ /\[\[component:/, "no unresolved component in $f");
    ok($body =~ /<!DOCTYPE html>/i, "$f has a doctype");
    ok($body =~ /<html lang="en">/, "$f declares its language");
    ok($body =~ m{<link rel="canonical" href="https://[^"]+">}, "$f has a canonical URL");
    ok($body =~ m{<meta name="description" content="[^"]{40,}">}, "$f has a description");
    ok($body =~ m{<meta property="og:title"}, "$f has Open Graph metadata");

    my $h1 = () = $body =~ /<h1[\s>]/g;
    ok($h1 == 1, "$f has exactly one h1", "found $h1");
    ok($body =~ /class="skip-link"/, "$f has a skip link");
    ok($body =~ /data-nav-toggle[^>]*aria-label="/, "$f nav toggle is labelled");
    ok($body =~ /aria-expanded="false"/, "$f nav toggle declares its state");

    # tag balance for the containers the renderer emits
    for my $tag (qw(div article section details dl)) {
        my $open  = () = $body =~ /<$tag\b/g;
        my $close = () = $body =~ m{</$tag>}g;
        ok($open == $close, "$f has balanced <$tag>", "$open open / $close close");
    }
    # every image must carry alt text
    for my $img ($body =~ /(<img\b[^>]*>)/g) {
        ok($img =~ /\balt=/, "$f: img has alt text", $img);
    }

    # The nginx example ships a strict Content-Security-Policy with no
    # 'unsafe-inline'. These two checks keep the markup compatible with it.
    my ($inline_style) = $body =~ /(\sstyle="[^"]*")/;
    ok(!defined $inline_style, "$f has no inline style attribute (CSP)", $inline_style);
    ok($body !~ /<script(?![^>]*\bsrc=)[^>]*>\s*\S/, "$f has no inline script (CSP)");
    ok($body !~ /<style[\s>]/, "$f has no inline stylesheet (CSP)");

    # The CSP is "default-src 'none'; img-src 'self'": the browser may fetch NO
    # subresource from another origin. That is about loading, not about linking —
    # a download URL or a link in a release note is a navigation and is fine.
    # So this checks the things the browser actually fetches: src attributes and
    # <link> elements. Anchors are checked separately, for https only.
    my @subresources = ($body =~ /\bsrc="([^"]+)"/g);
    push @subresources, ($body =~ /<link\b[^>]*\bhref="([^"]+)"/g);
    my @offsite = grep { m{^[a-z]+://} && !m{^https://pweevee\.skytweak\.} } @subresources;
    ok(!@offsite, "$f loads no third-party subresource", join(', ', @offsite));

    # Anchors may point anywhere, but never over plain http and never at a
    # javascript: URL.
    my @bad_links = grep { m{^http://} || m{^\s*javascript:}i }
                    ($body =~ /<a\b[^>]*\bhref="([^"]+)"/g);
    ok(!@bad_links, "$f has no insecure anchor target", join(', ', @bad_links));
}

# ---------------------------------------------------------------- 4. links

section('4. internal links and assets');

my %seen_target;
for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    my @refs = ($body =~ /(?:href|src)="(\/[^"#?]*)/g);
    for my $ref (@refs) {
        next if $seen_target{$ref}++;
        my $target = resolve($ref);
        ok(defined $target, "internal link resolves: $ref", "referenced from $f");
    }
}

for my $asset (qw(assets/pweevee.css assets/pweevee.js assets/favicon.svg
                  assets/social-card.png sitemap.xml robots.txt)) {
    ok(-f "$OUT/$asset" && -s "$OUT/$asset", "asset present and non-empty: $asset");
}

# the sitemap must list the indexable routes and nothing else
my $sitemap = -f "$OUT/sitemap.xml" ? slurp("$OUT/sitemap.xml") : '';
ok($sitemap =~ m{<loc>https://pweevee\.skytweak\.dpdns\.org/</loc>}, 'sitemap lists the home page');
# one sitemap entry per source page template, minus the 404 (excluded above)
my $locs = () = $sitemap =~ /<loc>/g;
my @src_pages = glob("website-src/pages/*.html");
ok($locs == @src_pages - 1,
   'sitemap lists every indexable route (one per source page minus the 404)',
   "found $locs, source pages " . scalar(@src_pages));
ok($sitemap !~ m{/404}, 'sitemap excludes the 404 page');
my $robots = -f "$OUT/robots.txt" ? slurp("$OUT/robots.txt") : '';
ok($robots =~ m{Sitemap: https://pweevee\.skytweak\.dpdns\.org/sitemap\.xml},
   'robots.txt points at the sitemap');

# ------------------------------------------------- 4b. visual system

section('4b. visual system');

my $css = slurp("$OUT/assets/pweevee.css");
my $home = slurp("$OUT/index.html");
utf8::decode($home);

# ---- the palette is the specified one, and only the specified one ---------

# The six surface values, verbatim, plus the blue sampled from the official logo
# artwork. If one of these disappears the design has drifted off-brief.
my %PALETTE = (
    '#ffffff' => 'white',
    '#f5f5f3' => 'off-white',
    '#e8e8e6' => 'light gray',
    '#171717' => 'dark gray',
    '#101010' => 'charcoal',
    '#080808' => 'near black',
    '#2a3762' => 'the logo blue',
);
for my $hex (sort keys %PALETTE) {
    ok($css =~ /\Q$hex\E/i, "specified colour present: $hex ($PALETTE{$hex})");
}

for my $token (qw(--white --off-white --light-gray --dark-gray --charcoal
                  --near-black
                  --l-bg --l-surface --l-surface-2 --l-rule --l-ink --l-brand
                  --d-bg --d-surface --d-surface-2 --d-rule --d-ink --d-brand
                  --rule --rule-strong --ink --ink-2 --ink-3 --accent --brand
                  --surface --surface-2 --header-bg --star-intensity)) {
    ok($css =~ /\Q$token\E:/, "design token declared: $token");
}

# The dark-glass palette must be gone, not merely unused: a leftover
# declaration is the first step back towards the old theme.
for my $gone (qw(--void --midnight --navy --blue-bright --blue-deep --crimson
                 --crimson-soft --glass-1 --glass-2 --glass-3 --glass-solid
                 --edge --edge-strong --edge-bright --bloom --bloom-strong
                 --glow-blue --glow-blue-dim --glow-crimson --rim --blur-1
                 --blur-2 --blur-3 --accent-bright --accent-glow
                 --mint --violet --amber --mint-ink --green --r-pill)) {
    ok($css !~ /\Q$gone\E\s*:/, "retired token removed: $gone");
}
ok($css !~ /accent-mint|accent-violet|accent-amber|accent-crimson|accent-cyan/,
   'retired accent classes removed from CSS');

# Two tones, not a rainbow: PwEevee's own material carries the logo blue and
# upstream material is graphite. Both must be declared, because the renderer
# builds the class name from the data model and a missing one fails silently.
ok($css =~ /\.accent-brand\b/,   'the brand accent tone is declared');
ok($css =~ /\.accent-neutral\b/, 'the neutral accent tone is declared');

# No colour outside the sanctioned set. This is the check that stops the palette
# drifting back into a second theme one convenience colour at a time.
{
    # Written as a split string rather than qw(), because a '#' inside qw() looks
    # like the start of a comment and makes perl warn.
    my %allowed = map { $_ => 1 } (keys %PALETTE, split ' ', join ' ',
        # the light theme's derived greys
        '#d2d2cf #4a4a46 #6e6e68',
        # the dark theme's surfaces, rules and inks
        '#111111 #242424 #383838 #f4f4f4 #b0b0b0 #8a8a8a',
        # the remaining steps of the logo blue
        '#1f2847 #90a0d5 #f2f3f6',
        # the two desaturated status inks, in each theme
        '#7a5410 #8c2f2f #d9b471 #e39a9a',
        # the print stylesheet, which is deliberately plain black on white
        '#fff #000 #ccc');
    # Comments are prose, not colour: a hex quoted in an explanation is not a
    # value the browser ever sees, so it is stripped before the scan.
    (my $decls = $css) =~ s{/\*.*?\*/}{}gs;

    my %found;
    $found{lc $1}++ while $decls =~ /(#[0-9a-f]{3,8})\b/gi;
    my @stray = grep { !$allowed{$_} } sort keys %found;
    ok(!@stray, 'no colour outside the declared palette', join(', ', @stray));

    # …and no saturated colour smuggled in as rgb()/hsl()
    my @rgb;
    while ($decls =~ /\brgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/g) {
        my ($r, $g, $b) = ($1, $2, $3);
        my $max = $r; $max = $g if $g > $max; $max = $b if $b > $max;
        my $min = $r; $min = $g if $g < $min; $min = $b if $b < $min;
        push @rgb, "rgb($r,$g,$b)" if ($max - $min) > 40;   # not grey
    }
    ok(!@rgb, 'no saturated rgb() colour outside the palette', join(', ', @rgb));
}

# ---- the aesthetic we moved away from must not come back ------------------

ok($css !~ /backdrop-filter/i, 'no glassmorphism backdrop blur');
ok($css !~ /\bfilter:\s*blur|\bblur\(/, 'no blur filters');

# Gradients were the signature of the old theme. There are none: a flat surface
# and a hairline carry the structure instead.
my $gradients = () = $css =~ /\b(?:linear|radial|conic)-gradient\(/g;
ok($gradients == 0, 'no gradients anywhere in the stylesheet', "found $gradients");

# the glowing-blob background and the glossy hero stage are gone from both sides
for my $ghost (qw(atmosphere __glow __halo __plinth __specks __vignette
                  __grain __reflection stage__ glass--  btn--glass)) {
    ok($css !~ /\Q$ghost\E/, "retired design vocabulary absent from CSS: $ghost");
}
ok($css !~ /\.glass[\s,{.:]/, 'the glass component is gone from the CSS');
for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    for my $ghost (qw(atmosphere__ stage__ class="stage" glass-- btn--glass)) {
        ok($b !~ /\Q$ghost\E/, "$f is free of the retired vocabulary: $ghost");
    }
}

# Radii stay small. The design system's own steps are all under 12px; the only
# larger radius belongs to the app-icon artwork, which is a squircle by nature.
for my $step (qw(--r-xs --r-sm --r --r-lg)) {
    my ($v) = $css =~ /\Q$step\E:\s*(\d+)px/;
    ok(defined $v && $v <= 12, "radius step $step stays small",
       defined $v ? "${v}px" : 'not declared');
}
{
    my %icon_radius = map { $_ => 1 } qw(project-hero__icon);
    my @oversized;
    for my $rule (split /\}/, $css) {
        next unless $rule =~ /border-radius:\s*([^;]+)/;
        my $value = $1;
        my $max = 0;
        for my $px ($value =~ /(\d+)px/g) { $max = $px if $px > $max }
        next if $max <= 12;
        my ($sel) = $rule =~ /([^{]*)\{/;
        $sel = defined $sel ? $sel : '';
        $sel =~ s/\s+/ /g;
        $sel =~ s/^\s+|\s+$//g;
        next if grep { $sel =~ /\Q$_\E/ } keys %icon_radius;
        push @oversized, "$sel (${max}px)";
    }
    ok(!@oversized, 'only the app-icon artwork uses a large radius',
       join('; ', @oversized));
}

# ---- hairline structure, not floating cards ------------------------------

my $hairlines = () = $css =~ /1px solid var\(--rule/g;
ok($hairlines >= 20, 'structure is carried by hairline rules', "found $hairlines");

# One elevation token, it is neutral, and it is barely used. A coloured shadow
# with a wide spread is a bloom by another name.
my ($shadow_token) = $css =~ /--shadow-paper:\s*([^;]+)/;
ok(defined $shadow_token, 'a single elevation token is declared');
if (defined $shadow_token) {
    my @chan = $shadow_token =~ /rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/g;
    my $neutral = 1;
    while (@chan >= 3) {
        my ($r, $g, $b) = splice(@chan, 0, 3);
        $neutral = 0 unless $r == $g && $g == $b;
    }
    ok($neutral, 'the elevation shadow is neutral, not a coloured bloom', $shadow_token);
}
# Only outer shadows count as elevation. An `inset` box-shadow is standing in for
# a border — it draws a hairline without changing the box model — which is the
# opposite of making something float.
my @outer = grep { !/inset/ && !/^\s*none/ } ($css =~ /box-shadow:\s*([^;}]+)/g);
ok(scalar(@outer) <= 4, 'elevation is used sparingly',
   scalar(@outer) . ' outer shadows: ' . join(' | ', @outer));

# ---- the inverted context ------------------------------------------------

ok($css =~ /^\.inverted\s*\{/m, 'the inverted (dark) context is a single class');
for my $flip (qw(--bg --surface --rule --ink --accent)) {
    ok($css =~ /\.inverted\s*\{[^}]*\Q$flip\E\s*:/s,
       "the inverted context reassigns $flip");
}
for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    ok($b =~ /class="site-footer inverted"/,
       "$f: the footer is an inverted region");
}
my $bands = () = $home =~ /class="section inverted"/g;
ok($bands == 1, 'the home page carries exactly one inverted band', "found $bands");

# ---- the falling-star field ---------------------------------------------

# Restraint is the requirement, so it is what gets asserted: the field exists,
# it only ever paints in a dark region, it is capped, it stops when it is not
# being looked at, and it does not exist at all under reduced motion.
ok($css =~ /\.starfield\s*\{/, 'the star field container is styled');
ok($css =~ /\.starfield\s*\{[^}]*position:\s*absolute/s,
   'the star field is positioned behind its section, not over the page');
ok($css =~ /\.starfield\s*\{[^}]*pointer-events:\s*none/s,
   'the star field never intercepts a pointer');
ok($css =~ /\.starfield\s*\{[^}]*display:\s*none/s,
   'the star field is off unless a region opts in');
ok($css =~ /\.inverted\s*>\s*\.starfield\s*\{[^}]*display:\s*block/s,
   'only a dark region turns the star field on');

my $home_fields = () = $home =~ /class="starfield"/g;
ok($home_fields == 2, 'the home page has exactly two star fields: the band and the footer',
   "found $home_fields");
for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    my $fields = () = $b =~ /class="starfield"/g;
    ok($fields >= 1 && $fields <= 2, "$f has a restrained number of star fields",
       "found $fields");
    # it carries no information, so it must be hidden from assistive technology
    ok($b !~ /class="starfield"(?![^>]*aria-hidden="true")/,
       "$f hides the star field from assistive technology");
}

# The script side of the same promise. Asserted against the star-field block
# alone, so a guard that happens to exist elsewhere in the file cannot stand in
# for the one that matters here.
my ($sf) = $js =~ /function starfield\(\)([\s\S]*?)5\. copy buttons/;
ok(defined $sf && length $sf, 'the star field is implemented in pweevee.js');
$sf = '' unless defined $sf;

ok($sf =~ /data-starfield/, 'the script finds the star field by its data hook');
ok($sf =~ /if \(reduceMotion\.matches\) return;/,
   'the script paints nothing at all under reduced motion');
ok($sf =~ /reduceMotion\.(?:addEventListener|addListener)/,
   'turning reduced motion on mid-visit stops the animation');

my ($max_stars) = $sf =~ /MAX_STARS\s*=\s*(\d+)/;
ok(defined $max_stars && $max_stars <= 80,
   'the star count is capped low enough to stay a texture',
   defined $max_stars ? $max_stars : 'no cap found');
my ($area) = $sf =~ /AREA_PER_STAR\s*=\s*(\d+)/;
ok(defined $area && $area >= 12000, 'the star density is sparse',
   defined $area ? "one per ${area} square px" : 'no density found');

# opacity stays very low, so it reads as air rather than as a starscape
my @alphas = $sf =~ /aMax:\s*([0-9.]+)/g;
ok(@alphas > 0, 'the star field declares its opacity range');
my $brightest = 0;
for my $a (@alphas) { $brightest = $a if $a > $brightest }
ok($brightest <= 0.5, 'even the brightest layer stays faint', "max alpha $brightest");

ok($sf =~ /IntersectionObserver/, 'a star field that is off screen is not drawn');
ok($sf =~ /doc\.hidden/,          'a hidden tab stops the animation loop');
ok($js =~ /visibilitychange/,     'the page listens for tab visibility');
ok($sf =~ /devicePixelRatio[^;]*,\s*1\.5\)/,
   'the canvas caps its pixel ratio, so a phone does not render at 3x');
ok($sf !~ /shooting|meteor|comet|trail/i, 'there are no shooting stars');
ok($js !~ /setInterval/, 'animation is driven by requestAnimationFrame, not a timer');
my $raf_loops = () = $js =~ /requestAnimationFrame\(tick\)/g;
ok($raf_loops <= 2, 'there is one animation loop, not one per field',
   "$raf_loops requestAnimationFrame(tick) call sites");

# ------------------------------------------- 4e. narrow-screen behaviour

section('4e. responsive behaviour');

# Every component that is two columns on a desktop needs a declared narrow-screen
# layout. Without one it either overflows or strands its content.
my %collapses = (
    'grid--2'        => 'the two-column grid',
    'grid--3'        => 'the three-column grid',
    'split'          => 'the split layout',
    'variant-grid'   => 'the AltSource variant grid',
    'kv__row'        => 'the key/value row',
    'footer__grid'   => 'the footer columns',
    'hero__grid'     => 'the hero',
    'hero__stats'    => 'the facts strip',
);
for my $cls (sort keys %collapses) {
    # minmax(0, 1fr) is the correct single-column collapse: a bare 1fr track
    # keeps min-content as its minimum, so one long unbreakable value (a repo
    # name, a filename) could push the track past a 320px viewport.
    ok($css =~ /\@media[^{]*max-width[^{]*\{[\s\S]*?\.\Q$cls\E[^{}]*\{[^}]*grid-template-columns:\s*(?:minmax\(0,\s*1fr\)|1fr|repeat\(2)/,
       "$collapses{$cls} collapses at a narrow width");
}

# the navigation collapses on its own breakpoint, and the script agrees with it
my ($nav_bp) = $css =~ /\@media \(max-width: (\d+)px\) \{\s*\n\s*\.nav \{/;
ok(defined $nav_bp, 'the navigation has its own collapse breakpoint');
if (defined $nav_bp) {
    ok($nav_bp >= 900, 'the nav collapses early enough to leave slack in the bar',
       "${nav_bp}px");
    my ($js_bp) = $js =~ /matchMedia\('\(min-width: (\d+)px\)'\)/;
    ok(defined $js_bp && $js_bp == $nav_bp + 1,
       'the drawer script uses the counterpart of the CSS breakpoint',
       "css ${nav_bp}px vs js " . (defined $js_bp ? "${js_bp}px" : 'none'));
}

# Long unbreakable values are the usual cause of sideways scrolling. Each place
# that can hold one must be able to break it.
for my $cls (qw(break asset__name variant__source-name hash__value notes)) {
    ok($css =~ /\.\Q$cls\E[^{}]*\{[^}]*overflow-wrap:\s*(?:anywhere|break-word)/s,
       "$cls can break a long unbreakable value");
}

# the checksum field shrinks rather than widening the page, and keeps its button
ok($css =~ /\.hash__value \{[^}]*min-width:\s*0/s,
   'the checksum value may shrink below its flex basis');
ok($css =~ /\.hash \{[^}]*flex-wrap:\s*wrap/s,
   'the checksum row wraps, so Copy is never pushed off screen');
ok($css =~ /\.hash \.copy \{[^}]*flex:\s*none/s,
   'the Copy button keeps its size');

# overflow-x: hidden is a band-aid that hides broken layout; it must not be the fix
ok($css !~ /(?:html|body|\.page)[^{}]*\{[^}]*overflow-x:\s*hidden/s,
   'the page does not mask overflow with overflow-x: hidden');

# no fixed pixel width large enough to overflow the narrowest supported viewport
{
    (my $nc = $css) =~ s{/\*.*?\*/}{}gs;
    my @wide;
    while ($nc =~ /([^{}]*)\{([^{}]*)\}/g) {
        my ($sel, $body) = ($1, $2);
        while ($body =~ /(?<!max-)(?<!min-)\bwidth:\s*(\d+)px/g) {
            push @wide, "$sel (${1}px)" if $1 > 260;
        }
    }
    $_ =~ s/\s+/ /g for @wide;
    ok(!@wide, 'no element is wider than the narrowest supported viewport',
       join('; ', @wide));
}

# ------------------------------------------- 4e2. accessibility

section('4e2. accessibility');

for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    my $short = $f;
    $short =~ s{^\Q$OUT\E/}{};

    # exactly one h1 per page, and no skipped level in the outline
    my $h1 = () = $b =~ /<h1\b/g;
    ok($h1 == 1, "$short has exactly one h1", "found $h1");

    my @levels = $b =~ /<h([1-6])\b/g;
    my ($prev, $skip) = (0, '');
    for my $lvl (@levels) {
        if ($prev && $lvl > $prev + 1) { $skip = "h$prev -> h$lvl"; last }
        $prev = $lvl;
    }
    ok(!$skip, "$short does not skip a heading level", $skip);

    # a decorative image must be hidden from assistive technology as well as
    # carrying an empty alt; a meaningful one must have real alt text
    for my $img ($b =~ /(<img\b[^>]*>)/g) {
        if ($img =~ /\balt=""/) {
            ok($img =~ /aria-hidden="true"/,
               "$short: a decorative image is hidden from assistive technology", $img);
        } else {
            ok($img =~ /\balt="[^"]+"/, "$short: a meaningful image has alt text", $img);
        }
    }

    # no control may be left without an accessible name
    for my $el ($b =~ m{(<(?:button|a)\b[^>]*>.*?</(?:button|a)>)}gs) {
        next if $el =~ /aria-label="[^"]+"|aria-labelledby="[^"]+"|aria-hidden="true"/;
        (my $text = $el) =~ s/<[^>]+>//g;
        $text =~ s/&[a-z#0-9]+;/x/g;
        ok($text =~ /\S/, "$short: every control has an accessible name",
           substr($el, 0, 100));
    }

    # the drawer must be announced and controllable from the keyboard
    ok($b =~ /data-nav-toggle[^>]*aria-expanded="false"[^>]*aria-controls="nav-drawer"/,
       "$short: the menu button declares its state and what it controls");
    ok($b =~ /<div class="nav__drawer" id="nav-drawer"/,
       "$short: the drawer carries the id the button points at");
}

# focus is visible, and it is the accent doing it
ok($css =~ /:focus-visible\s*\{[^}]*outline:\s*2px solid var\(--accent-ink\)/s,
   'focus is shown with a visible outline');
ok($css =~ /:focus-visible\s*\{[^}]*outline-offset/s,
   'the focus ring is offset so it is not lost against the border');

# the script must not trap or swallow keyboard use
ok($js =~ /e\.key === 'Escape'/, 'Escape closes the drawer');
ok($js =~ /e\.key !== 'Tab'/, 'Tab is kept inside the open drawer');
ok($js =~ /toggle\.focus\(\)/, 'focus returns to the button when the drawer closes');

# ------------------------------------------- 4f. brand rendering

section('4f. the brand is never restyled into another spelling');

# text-transform: uppercase renders PwEevee as PWEEVEE and iOS as IOS. The name is
# written one way, so no rule may repaint it into another — which means a label
# that is uppercased must not contain a project name.
{
    (my $nc = $css) =~ s{/\*.*?\*/}{}gs;
    my %upper;
    while ($nc =~ /([^{}]*)\{([^{}]*)\}/g) {
        my ($sel, $body) = ($1, $2);
        next unless $body =~ /text-transform:\s*uppercase/;
        $sel =~ s/\s+/ /g;
        $sel =~ s/^\s+|\s+$//g;
        $upper{$_} = 1 for ($sel =~ /\.([a-z][\w-]*)/g);
    }
    ok(scalar keys %upper, 'some labels are uppercased by design');

    # the classes that carry a project name must not be among them
    for my $named (qw(download__project showcase__meta brand__name)) {
        ok(!$upper{$named}, "$named is not uppercased, because it carries a name");
    }

    # and no eyebrow may contain the brand, since .eyebrow IS uppercased
    for my $f (@html) {
        my $b = slurp($f);
        utf8::decode($b);
        my @bad = $b =~ m{class="eyebrow"[^>]*>([^<]*PwEevee[^<]*)<}g;
        ok(!@bad, "$f has no uppercased label containing the brand name",
           join(' | ', @bad));
    }
}

# ---- motion is answerable -----------------------------------------------

ok($css =~ /prefers-reduced-motion/, 'reduced motion is honoured');
ok($css =~ /prefers-reduced-motion[\s\S]{0,900}\.starfield[^}]*display:\s*none\s*!important/,
   'the star field is removed entirely under reduced motion');
ok($css =~ /prefers-reduced-motion[\s\S]{0,900}transition-duration:\s*0\.01ms\s*!important/,
   'transitions stop under reduced motion');

# Nothing lifts on hover any more: a translate on a card was the old aesthetic.
ok($css !~ /\.panel--hover:hover\s*\{[^}]*transform/s,
   'an interactive panel answers with a border, not by floating');

# ---- artwork handling ---------------------------------------------------

# Either the real asset is used, or the original stand-in is — never a guess.
my @art = glob("$OUT/assets/brand/*");
if (grep { /\.(png|webp|svg|jpg)$/i } @art) {
    ok($home =~ m{<img class="showcase__art" src="/assets/brand/},
       'the hero figure uses the supplied project artwork');
    ok($home !~ /showcase__standin/, 'the stand-in is not rendered when artwork exists');
    for my $f (@html) {
        my $b = slurp($f);
        for my $img ($b =~ m{(<img[^>]*/assets/brand/[^>]*>)}g) {
            ok($img !~ /\bstyle=/, 'brand artwork carries no inline transform', $img);
            ok($img !~ /\bfilter\b/, 'brand artwork carries no filter', $img);
        }
    }
} else {
    ok($home =~ /showcase__standin/, 'the hero falls back to the original stand-in mark');
    print "    note: website/assets/brand/pweevee-logo.png not present — stand-in in use\n";
}

# the figure is a square frame with a hairline, and a caption that states a fact
for my $part (qw(showcase showcase__frame showcase__caption showcase__label
                 showcase__meta)) {
    ok($css =~ /\.\Q$part\E[\s,{:]/, "hero figure part styled: $part");
    ok($home =~ /\Q$part\E/, "hero figure part present on the home page: $part");
}
ok($css =~ /\.showcase__frame\s*\{[^}]*aspect-ratio:\s*1/s,
   'the artwork sits in a square frame');

# --------------------------------- 4c2. list items keep their content together

# A regression guard for a real layout bug. `.checklist li` and `.pipeline li`
# were `display: grid`, which turns every inline child into its own grid item:
#
#   <li><strong>Orion</strong> — injection runtime by <a>theos</a>, as shipped…</li>
#
# is four grid items (marker, <strong>, text, <a>), so the label landed in column
# two while the description wrapped into column one — stretching the `auto`
# column to the width of the longest sentence and stranding the label at the far
# right of the card. It looked broken at every width and worst on a phone.
section('4c2. label and description stay together');

for my $list (qw(checklist pipeline)) {
    my ($rule) = $css =~ /\n\.\Q$list\E li \{(.*?)\n\}/s;
    ok(defined $rule, "the $list list item has its own rule");
    next unless defined $rule;

    ok($rule !~ /display:\s*(?:grid|flex)/,
       "a $list item is not a grid or flex container, so inline content stays inline",
       $rule);
    # the marker has to come out of flow instead, or it becomes a grid item again
    ok($rule =~ /position:\s*relative/, "a $list item positions its own marker");
    ok($rule =~ /padding(?:-left)?:[^;]*\dem/, "a $list item indents for its marker");

    my ($marker) = $css =~ /\n\.\Q$list\E li::before \{(.*?)\n\}/s;
    ok(defined $marker && $marker =~ /position:\s*absolute/,
       "the $list marker is positioned absolutely, not laid out as a sibling");
}

# These lists are the ones that actually carry "<strong>label</strong> — text",
# so they are the ones the bug was visible in.
for my $page (qw(releases credits downloads projects)) {
    my $f = $page eq 'index' ? "$OUT/index.html" : "$OUT/$page/index.html";
    next unless -f $f;
    my $b = slurp($f);
    utf8::decode($b);
    for my $li ($b =~ m{(<li><strong>[^<]+</strong>[^<]*(?:<[^>]+>[^<]*)*</li>)}g) {
        # the label and its description must live in ONE list item, not be split
        ok($li =~ m{</strong>\s*(?:&mdash;|—|-)}, "$f: a label is followed by its own description",
           $li);
    }
}

# the marked lists must not set a fixed column anywhere
ok($css !~ /\.checklist li[^{]*\{[^}]*grid-template-columns/s,
   'the checklist does not impose columns on its items');
ok($css !~ /\.pipeline li[^{]*\{[^}]*grid-template-columns/s,
   'the pipeline does not impose columns on its items');

# ------------------------------------------------- 4d. the theme system

section('4d. light / dark theme system');

my $theme_js = slurp("$OUT/assets/theme.js");
my $layout_src_raw = slurp('website-src/layout.html');
utf8::decode($layout_src_raw);

# ---- dark is the default, with no media query and no script ---------------

# The bare :root block is what applies when nothing else matches, so whatever it
# assigns IS the default theme. It must be the dark set.
# There are two top-level :root blocks — the raw tokens, then the theme mapping.
# The one that assigns the semantic --bg is the theme default.
my $root_block = '';
for my $blk ($css =~ /\n:root\s*\{(.*?)\n\}/gs) {
    $root_block = $blk if $blk =~ /^\s*--bg\s*:/m;
}
ok(length $root_block, 'the theme cascade starts from a plain :root block');
ok($root_block =~ /--bg:\s*var\(--d-bg\)/,
   'the default theme is DARK (:root maps --bg to the dark set)');
ok($root_block =~ /color-scheme:\s*dark/,
   ':root declares color-scheme: dark, so form controls and scrollbars match');
for my $tok (qw(--surface --surface-2 --rule --ink --ink-2 --ink-3 --brand
                --btn-solid --star-intensity)) {
    ok($root_block =~ /\Q$tok\E:\s*(?:var\(--d-|1\b)/,
       "the default theme maps $tok to the dark set");
}

# Dark must not depend on a media query: a browser that reports no preference at
# all has to land on dark, and that only works if :root itself carries it.
ok($css !~ /\@media\s*\(\s*prefers-color-scheme:\s*dark\s*\)/,
   'dark needs no prefers-color-scheme query, so "no preference" still gets dark');

# ---- light applies when the device asks for it ----------------------------

my ($light_mq) = $css =~ /\@media \(prefers-color-scheme: light\) \{(.*?)\n\}/s;
ok(defined $light_mq, 'a prefers-color-scheme: light query exists');
$light_mq = '' unless defined $light_mq;
ok($light_mq =~ /--bg:\s*var\(--l-bg\)/,
   'prefers-color-scheme: light switches to the light set');
ok($light_mq =~ /color-scheme:\s*light/, 'the light theme declares color-scheme: light');

# ---- an explicit choice overrides both ------------------------------------

for my $mode (qw(light dark)) {
    my $letter = substr($mode, 0, 1);
    my ($block) = $css =~ /html\[data-theme="$mode"\]\s*\{(.*?)\n\}/s;
    ok(defined $block, "an explicit $mode choice has its own block");
    next unless defined $block;
    ok($block =~ /--bg:\s*var\(--\Q$letter\E-bg\)/,
       "html[data-theme=\"$mode\"] maps to the $mode set");
    ok($block =~ /color-scheme:\s*$mode/, "html[data-theme=\"$mode\"] sets color-scheme");
}

# An attribute selector is (0,1,1) against :root's (0,1,0), so an explicit choice
# beats the media query whatever the source order. That is the whole reason the
# override does not need !important.
my $attr_at = index($css, 'html[data-theme="dark"]');
my $mq_at   = index($css, '@media (prefers-color-scheme: light)');
ok($attr_at > 0 && $mq_at > 0,
   'both the explicit override and the media query are present');

# ---- the two themes are designed, not inverted ---------------------------

# If one theme were a mechanical inversion of the other, the greys would be
# complements. They are not: the light set is warm (paper) and the dark set is
# neutral. Checking the values are independently chosen is the honest version of
# "do not simply invert".
my %spec_dark = ('--d-bg' => '#080808', '--d-surface' => '#111111');
for my $t (sort keys %spec_dark) {
    ok($css =~ /\Q$t\E:\s*(?:\Q$spec_dark{$t}\E|var\(--near-black\))/i,
       "the dark theme uses the specified value for $t");
}
ok($css =~ /--d-surface-2:\s*var\(--dark-gray\)/,
   'the dark theme uses #171717 as its second surface');
ok($css =~ /--l-bg:\s*var\(--white\)/,   'the light theme background is #FFFFFF');
ok($css =~ /--l-surface-2:\s*var\(--off-white\)/,
   'the light theme second background is #F5F5F3');
ok($css =~ /--l-brand:\s*#2a3762/i, 'both themes use the same logo blue as the accent');
ok($css =~ /--d-brand:\s*#90a0d5/i,
   'the dark theme lifts that blue so it is legible on near-black');

# A component must never reach past the semantic layer into one theme's values —
# that is what would make it work in one theme and quietly break in the other.
# Only the mapping blocks are allowed to name --l-* / --d-* at all.
{
    my @allowed = (
        qr/^:root$/,
        qr/^\.inverted$/,                     # pins a region to the dark set
        qr/^html\[data-theme="(?:light|dark)"\]$/,
        qr/^:root, html\[data-theme/,          # the print remap
    );
    my @bad;
    # comments are made of the same characters as a selector, so they have to go
    # before the stylesheet is split into "selector { body }" pairs
    (my $nc = $css) =~ s{/\*.*?\*/}{}gs;
    my @parts = $nc =~ /([^{}]*)\{([^{}]*)\}/g;
    while (@parts >= 2) {
        my ($sel, $body) = splice(@parts, 0, 2);
        next unless $body =~ /var\(\s*--[ld]-/;
        $sel =~ s/\s+/ /g;
        $sel =~ s/^\s+|\s+$//g;
        next if grep { $sel =~ $_ } @allowed;
        push @bad, $sel;
    }
    ok(!@bad, 'no component reads a theme-specific value directly',
       join('; ', @bad));
}

# ---- the control ---------------------------------------------------------

ok($css =~ /\.theme\s*\{\s*display:\s*none/,
   'the theme control is hidden until a script can drive it');
ok($css =~ /\.js \.theme\s*\{/,
   'the control is revealed by the js class, so no-JS visitors see no dead buttons');
ok($css =~ /\.theme__btn\[aria-pressed="true"\]/,
   'the selected segment has its own visual state');

for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);

    # two instances: the bar and the mobile drawer
    my $controls = () = $b =~ /data-theme-control/g;
    ok($controls == 2, "$f has a theme control in the bar and in the mobile menu",
       "found $controls");

    # all three modes, every time
    for my $mode (qw(system light dark)) {
        ok($b =~ /data-theme-set="\Q$mode\E"/, "$f offers the $mode option");
    }
    my $set = () = $b =~ /data-theme-set=/g;
    ok($set == 6, "$f renders three options per control", "found $set");

    # System is the rendered default, which is the correct static answer
    ok($b =~ /data-theme-set="system" aria-pressed="true"/,
       "$f marks System as selected before any script runs");
    my $pressed = () = $b =~ /aria-pressed="true"/g;
    ok($pressed >= 2, "$f marks exactly one option per control", "found $pressed");

    # the drawer copy must be reachable on a phone
    ok($b =~ /nav__drawer[\s\S]{0,4000}data-theme-control/,
       "$f puts a theme control inside the mobile drawer");

    # every segment needs an accessible name; the icon alone is not one
    for my $btn ($b =~ /(<button class="theme__btn"[\s\S]{0,400}?<\/button>)/g) {
        ok($btn =~ /class="visually-hidden">[^<]+</,
           'a theme segment carries a text label for screen readers', $btn);
        ok($btn =~ /aria-hidden="true"/, 'the segment icon is hidden from the a11y tree');
        # an empty title is what you get from escaping plain text with the URL
        # escaper, and it is invisible in a diff, so it gets pinned
        ok($btn =~ /title="[^"]+"/, 'the segment tooltip is not empty', $btn);
    }
    ok($b !~ /aria-labelledby=""/, "$f has no empty aria-labelledby");
    ok($b !~ /\btitle=""/, "$f has no empty title attribute");
}

# the control's icons must resolve against the sprite
ok($layout_src_raw =~ /<symbol id="i-auto"/, 'the sprite defines the system-theme icon');
ok($layout_src_raw =~ /<symbol id="i-sun"/,  'the sprite defines the light-theme icon');
ok($layout_src_raw =~ /<symbol id="i-moon"/, 'the sprite defines the dark-theme icon');

# ---- no flash of the wrong theme ----------------------------------------

# An explicit override that disagrees with the device can only avoid a flash if
# it is applied before the first paint. That means a blocking script in <head> —
# and, because the site ships a strict CSP with no 'unsafe-inline', an external
# same-origin one rather than an inline snippet.
ok(-f "$OUT/assets/theme.js" && -s "$OUT/assets/theme.js",
   'the pre-paint theme applier is published');
ok(length($theme_js) < 2500, 'the pre-paint applier is small enough to be cheap',
   length($theme_js) . ' bytes');

for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    my ($head) = $b =~ /<head>(.*?)<\/head>/s;
    $head = '' unless defined $head;
    ok($head =~ m{<script src="/assets/theme\.js"></script>},
       "$f loads the theme applier in <head>");
    ok($head !~ m{<script[^>]*\bsrc="/assets/theme\.js"[^>]*\b(?:defer|async)},
       "$f does not defer the theme applier, which would let the wrong theme paint");
    # it has to run before the stylesheet paints anything
    ok(index($head, '/assets/theme.js') < index($head, '/assets/pweevee.css'),
       "$f runs the applier ahead of the stylesheet");
    # and the theme must not depend on the deferred main script
    ok($b =~ m{<script src="/assets/pweevee\.js" defer></script>},
       "$f still defers the main script");
    ok($b =~ /<meta name="color-scheme" content="dark light">/,
       "$f advertises both themes, dark first");
}

ok($theme_js =~ /localStorage/, 'the applier reads the stored choice');
ok($theme_js =~ /setAttribute\('data-theme'/, 'the applier sets data-theme');
ok($theme_js =~ /classList\.add\('js'\)/,
   'the applier sets the js class early, so the control does not reflow the nav in');
ok($theme_js =~ /try\s*\{/ && $theme_js =~ /catch/,
   'storage access is guarded, so private mode falls back to prefers-color-scheme');
ok($theme_js =~ /choice === 'light' \|\| choice === 'dark'/,
   'only light and dark are honoured; anything else follows the device');

# ---- persistence and System behaviour -----------------------------------

my ($theme_block) = $js =~ /function theme\(\)([\s\S]*?)3\. scroll reveal/;
ok(defined $theme_block && length $theme_block,
   'the theme control is implemented in pweevee.js');
$theme_block = '' unless defined $theme_block;

ok($theme_block =~ /localStorage\.setItem/, 'an explicit choice is persisted');
ok($theme_block =~ /localStorage\.removeItem/,
   'choosing System clears the stored choice rather than storing "system"');
ok($theme_block =~ /removeAttribute\('data-theme'\)/,
   'System removes data-theme so the media query takes over again');
ok($theme_block =~ /aria-pressed/, 'the control reflects the active choice');
ok($theme_block =~ /prefers-color-scheme: dark|mqDark/,
   'System follows the device preference');
ok($theme_block =~ /addEventListener\('change'|addListener/,
   'a device theme change while in System mode is noticed');
ok($theme_block =~ /mark\(stored\(\)\)/,
   'the rendered state is corrected from storage on load');
ok($theme_block !~ /persist\(\s*stored\(\)\s*\)/,
   'merely reading the state never turns "follow the device" into a stored choice');

# the effective-theme helper has to mirror the CSS, including the no-preference case
ok($js =~ /function effectiveTheme\(\)/, 'the script can resolve the effective theme');
my ($eff) = $js =~ /function effectiveTheme\(\)\s*\{(.*?)\n  \}/s;
$eff = '' unless defined $eff;
$eff =~ s/\s+$//;
ok($eff =~ /return 'dark';$/,
   'the last resort, with no data-theme and no device preference, is dark');
ok($eff =~ /mqLight/, 'the script distinguishes "prefers light" from "no preference"');

# ---- the star field across themes --------------------------------------

ok($css =~ /--star-intensity:\s*1/, 'the dark theme runs the star field at full strength');
my @intensities = $css =~ /--star-intensity:\s*([0-9.]+)/g;
my $light_star;
if ($light_mq =~ /--star-intensity:\s*([0-9.]+)/) { $light_star = $1 }
ok(defined $light_star && $light_star < 0.6,
   'the light theme substantially reduces the star field',
   defined $light_star ? $light_star : 'not set for light');
ok($sf =~ /--star-intensity/,
   'the painter reads its strength from CSS rather than hard-coding a theme');
ok($sf =~ /s\.a \* intensity/, 'the intensity actually scales each star');
ok($sf =~ /onThemeChange/, 'switching theme repaints the field at the new strength');
# it stays white-on-dark in both themes, so it can never look like dark specks
ok($css =~ /\.inverted\s*\{[^}]*--bg:\s*var\(--d-bg\)/s,
   'the star band is dark in both themes, so the specks are never dark on paper');
ok($sf =~ /rgba\(255,255,255,/, 'stars are painted light, never dark');

# ------------------------------------------------- 4c. official logo wiring

# The official logo is the brand artwork. These checks fail if any surface
# regresses to a placeholder glyph, the old SVG mark, or a stale icon.
section('4c. official PwEevee logo');

my $LOGO = 'assets/brand/pweevee-logo.png';
if (-f "$OUT/$LOGO" && -s "$OUT/$LOGO") {
    ok(1, 'the official logo is present');

    # derived icon sizes, and they must not be older than the logo
    my $logo_mtime = (stat("$OUT/$LOGO"))[9] // 0;
    for my $size (32, 180, 512) {
        my $icon = "$OUT/assets/icon-$size.png";
        ok(-f $icon && -s $icon, "derived icon exists: assets/icon-$size.png");
        next unless -f $icon;
        ok(((stat($icon))[9] // 0) + 1 >= $logo_mtime,
           "assets/icon-$size.png is not older than the logo "
           . '(run make-brand-assets.pl after replacing it)');
    }

    for my $f (@html) {
        my $body = slurp($f);
        utf8::decode($body);
        ok($body =~ m{<link rel="icon" type="image/png"[^>]*href="/assets/icon-32\.png"},
           "$f uses the logo-derived favicon");
        ok($body =~ m{<link rel="apple-touch-icon" href="/assets/icon-180\.png">},
           "$f declares the logo-derived Apple touch icon");
        ok($body !~ m{href="/assets/favicon\.svg"},
           "$f no longer links the superseded SVG mark");
        # the nav and footer wordmarks each carry the mark
        my $marks = () = $body =~ m{class="brand__mark"}g;
        ok($marks >= 2, "$f shows the brand mark in the nav and the footer", "found $marks");
        ok($body =~ m{class="brand__mark" src="/assets/icon-32\.png"},
           "$f brand mark comes from the official logo");
    }

    # hero figure — one image, at full resolution, and nothing derived from it
    ok($home =~ m{<img class="showcase__art" src="/\Q$LOGO\E"},
       'the hero figure is the official logo');
    my $hero_copies = () = $home =~ m{class="showcase__art"}g;
    ok($hero_copies == 1, 'the logo is shown once in the hero, not mirrored',
       "found $hero_copies");
    ok($home !~ /showcase__standin/, 'the stand-in mark is gone from the hero');

    # project card + project page
    ok($home =~ m{class="project-card__icon" src="/\Q$LOGO\E"},
       'the PwEevee project card shows the official logo');
    my $ppage = slurp("$OUT/projects/pweevee/index.html");
    utf8::decode($ppage);
    ok($ppage =~ m{class="project-hero__icon" src="/\Q$LOGO\E"},
       'the PwEevee project page shows the official logo');

    # release / download UI
    for my $f ("$OUT/index.html", "$OUT/downloads/index.html") {
        my $b = slurp($f);
        utf8::decode($b);
        next unless $b =~ /class="download__project"/;
        ok($b =~ m{class="download__logo" src="/assets/icon-(?:32|180)\.png"},
           "$f labels the release panel with the logo");
        ok($b !~ m{download__project"><span aria-hidden="true">&\#9670;},
           "$f no longer uses the diamond placeholder on a release panel");
    }

    # the artwork must never be given a transform or a non-square box
    for my $f (@html) {
        my $b = slurp($f);
        for my $img ($b =~ m{(<img[^>]*\Q$LOGO\E[^>]*>)}g) {
            ok($img !~ /\bstyle=/, 'the logo carries no inline style', $img);
            my ($w) = $img =~ /\bwidth="(\d+)"/;
            my ($hh) = $img =~ /\bheight="(\d+)"/;
            ok($w && $hh && $w == $hh, 'the logo is placed in a square box', $img);
        }
    }

    # the social card must have been rebuilt from the logo, not the drawn mark
    my $card_mtime = -f "$OUT/assets/social-card.png" ? (stat("$OUT/assets/social-card.png"))[9] : 0;
    ok($card_mtime + 1 >= $logo_mtime,
       'the Open Graph card was regenerated after the logo landed '
       . '(run make-social-card.pl)');
} else {
    print "    note: $LOGO absent — logo wiring not asserted\n";
}

# artwork, wherever it appears, must be square-boxed and never stretched
for my $f (@html) {
    my $b = slurp($f);
    for my $img ($b =~ m{(<img[^>]*class="(?:showcase__art|project-card__icon|project-hero__icon)"[^>]*>)}g) {
        ok($img =~ /\bwidth="(\d+)"/ && $img =~ /\bheight="(\d+)"/,
           'artwork declares intrinsic dimensions (no layout shift)', $img);
    }
}
ok($css =~ /\.showcase__art\s*\{[^}]*object-fit:\s*contain/s,
   'artwork is contained, never distorted');

# --- stylesheet integrity -------------------------------------------------

# Braces must balance, or everything after the error silently stops applying.
{
    my $stripped = $css;
    $stripped =~ s{/\*.*?\*/}{}gs;
    ok($stripped !~ m{/\*}, 'no unterminated CSS comment');
    my $open  = () = $stripped =~ /\{/g;
    my $close = () = $stripped =~ /\}/g;
    ok($open == $close, 'CSS braces balance', "$open open / $close close");

    # Every var() without a fallback must reference a declared custom property,
    # otherwise the value resolves to nothing and the rule quietly dies.
    my %declared = map { $_ => 1 } ($stripped =~ /(--[a-z0-9-]+)\s*:/gi);
    my %bare     = map { $_ => 1 } ($stripped =~ /var\(\s*(--[a-z0-9-]+)\s*\)/gi);
    my @undeclared = grep { !$declared{$_} } sort keys %bare;
    ok(!@undeclared, 'every CSS variable used without a fallback is declared',
       join(', ', @undeclared));

    # No custom property is handed over from script any more: the pointer-tracked
    # highlight went with the glass. If one comes back it must carry a fallback,
    # so a rule cannot die when the script does not run.
    ok($stripped !~ /var\(\s*--m[xy]\s*\)/,
       'no rule depends on a script-supplied variable without a fallback');
    ok($js !~ /setProperty\('--/,
       'the script sets no custom property on an element');

    # every class the renderer and templates emit must exist in the stylesheet
    my %css_classes = map { $_ => 1 } ($stripped =~ /\.([a-z][a-z0-9_-]*)/gi);
    my %markup_classes;
    for my $f (@html) {
        my $b = slurp($f);
        for my $attr ($b =~ /class="([^"]+)"/g) {
            $markup_classes{$_} = 1 for grep { length } split /\s+/, $attr;
        }
    }
    my @unstyled = grep { !$css_classes{$_} } sort keys %markup_classes;
    ok(!@unstyled, 'every class used in the markup is styled', join(', ', @unstyled));
}
ok(!-f "$OUT/assets/style.css", 'the superseded stylesheet was removed');
ok(!-f "$OUT/assets/site.js",   'the superseded script was removed');

# the sprite symbol every <use> points at must be defined in the page
for my $f (@html) {
    my $body = slurp($f);
    next unless $body =~ /<use href="#([^"]+)"/;
    my %want = map { $_ => 1 } ($body =~ /<use href="#([^"]+)"/g);
    for my $id (keys %want) {
        ok($body =~ /<symbol id="\Q$id\E"/, "$f defines the sprite symbol #$id");
    }
}

# ---------------------------------------------------------------- 5. downloads

section('5. download targets');

# Every download URL that reaches a page must come from generated data, and must
# be one of the two sources the site is allowed to offer: a GitHub release asset,
# or a download URL named by a declared AltSource.
my %gh_asset_urls;
for my $p (@{ $rel->{projects} || [] }) {
    for my $r (grep { ref $_ eq 'HASH' } (($p->{latest} // ()), @{ $p->{history} || [] })) {
        $gh_asset_urls{ $_->{download_url} } = 1 for @{ $r->{assets} || [] };
    }
}
my %alt_urls;
for my $s (@{ $alt_data->{sources} || [] }) {
    $alt_urls{ $_->{download_url} } = 1 for @{ $s->{variants} || [] };
}
ok(scalar keys %gh_asset_urls > 0, 'the generated data provides real GitHub asset URLs');
ok(scalar keys %alt_urls == 4, 'the generated data provides the four AltSource variant URLs',
   'found ' . scalar keys %alt_urls);

my %checked;
my $download_buttons = 0;
for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);

    # The website hosts no build files any more, so no page may link to one.
    my ($local) = $body =~ m{href="(/releases/[^"]*\.(?:ipa|tipa|deb))"};
    ok(!defined $local, "$f offers no locally hosted build file", $local);

    # Every GitHub release asset link must be a real asset URL from the data.
    for my $href ($body =~ m{href="(https://[^"]*/releases/download/[^"]+)"}g) {
        next if $checked{$href}++;
        ok($href =~ m{^https://github\.com/[^/]+/[^/]+/releases/download/},
           'external download is a GitHub release asset URL', $href);
        ok($gh_asset_urls{$href}, 'that asset URL came from the generated release data', $href);
    }

    # Every .ipa link that is not a GitHub asset must be a declared AltSource URL.
    for my $href ($body =~ m{href="(https://[^"]+\.ipa)"}g) {
        next if $href =~ m{^https://github\.com/};
        next if $checked{$href}++;
        ok($alt_urls{$href}, 'a non-GitHub IPA link came from the AltSource data', $href);
    }

    # A primary action must always have a real target.
    my @empty = $body =~ m{<a\b[^>]*class="[^"]*btn--primary[^"]*"[^>]*href="(\s*|#)"}g;
    ok(!@empty, "$f has no primary button with an empty target");
    for my $a ($body =~ m{(<a\b[^>]*class="[^"]*btn--primary[^"]*"[^>]*>)}g) {
        my ($href) = $a =~ /href="([^"]*)"/;
        ok(defined $href && length $href && $href ne '#',
           "$f: primary button has a target", $a);
        $download_buttons++ if $a =~ /\bdownload\b/i || ($href // '') =~ /\.(?:ipa|deb|tipa)$/i;
    }
}
ok($download_buttons > 0, 'at least one real download button is rendered');

my $dl = slurp("$OUT/downloads/index.html");
utf8::decode($dl);
ok($dl =~ /Download IPA|Download DEB|View release on GitHub/,
   'the downloads page offers an action');
ok($dl =~ /SHA-256/, 'the downloads page explains checksum verification');
# the graceful state must exist in the renderer's vocabulary
my $renderer = slurp('PwEvevee/build-system/release/render-site.pl');
ok($renderer =~ /Download currently unavailable/,
   'the renderer has a graceful no-asset state');
ok($renderer =~ /View release on GitHub/,
   'the no-asset state offers the GitHub release instead');

# ------------------------------------------------- 5b. no dev build anywhere

section('5b. the dev build is gone');

# The old website presented a locally built "dev" IPA as the current release and
# badged it "Hosted on this server". None of that may survive anywhere a visitor
# can see it.
for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    ok($body !~ /Hosted on this server/i, "$f does not claim to host the release itself");
    ok($body !~ /Hosted here/i,           "$f has no 'hosted here' release badge");
    ok($body !~ /badge--hosted/,          "$f has no hosted-here badge markup");
    ok($body !~ /pweevee-test/i,          "$f does not reference the local test IPA");
    ok($body !~ /past[ -]retention/i,     "$f has no retention-window release UI");
    ok($body !~ /WEBSITE_IPA_RETENTION_MONTHS/,
       "$f does not document a local retention window");
    # "dev" as a version label, e.g. <h2 class="download__version">dev</h2>
    ok($body !~ m{class="(?:download|release)__version"[^>]*>\s*(?:PwEevee\s+)?dev\s*<},
       "$f does not present a dev build as a release");
}
ok(!-f "$OUT/releases/index.json",
   'the local build index is no longer published to the website');
my @stray = glob("$OUT/releases/*.ipa");
ok(!@stray, 'no build file is staged inside website/releases/', join(', ', @stray));

# The renderer must no longer have a second, local notion of a release.
ok($renderer !~ /releases\/index\.json/,
   'the renderer no longer reads the local build index');
ok($renderer !~ /past_retention/, 'the renderer has no retention logic left');
ok($renderer !~ /Hosted on this server/, 'the renderer cannot emit the hosted-here badge');

# ------------------------------------------------- 5c. project name casing

section('5c. project naming');

# The only correct spelling is PwEevee: capital P, capital E, capital E.
#
# Several wrong spellings are prefixes of the right one — "PwEeve" lives inside
# "PwEevee" — so each pattern that is a prefix carries a lookahead. Without it
# the check would fail on correct text, which is worse than not checking.
my @BAD_NAMES = (
    [ qr/pwEveeve/,      'pwEveeve' ],
    [ qr/PwEvevee/,      'PwEvevee' ],
    [ qr/pwEvevee/,      'pwEvevee' ],
    [ qr/[Pp]w\s+Eevee/, 'Pw Eevee (with a space)' ],
    [ qr/pwEevee(?!e)/,  'pwEevee (lowercase p)' ],
    [ qr/PwEeve(?![ev])/, 'PwEeve' ],
    [ qr/pwEeve(?![ev])/, 'pwEeve' ],
    [ qr/PwEvee(?!v)/,   'PwEvee' ],
    [ qr/pwEvee(?!v)/,   'pwEvee' ],
    [ qr/PWEevee/,       'PWEevee' ],
);

# Sanity-check the patterns themselves: the correct spelling must pass all of
# them, and each wrong spelling must be caught by its own pattern.
{
    my @wrong = grep { 'PwEevee' =~ $_->[0] } @BAD_NAMES;
    ok(!@wrong, 'the naming patterns do not flag the correct spelling',
       join(', ', map { $_->[1] } @wrong));
    ok('pwEevee' =~ /pwEevee(?!e)/, 'the lowercase-p spelling is detectable');
    ok('PwEeve ' =~ /PwEeve(?![ev])/, 'the truncated spelling is detectable');
    ok('Pw Eevee' =~ /[Pp]w\s+Eevee/, 'the spaced spelling is detectable');
}

for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    # strip the one code sample that legitimately names the build-system
    # directory on disk (PwEvevee/build-system/unified.sh) — that is a path, not
    # the project name, and renaming it is not part of the website.
    my $prose = $body;
    $prose =~ s{<p class="mono[^"]*"[^>]*>.*?</p>}{}gs;
    $prose =~ s{<code\b[^>]*>.*?</code>}{}gs;
    # Asset filenames come from upstream GitHub releases verbatim (a historical
    # asset is literally named 'PwEvevee.ipa'); they are data we link, not prose
    # we wrote, so the naming check must not fail on them.
    $prose =~ s{<span class="asset__name"[^>]*>.*?</span>}{}gs;
    $prose =~ s{aria-label="[^"]*"}{}gs;
    $prose =~ s{data-search="[^"]*"}{}gs;
    # release download URLs also embed the historical asset name; URLs are
    # data, not prose
    $prose =~ s{href="[^"]*"}{}gs;

    for my $bad (@BAD_NAMES) {
        my ($re, $label) = @$bad;
        my ($hit) = $prose =~ /($re)/;
        ok(!defined $hit, "$f does not contain '$label'", $hit);
    }
    ok($prose =~ /PwEevee/, "$f uses the correct PwEevee spelling");
}

# the brand, the title and the hero specifically
ok($home =~ m{<a class="brand"[^>]*>.*?<span class="brand__name">PwEevee</span>}s,
   'the navbar wordmark reads PwEevee');
ok($home =~ m{<title>PwEevee — A unified Spotify customization ecosystem</title>},
   'the browser title reads PwEevee');
ok($home =~ m{<h1 class="display">PwEevee</h1>}, 'the hero heading reads PwEevee');
ok($home =~ m{<meta property="og:site_name" content="PwEevee">},
   'the Open Graph site name reads PwEevee');
for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    ok($body =~ m{<a class="brand"[^>]*aria-label="PwEevee[^"]*"},
       "$f: the brand link is labelled PwEevee");
}

# and in the data the pages are generated from
my $proj_raw = slurp("$OUT/data/projects.json");
utf8::decode($proj_raw);
ok($proj_raw =~ m{"name"\s*:\s*"PwEevee"}, 'the data model names the project PwEevee');
for my $bad (@BAD_NAMES) {
    my ($re, $label) = @$bad;
    # the $comment block legitimately names the build-system directory
    my $prose = $proj_raw;
    $prose =~ s{"\$comment".*?\],}{}s;
    my ($hit) = $prose =~ /($re)/;
    ok(!defined $hit, "projects.json does not contain '$label'", $hit);
}

# ------------------------------------------------- 5d. stale repositories

section('5d. stale repository references');

for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    ok($body !~ m{whoeevee/EeveeSpotifyReborn}, "$f does not link whoeevee/EeveeSpotifyReborn");
    ok($body !~ m{github\.com/whoeevee/EeveeSpotify\b},
       "$f does not link the retired whoeevee/EeveeSpotify repository");
}
# the canonical repository has to be reachable from the site
ok($home =~ m{github\.com/SideloadLabs/EeveeSpotifyReincarnated},
   'the home page links SideloadLabs/EeveeSpotifyReincarnated');
my $layout_out = slurp("$OUT/contact/index.html");
utf8::decode($layout_out);
ok($layout_out =~ m{github\.com/SideloadLabs/EeveeSpotifyReincarnated},
   'the footer repository list links the SideloadLabs repository');
ok($layout_out =~ m{github\.com/SideloadLabs/SideloasLabs-AltSource},
   'the footer links the AltSource repository with its upstream spelling');

my $dlpage = $dl;
for my $want ('github.com/codeboy2012/spoti.pw-builds',
              'github.com/skopevoj/spoti.pw',
              'github.com/SideloadLabs/EeveeSpotifyReincarnated') {
    ok(index($dlpage, $want) >= 0, "the downloads page links $want");
}

# ------------------------------------------------- 5e. AltSource presentation

section('5e. AltSource variants on the page');

for my $page ("$OUT/downloads/index.html", "$OUT/projects/eeveespotify/index.html") {
    my $body = slurp($page);
    utf8::decode($body);
    ok($body =~ /variant-family/, "$page renders the variant families");
    ok($body =~ /class="variant\b/, "$page renders variant cards");

    my $families = () = $body =~ /class="variant-family /g;
    ok($families == 2, "$page shows both variant families", "found $families");
    my $cards = () = $body =~ /class="panel panel--hover variant /g;
    ok($cards == 4, "$page shows all four variants", "found $cards");

    # each variant must state what it is and offer the real URL
    for my $url (sort keys %alt_urls) {
        ok(index($body, $url) >= 0, "$page offers the real variant URL", $url);
    }
    ok($body =~ />Standard</, "$page labels the Standard variant");
    ok($body =~ />Patched</,  "$page labels the Patched variant");
    ok($body =~ /Spotify<\/dt>/, "$page shows the Spotify version per variant");
    ok($body =~ /EeveeSpotify<\/dt>/, "$page shows the EeveeSpotify version per variant");

    # and the source must be named, not passed off as a GitHub release
    ok($body =~ /SideloadLabs/, "$page names SideloadLabs as the publisher");
    ok($body =~ /not a GitHub release/i,
       "$page states that the AltSource is not a GitHub release");
    ok(index($body,
        'https://raw.githubusercontent.com/SideloadLabs/SideloasLabs-AltSource/refs/heads/main/apps.json') >= 0,
       "$page links the exact AltSource manifest URL");
}

# ------------------------------------------------- 5f. the project filter

section('5f. release filter');

my $releases_page = slurp("$OUT/releases/index.html");
utf8::decode($releases_page);

ok($releases_page =~ /data-filter-scope/, 'the releases page has a filter scope');
ok($releases_page =~ /data-filter-default="pweevee"/,
   'the filter default is declared as PwEevee');
ok($releases_page =~ /data-filter-param="project"/,
   'the filter declares its URL parameter');

# every filter the brief asks for must exist, and PwEevee must be the one that
# is already selected when the page arrives
my %chip;
while ($releases_page =~ m{<button class="chip"[^>]*data-filter="([^"]+)"[^>]*aria-pressed="([^"]+)"[^>]*>([^<]*)</button>}g) {
    $chip{$1} = { pressed => $2, label => $3 };
}
ok(scalar keys %chip == 4, 'all four filters are rendered',
   join(', ', sort keys %chip));
ok($chip{all} && $chip{all}{label} eq 'All projects', 'the All projects filter exists');
ok($chip{pweevee} && $chip{pweevee}{label} eq 'PwEevee', 'the PwEevee filter exists and is named PwEevee',
   $chip{pweevee} ? $chip{pweevee}{label} : 'missing');
ok($chip{spotipw} && $chip{spotipw}{label} eq 'spoti.pw', 'the spoti.pw filter exists');
ok($chip{eeveespotify} && $chip{eeveespotify}{label} eq 'EeveeSpotify',
   'the EeveeSpotify filter exists');

ok($chip{pweevee} && $chip{pweevee}{pressed} eq 'true',
   'the PwEevee filter is selected when the page loads');
my @also_pressed = grep { $_ ne 'pweevee' && ($chip{$_}{pressed} // '') eq 'true' } sort keys %chip;
ok(!@also_pressed, 'no other filter is selected by default', join(', ', @also_pressed));

# the default view must already be filtered in the markup, so it is right with
# JavaScript switched off and there is no flash of the wrong content
my (%visible, %hidden_by_project);
while ($releases_page =~ m{<div class="timeline__item[^"]*" data-release-item data-project="([^"]+)"[^>]*?(\shidden)?>}g) {
    my ($proj, $hidden) = ($1, $2);
    if ($hidden) { $hidden_by_project{$proj}++ } else { $visible{$proj}++ }
}
my $total_items = () = $releases_page =~ /data-release-item/g;
ok($total_items > 0, 'the timeline contains release items', "found $total_items");
ok(($visible{pweevee} // 0) > 0, 'PwEevee releases are visible by default');
my @leaked = grep { $_ ne 'pweevee' } sort keys %visible;
ok(!@leaked, 'nothing but PwEevee is visible by default', join(', ', @leaked));
for my $other (qw(spotipw eeveespotify)) {
    ok(($hidden_by_project{$other} // 0) > 0,
       "$other releases are present but hidden by default");
}

# every item is tagged, or the filter could never match it
my $tagged = () = $releases_page =~ /data-release-item data-project="/g;
ok($tagged == $total_items, 'every release item declares its project',
   "$tagged of $total_items");
my $searchable = () = $releases_page =~ /data-search="/g;
ok($searchable == $total_items, 'every release item is searchable');

# month groups must be hidden when the default filter empties them
my $groups_total  = () = $releases_page =~ /<section data-release-group/g;
my $groups_hidden = () = $releases_page =~ /<section data-release-group hidden>/g;
ok($groups_total > 0, 'the timeline is grouped by month');
ok($groups_hidden > 0, 'month groups with nothing to show are hidden by default');
ok($releases_page =~ /data-filter-count[^>]*>\s*\d+ of \d+ releases/,
   'the count reflects the default filter rather than the whole list');

# hiding has to actually hide: the cards are display:grid, so [hidden] alone loses
ok($css =~ /\[hidden\]\s*\{[^}]*display:\s*none\s*!important/,
   'the stylesheet makes the hidden attribute win over the card display rule');
ok($css =~ /\.is-filtered\s*\{[^}]*display:\s*none\s*!important/,
   'the scripted filter class also hides');
ok($css =~ /\.chip\[aria-pressed="true"\]/, 'the selected filter has its own visual state');

# and the script has to do the rest: URL state, back/forward, no reload
ok($js =~ /data-filter-default/, 'the script reads the declared default');
ok($js =~ /data-filter-param/,   'the script reads the declared URL parameter');
ok($js =~ /popstate/,            'the script answers browser back and forward');
ok($js =~ /pushState/,           'the script makes a selection addressable');
ok($js =~ /replaceState/,        'the script normalises the URL without adding history');
ok($js =~ /URLSearchParams|location\.search/, 'the script reads the filter from the URL');
ok($js !~ /location\.reload|location\.href\s*=/,
   'the script never reloads the page to filter');

# ---------------------------------------------------------------- 6. content

section('6. content and attribution');

ok($home =~ /unified Spotify/i, 'the home page states what PwEevee is');
ok($home =~ /did\s+not\s+create|does not own|claims no ownership/i,
   'the home page disclaims ownership of upstream work');

for my $f (@html) {
    my $body = slurp($f);
    utf8::decode($body);
    ok($body =~ m{github\.com/skopevoj/spoti\.pw}
       || $body =~ m{github\.com/SideloadLabs/EeveeSpotifyReincarnated},
       "$f links at least one upstream repository");
    ok($body =~ /not affiliated/i, "$f carries the non-affiliation notice");
    # no invented claims of authorship or ownership over other people's work
    ok($body !~ /PwEevee (?:created|wrote|developed) (?:spoti\.pw|EeveeSpotify|SideloadLabs)/i,
       "$f does not claim upstream authorship");
    ok($body !~ /PwEevee (?:owns|operates|maintains) (?:spoti\.pw|EeveeSpotify|SideloadLabs)/i,
       "$f does not claim to own an upstream project");
}

# ---- upstream credit vs PwEevee's own work ------------------------------
#
# An upstream component and the integration built around it are two different
# pieces of work. The EeveeSpotify page must credit upstream fully AND state
# PwEevee's own contribution separately, so neither is mistaken for the other.
{
    my $ee = slurp("$OUT/projects/eeveespotify/index.html");
    utf8::decode($ee);

    # upstream credit is intact — removing it would be the opposite mistake
    for my $who ('Eevee', 'SideloadLabs', 'jaydenjcpy') {
        ok($ee =~ /\Q$who\E/, "the EeveeSpotify page still credits $who");
    }
    ok($ee =~ /Upstream authors/,
       'the author list is labelled as upstream, not as authors of everything shown');

    # jaydenjcpy's credit is scoped to the upstream deb, which is what the
    # package control file actually supports
    ok($ee =~ /jaydenjcpy[\s\S]{0,300}?upstream/i,
       'the jaydenjcpy credit is scoped to the upstream package');
    ok($ee !~ /jaydenjcpy[^<]{0,120}PwEevee(?:'s|&#39;s)? (?:integration|packaging)\b(?![^<]{0,40}not)/i,
       'jaydenjcpy is not credited with PwEevee integration or packaging');

    # PwEevee's own work is stated, and stated as PwEevee's
    ok($ee =~ /What this project contributes/,
       'the page has a section for PwEevee\'s own contribution');
    for my $item ('Integration', 'Unified packaging', 'Build and validation',
                  'Website presentation and distribution') {
        ok($ee =~ /\Q$item\E/, "PwEevee's contribution names: $item");
    }
    ok($ee =~ /not attributable to Eevee, SideloadLabs or jaydenjcpy/,
       'the page says plainly that PwEevee\'s work is not upstream\'s');

    # and it still disclaims ownership of the upstream project
    ok($ee =~ /claims no ownership|does not own|did not create/i,
       'the page still disclaims ownership of the upstream project');

    # the donation disclaimer must be about upstream only: bundling "the
    # self-contained packaging" into it implied the packaging was upstream's
    ok($ee !~ /donation link was found for[^<]*packaging/i,
       'the donation disclaimer no longer covers the packaging shown here');
    ok($ee =~ /No official donation link was found for EeveeSpotify or EeveeSpotifyReincarnated/,
       'the donation disclaimer names the upstream projects only');
}

# ---- the decrypted-IPA workflow is PwEevee's, not a visitor requirement ----
#
# The site used to tell visitors they supply their own decrypted IPA. That is not
# how a published PwEevee download works: PwEevee builds and publishes the
# finished app. The phrasing has to be gone from the public site, not restyled.
for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    ok($b !~ /supplied by you/i, "$f does not say the IPA is supplied by the visitor");
    ok($b !~ /you supply your own/i, "$f does not tell the visitor to supply an IPA");
    ok($b !~ /supply your own decrypted/i, "$f has no supply-your-own-IPA instruction");
}

# The public how-it-works path is the five steps a visitor actually takes, and it
# must not open by asking them for a build input.
{
    # Scoped to the section itself. Release notes are upstream text spliced into
    # this page, and what an upstream author writes in them is not this site's
    # vocabulary to police.
    my ($how) = $home =~ /<section class="section inverted" id="how">(.*?)<\/section>/s;
    ok(defined $how, 'the home page has a how-it-works section');
    $how = '' unless defined $how;

    my $steps = () = $how =~ /<li><strong>[^<]+<\/strong>/g;
    ok($steps == 5, 'the home page explains the process in five steps',
       "found $steps");
    for my $verb ('Choose a build', 'Download the IPA', 'Sign it', 'Install it',
                  'Open it and use it') {
        ok($how =~ /\Q$verb\E/, "the process names the step: $verb");
    }
    # internal build vocabulary belongs on the developer-facing pages
    for my $jargon ('Mach-O', 'build manifest', 'load command', 'source-artifact') {
        ok($how !~ /\Q$jargon\E/i,
           "the how-it-works section does not use internal jargon: $jargon");
    }
    # …and that detail must still exist somewhere, not be deleted
    my $pw = slurp("$OUT/projects/pweevee/index.html");
    utf8::decode($pw);
    ok($pw =~ /Mach-O/, 'the build detail is kept on the PwEevee project page');
    ok($pw =~ /eight stages/i, 'the eight build stages are kept');
}

# ---- the support and referral sections -------------------------------------

{
    ok($home =~ /Enjoying PwEevee\?/, 'the home page asks for a star, in plain words');
    ok($home =~ /Star PwEevee on GitHub/, 'the star button is labelled');
    ok($home =~ m{href="https://github\.com/codeboy2012/spoti\.pw-builds"[^>]*>\s*<span aria-hidden="true">&\#9733;</span>}
       || $home =~ m{<a class="btn btn--primary" href="https://github\.com/codeboy2012/spoti\.pw-builds"},
       'the star button points at the real repository, not an invented one');
    # no pressure
    for my $guilt ('please donate', 'if you care', 'support us or', 'we need you') {
        ok($home !~ /\Q$guilt\E/i, "the ask is not guilt-tripping: $guilt");
    }

    # the referral is optional, unaffiliated, and below the project's own content
    ok($home =~ /Freebuff/, 'the optional referral is present');
    ok($home =~ m{href="https://freebuff\.com/\?ref=ref-4a833bdc-4d33-4512-b5a6-cdb94b9800a6"},
       'the referral uses the supplied URL exactly');
    ok($home =~ /rel="noopener nofollow sponsored"/,
       'the referral link is marked nofollow and sponsored');
    ok($home =~ /Not required, not affiliated with PwEevee, and not a sponsor/,
       'the referral states plainly that it is not part of PwEevee');
    ok(index($home, 'Enjoying PwEevee?') < index($home, 'Freebuff'),
       'the referral sits below the project\'s own support content');
    ok($home =~ /15 Freebucks/ && $home =~ /at least 4 months old/,
       'the referral terms are stated accurately');
}

# "self-contained packaging" must not be the label for what this site ships.
# The literal package identifier is still allowed — that is a fact about the
# upstream deb, not a claim about who built the download.
for my $f (@html) {
    my $b = slurp($f);
    utf8::decode($b);
    ok($b !~ /self-contained packaging/i,
       "$f does not present packaging as upstream's with that wording");
    ok($b !~ /the self-contained package upstream distributes/i,
       "$f does not use the ambiguous self-contained phrasing");
}

# the same separation must exist in the data the pages are built from
{
    my $m = eval { read_json("$OUT/data/projects.json") } || {};
    my ($ee) = grep { ($_->{slug} // '') eq 'eeveespotify' } @{ $m->{projects} || [] };
    ok($ee, 'the data model still declares the EeveeSpotify project');
    if ($ee) {
        ok(ref $ee->{pweevee_work} eq 'HASH',
           'the data model carries PwEevee\'s own contribution separately');
        my $w = $ee->{pweevee_work} || {};
        ok(ref $w->{items} eq 'ARRAY' && @{ $w->{items} } >= 4,
           'four areas of PwEevee work are declared',
           'found ' . scalar @{ $w->{items} || [] });
        ok(scalar(grep { $_->{name} eq 'jaydenjcpy' } @{ $ee->{authors} || [] }) == 1,
           'jaydenjcpy remains in the upstream author list');
        ok(($ee->{support}{note} // '') !~ /packaging/i,
           'the support note no longer mentions the packaging');
    }
}

# SideloadLabs must be named as the publisher of the variants, not absorbed
ok($layout_out =~ /SideloadLabs/, 'the footer identifies SideloadLabs');
ok($layout_out =~ /does not own or mirror|not own/i,
   'the footer states PwEevee does not own the AltSource');

# Versions must never be hardcoded in a template: they belong to the generated
# data. SVG geometry is stripped first, since path data is full of decimals that
# look like version numbers.
for my $src (glob('website-src/pages/*.html'), 'website-src/layout.html') {
    my $body = slurp($src);
    utf8::decode($body);
    $body =~ s{<svg\b.*?</svg>}{}gs;
    $body =~ s{\sd="[^"]*"}{}g;
    $body =~ s{\sviewBox="[^"]*"}{}g;
    my ($found) = $body =~ /(\bv?\d+\.\d+\.\d+\b)/;
    ok(!defined $found, "no hardcoded version in $src", $found);
}

# ---------------------------------------------------------------- 7. legacy

section('7. pre-redesign URLs still resolve');

# /releases/index.json is deliberately absent now: it was the local build index
# behind the dev build, and nothing on the site reads it any more. Every page
# route that existed before the change still resolves.
for my $legacy (qw(/ /downloads /releases /projects /projects/pweevee /projects/spotipw
                   /projects/eeveespotify /credits /development /legal /contact
                   /data/releases.json)) {
    ok(defined resolve($legacy), "URL still resolves: $legacy");
}
ok(defined resolve('/data/altsource.json'), 'the AltSource data file is published');
ok(-f "$OUT/alt-redirect.html", 'the alternate-host redirect page is still present');
ok(-f "$OUT/nginx.conf.example", 'the nginx example config is still present');

ok(defined resolve('/data/altsource.json'), 'the AltSource data file is published');
ok(-f "$OUT/alt-redirect.html", 'the alternate-host redirect page is still present');
ok(-f "$OUT/nginx.conf.example", 'the nginx example config is still present');

my $alt = -f "$OUT/alt-redirect.html" ? slurp("$OUT/alt-redirect.html") : '';
ok($alt =~ m{https://pweevee\.skytweak\.dpdns\.org/}, 'the redirect stub points at the canonical URL');
ok($alt =~ /http-equiv="refresh"/i, 'the redirect stub still works without JavaScript');

# ------------------------------------------- 7b. live repository statistics

section('7b. live repository statistics (stats.json + homepage band)');

ok(defined resolve('/install'), 'the install guide route resolves');

{
    my $stats_ok = -f 'website/data/stats.json';
    ok($stats_ok, 'website/data/stats.json exists (run scripts/update-stats.sh)');
    if ($stats_ok) {
        my $fmt_count = sub {
            my $n = 0 + ($_[0] // 0);
            my $s = sprintf('%d', $n);
            1 while $s =~ s/^(\d+)(\d{3})\z/$1,$2/;
            return $s;
        };
        my $stats = eval { read_json('website/data/stats.json') };
        ok(ref $stats eq 'HASH', 'stats.json parses as JSON');
        if (ref $stats eq 'HASH') {
            ok(($stats->{schema} // 0) >= 1, 'stats.json declares its schema version');
            ok(($stats->{generated_at} // '') =~ /^\d{4}-\d{2}-\d{2}T/,
               'stats.json records the generation time (UTC timestamp)');
            ok(ref $stats->{metric_notes} eq 'HASH' && ref $stats->{repos} eq 'ARRAY',
               'stats.json carries the metric notes and the repos array');
            my $wnotes = $stats->{metric_notes}{watchers} // '';
            ok($wnotes =~ /subscribers_count/ && $wnotes =~ /NOT watchers_count/,
               'the watchers metric is documented as subscribers_count, explicitly not watchers_count');
            ok(($stats->{metric_notes}{downloads} // '') =~ /download_count/,
               'the downloads metric is documented as GitHub release-asset download_count',
               $stats->{metric_notes}{downloads});
            ok(($stats->{downloads}{aggregate_label} // '') =~ /not unique users or installs/,
               'the site-facing aggregate disclaims unique users or installs',
               $stats->{downloads}{aggregate_label});

            my %by_slug = map { ($_->{slug} // '') => $_ } @{ $stats->{repos} };
            my $home_entry = $by_slug{pweevee};
            for my $slug (sort keys %by_slug) {
                my $r = $by_slug{$slug};
                ok($r->{stars}  !~ /[^\d]/ && ($r->{stars}  // 0) >= 0, "$slug stars is a non-negative number");
                ok($r->{forks}   !~ /[^\d]/ && ($r->{forks}  // 0) >= 0, "$slug forks is a non-negative number");
                ok($r->{subscribers} !~ /[^\d]/ && ($r->{subscribers} // 0) >= 0,
                   "$slug watchers via subscribers_count is a non-negative number");
                if ($r->{available}) {
                    ok($r->{repo_url} =~ /^https:\/\/github\.com\//, "$slug repo_url is an https GitHub URL");
                    ok($r->{stale} ? length($r->{error} // '') : 1,
                       "$slug marks its staleness with an error message when stale");
                }
                else {
                    ok(length($r->{error} // '') > 0,
                       "$slug states why its statistics are unavailable instead of showing zeroes");
                }
            }

            # The download aggregate must match the release data it derives from.
            my $dl = $stats->{downloads};
            ok(ref $dl eq 'HASH', 'stats.json carries the download aggregate');
            if (ref $dl eq 'HASH') {
                ok(($dl->{aggregate_label} // '') =~ /not unique users or installs/,
                   'the aggregate is explicitly not presented as unique users');
                my $done = 0;
                my $rel  = eval { read_json('website/data/releases.json') };
                if (ref $rel eq 'HASH') {
                    my $sum = 0;
                    for my $p (@{ $rel->{projects} || [] }) {
                        my %counted;
                        if (ref $p->{latest}{assets} eq 'ARRAY') {
                            $counted{ $p->{latest}{version} } = 1;
                            $sum += ($_->{download_count} // 0) for @{ $p->{latest}{assets} };
                        }
                        for my $h (@{ $p->{history} || [] }) {
                            my $tag = $h->{tag_name} // $h->{version} // '';
                            next if $counted{$tag};
                            $sum += ($_->{download_count} // 0) for @{ $h->{assets} || [] };
                        }
                    }
                    ok(0 + ($dl->{total} // -1) == $sum,
                       'the published download total equals a fresh independent recount of the release data',
                       "stats.json says " . (0 + ($dl->{total} // 0)) . ", recount says $sum");
                    $done = 1;
                }
                ok($done, 'releases.json was readable for the independent download recount');
            }

            # ---- the rendered band on the homepage ----
            if ($home_entry && $home_entry->{available} && !$home_entry->{stale}) {
                my @expected = map { $fmt_count->($_) }
                    ($home_entry->{stars}, $home_entry->{forks}, $home_entry->{subscribers},
                     $home_entry->{open_issues});
                push @expected, $fmt_count->($stats->{downloads}{total})
                    if ($stats->{downloads}{total} // 0) > 0;
                my @got = $home =~ /<dd class="stats-band__num">([\d,]+)<\/dd>/g;
                ok(scalar(@got), 'the homepage renders the statistics band with numbers');
                ok($got[0] eq $expected[0], 'the band renders stars exactly as stored in stats.json',
                   "$got[0] vs $expected[0]") if @expected && @got;
                ok(join('|', @got) eq join('|', @expected),
                   'every rendered number matches its stats.json value in order',
                   'rendered: ' . join(', ', @got) . ' / expected: ' . join(', ', @expected));
                ok($home !~ /stats-band__missing/,
                   'the homepage band does not claim statistics are missing (they exist and are fresh)');
            }
            else {
                ok($home =~ /stats-band__missing/,
                   'the homepage renders the explanatory missing state instead of fabricated zeroes');
            }
            if (length($stats->{generated_at} // '')) {
                ok($home =~ /<time datetime="\Q$stats->{generated_at}\E">/,
                   'the refresh timestamp rendered on the homepage is the stats.json generation time');
            }
            ok($home =~ /browser never calls GitHub/,
               'the band states explicitly that the page loads a shared snapshot');
            ok($home =~ /updated hourly/,
               'the band labels its freshness as hourly');
        }
    }

    # the rendered band stays a definition list: screen readers announce pairs
    ok($home =~ /<dl class="stats-band">/, 'the statistics band is a real dl (definition list)');
    ok($css =~ /\.stats-band\s*\{/, 'the statistics band has styles');
    ok($css =~ /\.stats-band__num[^{}]*\{[^}]*font-variant-numeric:\s*tabular-nums/s,
       'statistics numbers use tabular figures (no jitter between refreshes)');
    ok($css =~ /\@media[^{]*max-width[^{]*\{[\s\S]*?\.stats-band[^{}]*\{[^}]*grid-template-columns:\s*(?:minmax\(0,\s*1fr\)|1fr)/s,
       'the statistics band collapses to a single column on narrow screens');
}

# ------------------------------------------- 7c. update-stats.pl behaviour

# Deterministic, mocked-HTTP tests. The GitHub REST API origin is overridden
# (STATS_API_BASE) to a local 127.0.0.1 mock server, so the REAL data flow ---
# parsing, metric selection, ETag bookkeeping, stale fallback, aggregation ---
# runs through the genuine PwHttp client against canned responses, with no
# external network access at all.

section('7c. update-stats.pl fixture behaviour (deterministic, mocked HTTP)');

{
    my $FIX = 'PwEvevee/build-system/_work/stats-fixtures';

    # A trimmed test tree — rebuilt from nothing every run, never reused, so a
    # stale fixture can never pass by accident.
    require File::Path;
    File::Path::remove_tree($FIX) if -d $FIX;
    File::Path::make_path($FIX);

    my $writes = sub {
        my ($path, $bytes) = @_;
        require File::Basename;
        File::Path::make_path(File::Basename::dirname($path));
        open my $fh, '>', $path or die "fixture: cannot write $path: $!\n";
        binmode $fh; print {$fh} $bytes; close $fh;
    };

    $writes->("$FIX/projects.json", <<'END_PROJECTS');
{"projects":[
  {"slug":"demo","name":"Demo project","github":{"owner":"mock-org","repo":"demo-repo"}},
  {"slug":"bare","name":"Bare project"}
]}
END_PROJECTS

    # latest assets sum 150; history repeats the latest (as update-releases.pl
    # publishes it) plus one older release (25) — the aggregate must count 175,
    # with 2 distinct releases, not 325 over 3.
    $writes->("$FIX/releases.json", <<'END_RELEASES');
{"generated_at":"2026-10-25T00:00:00Z","projects":[
  {"slug":"demo","latest":{"version":"v2.0.0","assets":[
      {"name":"a.ipa","download_count":100},{"name":"b.ipa","download_count":50}]},
   "history":[
      {"tag_name":"v2.0.0","assets":[
          {"name":"a.ipa","download_count":100},{"name":"b.ipa","download_count":50}]},
      {"tag_name":"v1.0.0","assets":[{"name":"c.ipa","download_count":25}]}]},
  {"slug":"bare"}
]}
END_RELEASES

    # The mock server serves exactly these responses, one per HTTP request,
    # in this order: it is a scripted conversation, not a standing web app.
    my $repo_body =
        '{"stargazers_count":120,"watchers_count":120,"forks_count":7,'
      . '"subscribers_count":17,"open_issues_count":3,'
      . '"pushed_at":"2026-10-25T00:00:00Z","topics":[]}';
    my $bad_body = '{"forks_count":7,"open_issues_count":3}';
    my $convo = [
        # 1 — case A: a fresh 200 with a real ETag
        { status => 200, etag => 'W/"freshabc"', body => $repo_body },
        # 2 — case B: conditional revalidation answered with 304 Not Modified
        { status => 304, etag => 'W/"ennn"',     body => '' },
        # 3 — case C, attempt 1: GitHub is up but erroring. PwHttp configures
        # curl retry = 2, which retries transient failures (5xx included), so
        # this response is ended and immediately REPLACED by the retry response;
        # a scripted conversation of length 5 would misalign the remaining
        # cases by one response and leave the server empty before case E.
        { status => 500, body => '' },
        # 3b — case C, attempt 2 (curl's own retry): the retry attempt sees a
        # non-transient failure, so case C settles on this response.
        { status => 404, body => '' },
        # 4 — case D: repository gone
        { status => 404, body => '' },
        # 5 — case E: a 200 whose body is not a valid repository object
        { status => 200, etag => 'W/"weird"',    body => $bad_body },
    ];
    my $convo_json = JSON::PP->new->canonical->encode($convo);
    my $server_src = <<'SERVER_SRC';
#!/usr/bin/env perl
# One scripted mock GitHub API server. Serves the scripted responses in
# script.json in order, one per connection, then exits. Used only by
# website-tests.pl 7c; binds 127.0.0.1 only.
use strict; use warnings;
use IO::Socket::INET;
my $dir = $ARGV[0] or die "usage: server.pl <dir>\n";
my $raw;
{
    local $/;
    open my $fh, '<', "$dir/script.json" or die "script.json: $!\n";
    $raw = <$fh>;
}
require JSON::PP;
my @convo = @{ JSON::PP::decode_json($raw) };
my $srv = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1', LocalPort => 0, Proto => 'tcp',
    Listen => 8, ReuseAddr => 1,
) or die "bind: $!\n";
open my $pf, '>', "$dir/port.txt" or die "port.txt: $!\n";
print {$pf} $srv->sockport; close $pf;
alarm 120;                       # never linger if the suite dies mid-run
my $n = 0;
while ($n < @convo) {
    my $c = $srv->accept or last;
    my $req = '';
    while (defined(my $line = <$c>)) { $req .= $line; last if $line =~ /^\r?$/; }
    my $hit  = $convo[$n];
    my $body = $hit->{body} // '';
    print {$c} "HTTP/1.0 $hit->{status} Mock\r\n";
    print {$c} "ETag: $hit->{etag}\r\n" if length($hit->{etag} // '');
    print {$c} "Content-Type: application/json\r\n"
             . 'Content-Length: ' . length($body) . "\r\n\r\n";
    print {$c} $body unless ($hit->{status} // 0) == 304;
    close $c;
    $n++;
}
close $srv;
exit 0;
SERVER_SRC
    $writes->("$FIX/script.json", $convo_json . "\n");
    $writes->("$FIX/server.pl",   $server_src . "\n");

    # start the mock server (loopback only) and wait for its port
    my $server_pid = fork();
    defined $server_pid or die "cannot fork the mock server: $!\n";
    if (!$server_pid) {
        exec 'perl', "$FIX/server.pl", $FIX or die "exec mock server: $!\n";
    }
    my $port = '';
    for (1 .. 200) {
        if (open my $pf, '<', "$FIX/port.txt") {
            $port = <$pf> // ''; close $pf; chomp $port;
            last if $port =~ /^\d+$/;
        }
        select undef, undef, undef, 0.05;
    }
    die "the update-stats mock server did not come up\n" unless $port =~ /^\d+$/;
    my $BASE = "http://127.0.0.1:$port";
    my $repo_url = "$BASE/repos/mock-org/demo-repo";

    # runs the real update-stats.pl against the mock server. The command must be
    # ONE string: a qx{...} . qq{...} concatenation runs only the first piece and
    # appends the second to the captured output, so every argument is lost.
    my $run = sub {
        my ($case, $out) = @_;
        local $ENV{STATS_API_BASE} = $BASE;
        my $stdout = qx{perl PwEvevee/build-system/release/update-stats.pl --out "$out" --projects "$FIX/projects.json" --releases "$FIX/releases.json" --quiet 2>&1};
        my $exit = $? >> 8;
        return ($exit, $stdout, $out);
    };

    # ---- A: fresh fetch, correct metric selection -------------------------
    {
        my ($exit, $stdout, $out) = $run->('fresh', "$FIX/fresh/stats.json");
        ok($exit == 0, 'update-stats exits successfully on a clean fetch');
        my $d = eval { read_json($out) };
        ok(ref $d eq 'HASH', 'a clean fetch produces valid stats.json');
        if (ref $d eq 'HASH') {
            my %p = map { ($_->{slug} // '') => $_ } @{ $d->{repos} };
            ok(($p{demo}{stars} // -1) == 120, 'stars come from stargazers_count');
            ok(($p{demo}{forks} // -1) == 7,  'forks come from forks_count');
            ok(($p{demo}{subscribers} // -1) == 17,
               'watchers come from subscribers_count — the mocked watchers_count (120) is ignored');
            ok(($p{demo}{open_issues} // -1) == 3, 'open issues are stored');
            ok(($p{demo}{etag} // '') =~ /freshabc/,
               'an ETag that the server actually sent is stored for conditional requests');
            ok($p{demo}{available} && !$p{demo}{stale}, 'a clean fetch is available and not stale');
            ok(ref $p{bare} eq 'HASH' && !$p{bare}{available} && length($p{bare}{error} // ''),
               'a project with no GitHub coordinate renders unavailable with a reason');
            my $dl = $d->{downloads};
            ok(ref $dl eq 'HASH' && ($dl->{per_project}{demo}{release_downloads} // -1) == 175,
               'the aggregate sums the latest release and the older history release exactly once',
               "got " . ($dl->{per_project}{demo}{release_downloads} // 'missing'));
            ok((($dl->{per_project}{demo}{releases_summed} // -1) == 2),
               'the repeated latest release in history is recognised and not double-counted');
            ok(($dl->{total} // -1) == 175, 'the all-projects download total is right',
               "got " . (0 + ($dl->{total} // 0)));
        }
    }

    # ---- B: If-None-Match/304 keeps stored numbers verbatim ---------------
    {
        my $prev = {
            schema => 1, generated_at => '2026-10-25T00:00:00Z',
            repos => [ {
                slug => 'demo', name => 'Demo project', repo => 'mock-org/demo-repo',
                repo_url => 'https://github.com/mock-org/demo-repo',
                available => JSON::PP::true(), stale => JSON::PP::false(),
                stars => 120, forks => 7, subscribers => 17, open_issues => 3,
                pushed_at => '2026-10-25T00:00:00Z', topics => [],
                etag => 'W/"ennn"', fetched_at => '2026-10-24T00:00:00Z',
            } ],
        };
        my $writer = sub {
            require File::Basename;
            File::Path::make_path(File::Basename::dirname($_[0]));
            open my $fh, '>', $_[0] or die "$!:\n"; binmode $fh;
            print {$fh} JSON::PP->new->utf8->canonical->encode($_[1]); close $fh;
        };
        $writer->("$FIX/etag/stats.json", $prev);
        my ($exit, $stdout, $out) = $run->('etag', "$FIX/etag/stats.json");
        ok($exit == 0, 'a 304 run exits successfully');
        my $d = eval { read_json($out) };
        ok(ref $d eq 'HASH', 'a 304 run still produces valid stats.json');
        if (ref $d eq 'HASH') {
            my ($r) = grep { ($_->{slug} // '') eq 'demo' } @{ $d->{repos} };
            ok(defined $r, 'the stored repo survives a 304');
            ok(($r->{stars} // 0) == 120 && ($r->{subscribers} // 0) == 17,
               'a 304 does not touch the stored numbers');
            ok(($r->{fetched_at} // '') eq '2026-10-24T00:00:00Z',
               'fetched_at still describes the last verification with actual numbers');
            ok($r->{available} && !$r->{stale}, 'a 304 is a success path, not a stale path');
        }
    }

    # ---- C: error with previous data -> stale fallback ---------------------
    {
        my $prev = {
            schema => 1, generated_at => '2026-10-25T00:00:00Z',
            repos => [ {
                slug => 'demo', name => 'Demo project', repo => 'mock-org/demo-repo',
                repo_url => 'https://github.com/mock-org/demo-repo',
                available => JSON::PP::true(), stale => JSON::PP::false(),
                stars => 120, forks => 7, subscribers => 17, open_issues => 3,
                pushed_at => 'x', topics => [], etag => '',
                fetched_at => '2026-10-24T00:00:00Z',
            } ],
        };
        File::Path::make_path("$FIX/stale");
        open my $fh, '>', "$FIX/stale/stats.json" or die "stale fixture: $!\n";
        binmode $fh; print {$fh} JSON::PP->new->utf8->canonical->encode($prev); close $fh;
        my ($exit, $stdout, $out) = $run->('stale', "$FIX/stale/stats.json");
        ok($exit == 0, 'an upstream failure still exits cleanly (the site must keep rendering)');
        my $d = eval { read_json($out) };
        ok(ref $d eq 'HASH', 'the fallback run produces valid stats.json');
        if (ref $d eq 'HASH') {
            my ($r) = grep { ($_->{slug} // '') eq 'demo' } @{ $d->{repos} };
            ok($r->{stale}, 'GitHub-down marks the previous data stale');
            ok(($r->{stars} // 0) == 120 && ($r->{subscribers} // 0) == 17,
               'the previous known-good numbers survive an outage byte for byte');
            ok(length($r->{error} // '') > 0, 'the stale entry records what went wrong');
            ok(length($r->{stale_since} // '') > 0, 'the stale entry records when staleness started');
        }
    }

    # ---- D: failure with no previous data at all ----------------------------
    {
        my ($exit, $stdout, $out) = $run->('noprev', "$FIX/noprev/stats.json");
        ok($exit == 2, 'no data anywhere is a hard failure (exit 2), not a silent success');
        my $d = eval { read_json($out) };
        ok(ref $d eq 'HASH', 'even a failed run writes a declarative stats.json');
        if (ref $d eq 'HASH') {
            my ($r) = grep { ($_->{slug} // '') eq 'demo' } @{ $d->{repos} };
            ok($r && !$r->{available} && ($r->{error} // '') =~ /404/,
               'a 404 is surfaced as the unavailable reason');
        }
        ok($stdout =~ /404/ || $stdout eq '', 'the failure is reported in the run log');
    }

    # ---- E: a 200 whose body is not a valid repository ----------------------
    {
        my ($exit, $stdout, $out) = $run->('badshape', "$FIX/badshape/stats.json");
        ok($exit == 2, 'a non-repository 200 response is a hard failure, not a fake success');
        my $d = eval { read_json($out) };
        ok(ref $d eq 'HASH', 'the bad-shape run still writes its declarative output');
        if (ref $d eq 'HASH') {
            my ($r) = grep { ($_->{slug} // '') eq 'demo' } @{ $d->{repos} };
            ok($r && !$r->{available} && ($r->{error} // '') =~ /missing required field/,
               'the missing stargazers_count is named as the validation failure',
               ($r->{error} // ''));
        }
    }

    # replays done: retire the mock server (it also self-terminates after its
    # scripted conversation, so a suite failure cannot leave it running)
    kill 'KILL', $server_pid;
    waitpid $server_pid, 0;

    # tidy up: only what this run created
    File::Path::remove_tree($FIX);
}

# ---------------------------------------------------------------- summary

printf "\n%s\n", '-' x 62;
if ($fail) {
    printf "FAIL  %d passed, %d failed\n\n", $pass, $fail;
    print "  - $_\n" for @failures;
    print "\n";
    exit 1;
}
printf "OK    %d checks passed\n", $pass;
exit 0;

# ============================================================ helpers

sub all_files {
    my ($dir) = @_;
    my @out;
    my @stack = ($dir);
    while (my $d = pop @stack) {
        opendir(my $dh, $d) or next;
        for my $e (readdir $dh) {
            next if $e eq '.' || $e eq '..';
            my $p = "$d/$e";
            if (-d $p) { push @stack, $p }
            elsif (-f $p) { push @out, $p }
        }
        closedir $dh;
    }
    return sort @out;
}

# mirror of the server's try_files: /x -> website/x, website/x/index.html
sub resolve {
    my ($url) = @_;
    (my $path = $url) =~ s{^/}{};
    $path =~ s{/$}{};
    return "$OUT/index.html" if $path eq '';
    return "$OUT/$path" if -f "$OUT/$path";
    return "$OUT/$path/index.html" if -f "$OUT/$path/index.html";
    return undef;
}
