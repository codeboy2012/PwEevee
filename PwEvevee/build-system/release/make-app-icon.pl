#!/usr/bin/env perl
# ============================================================================
# make-app-icon.pl — the ORIGINAL PwEevee brand artwork, procedurally drawn
# ============================================================================
#
# This script GENERATES the official PwEevee brand artwork:
#
#     website/assets/brand/pweevee.png      (and the pweevee-<size>.png set,
#     website/assets/brand/pweevee-1024.png  with pweevee-1024.png also read
#                                             by make-brand-assets.pl to
#                                             derive the favicon-size icons)
#
# The renderer prefers the bare "pweevee.png" name for brand slots, so running
# this refreshes the official mark. A separate file, pweevee-app-icon.png, is
# the Spotify-derived artwork that HONESTLY DEPICTS the app icon inside the
# shipped IPA; it is third-party depiction and is never a brand source.
#
#   perl PwEvevee/build-system/release/make-app-icon.pl            # all sizes
#   perl PwEvevee/build-system/release/make-app-icon.pl --preview  # fast 96px look-dev
#
# Original artwork, not derived from any upstream project's icon.
#
# THE SYMBOL — "the resolved stream":
#
# Two flow-lines enter from the left (the two upstream components), interlock
# through a hexagonal node — six facets: build, validate, package, sign,
# publish, host — and leave to the right as one bright line: many components
# resolved into a single shipped build. The node's vertical stroke reads as a
# subtle "P"; the two entering ribbons suggest a soft "E" without ever drawing
# letters. At 16px the silhouette collapses to a rounded square with one bright
# horizontal gesture — still unmistakably PwEevee.
#
# THE MATERIAL — dark glass slab on an integrated near-black ground:
# deep midnight-blue body with a vertical depth gradient, electric-blue rim
# light on the top-left edge, one restrained crimson accent on the lower-right
# (the site's accent at icon scale), internal blue bloom behind the symbol,
# a soft top gloss and a sharp specular tick, Apple-style generous padding.
#
# The icon carries its dark background inside the artwork (per the brief); the
# corner pixels are transparent so it sits correctly on any browser chrome.
#
# Pure core Perl. Anti-aliasing is analytic (signed-distance functions with
# smooth coverage), painted at 2x supersample and box-filtered down.
# ============================================================================
use strict;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/lib";
use Compress::Zlib qw(compress crc32);
use PwSite qw(repo_root spew);

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $preview = grep { /^--preview$/ } @ARGV;

# ----------------------------------------------------------------------------
# palette — the site's own colors
# ----------------------------------------------------------------------------
my %C = (
    ground_hi => [0x0a, 0x12, 0x28],   # midnight navy, upper canvas
    ground_lo => [0x03, 0x05, 0x0c],   # near-black, lower canvas
    body_hi   => [0x14, 0x2c, 0x68],   # slab body, lit upper face
    body_lo   => [0x06, 0x0f, 0x2e],   # slab body, deep lower face
    glow      => [0x2f, 0x7d, 0xff],   # electric blue (key light)
    glow_hi   => [0x62, 0xa8, 0xff],   # hot electric blue (symbol)
    rim       => [0xa9, 0xcf, 0xff],   # rim light, cold sky
    ink       => [0xe6, 0xf2, 0xff],   # symbol ink
    crimson   => [0xe5, 0x20, 0x3f],   # the single red accent
);

my $S          = $preview ? 96 : 1024;
my $PREVIEW_SS = $preview ? 1 : 2;

my $RADIUS_FRAC = 0.2250;   # corner radius of the icon silhouette
my $EDGE_FRAC   = 0.0100;   # rim-light band thickness (in unit space)

my $SS  = $S * $PREVIEW_SS;
my @buf = (0) x ($SS * $SS * 4);

# ---- sdf primitives (all: negative = inside) --------------------------------

sub sd_round_rect {
    # iq's canonical rounded-box SDF: b = half-size, r = corner radius
    my ($px, $py, $cx, $cy, $bx, $by, $r) = @_;
    my $qx = abs($px - $cx) - $bx + $r;
    my $qy = abs($py - $cy) - $by + $r;
    my $mx = $qx > $qy ? $qx : $qy;
    my $m  = $mx < 0 ? $mx : 0;
    my $ax = $qx > 0 ? $qx : 0;
    my $ay = $qy > 0 ? $qy : 0;
    return $m + sqrt($ax * $ax + $ay * $ay) - $r;
}

sub sd_hex {
    # iq's canonical flat-top hexagon SDF (points left/right), negative inside.
    # r is the circumradius (the horizontal half-width), apothem = r*sqrt(3)/2.
    # The old hand-rolled "max over three face planes" was NOT a valid SDF:
    # points far above/below the shape evaluated negative ("inside"), which
    # extruded the node into a full-height beam and rendered the bottom as
    # a spade/arrowhead.
    my ($px, $py, $cx, $cy, $r) = @_;
    $px = abs($px - $cx); $py = abs($py - $cy);
    my $a  = $r * 0.8660254038;             # apothem
    my $dot = -0.8660254038 * $px + 0.5 * $py;   # k.xy . p,  k = (-0.866, 0.5)
    if ($dot < 0) {                         # p -= 2*min(dot,0)*k.xy
        $px += 1.7320508076 * $dot;
        $py -= $dot;
    }
    my $cz = 0.5773502692 * $a;
    my $cl = $px > $cz ? $cz : $px;
    $px -= $cl;
    $py -= $a;
    my $len = sqrt($px * $px + $py * $py);
    return $py > 0 ? $len : -$len;
}

# ---- painting ----------------------------------------------------------------

sub coverage {
    my ($d, $soft) = @_;
    $soft = 0.0015 unless defined $soft;
    my $a = 0.5 - $d / (2 * $soft);
    return 0 if $a <= 0;
    return 1 if $a >= 1;
    return $a;
}

sub px {   # unit-space coords, alpha over
    my ($x, $y, $r, $g, $b, $a) = @_;
    return if $a <= 0;
    $a = 1 if $a > 1;
    my $ix = int($x * $SS); my $iy = int($y * $SS);
    return if $ix < 0 || $ix >= $SS || $iy < 0 || $iy >= $SS;
    my $i = ($iy * $SS + $ix) * 4;
    $buf[$i]     += ($r - $buf[$i])     * $a;
    $buf[$i + 1] += ($g - $buf[$i + 1]) * $a;
    $buf[$i + 2] += ($b - $buf[$i + 2]) * $a;
    $buf[$i + 3] += (1 - $buf[$i + 3]) * $a;
}

sub light {   # additive on already-opaque pixels
    my ($x, $y, $r, $g, $b, $e) = @_;
    my $ix = int($x * $SS); my $iy = int($y * $SS);
    return if $ix < 0 || $ix >= $SS || $iy < 0 || $iy >= $SS;
    my $i = ($iy * $SS + $ix) * 4;
    return if $buf[$i + 3] <= 0.02;
    $buf[$i]     += ($r - $buf[$i])     * $e;
    $buf[$i + 1] += ($g - $buf[$i + 1]) * $e;
    $buf[$i + 2] += ($b - $buf[$i + 2]) * $e;
}

# ============================================================================

sub paint {
    my $slab_d = [];   # sd to the rounded-square silhouette per pixel (shared)

    # ---- 1. ground (fills the rounded square) -------------------------------
    for my $iy (0 .. $SS - 1) {
        my $y = ($iy + 0.5) / $SS;
        my $t = $y ** 1.15;
        my $r = $C{ground_lo}[0] + ($C{ground_hi}[0] - $C{ground_lo}[0]) * (1 - $t);
        my $g = $C{ground_lo}[1] + ($C{ground_hi}[1] - $C{ground_lo}[1]) * (1 - $t);
        my $b = $C{ground_lo}[2] + ($C{ground_hi}[2] - $C{ground_lo}[2]) * (1 - $t);
        for my $ix (0 .. $SS - 1) {
            my $i = ($iy * $SS + $ix) * 4;
            $buf[$i] = $r; $buf[$i + 1] = $g; $buf[$i + 2] = $b; $buf[$i + 3] = 1;
        }
    }

    # ---- 2. slab mask + interior --------------------------------------------
    # everything below is masked to the rounded square, computed per pixel
    $slab_d = [];   # signed distance to the slab silhouette, per pixel
    for my $iy (0 .. $SS - 1) {
        my $y = ($iy + 0.5) / $SS;
        for my $ix (0 .. $SS - 1) {
            my $x = ($ix + 0.5) / $SS;
            $slab_d->[ $iy * $SS + $ix ] = sd_round_rect($x, $y, 0.5, 0.5, 0.5, 0.5, $RADIUS_FRAC);
        }
    }

    for my $iy (0 .. $SS - 1) {
        my $y = ($iy + 0.5) / $SS;
        for my $ix (0 .. $SS - 1) {
            my $x = ($ix + 0.5) / $SS;
            my $d = $slab_d->[ $iy * $SS + $ix ];
            # sd_round_rect is NEGATIVE inside — coverage(d) is the inside mask.
            # The old coverage(-$d) inverted it and blanked the whole interior.
            my $cov = coverage($d, 0.0016);
            next unless $cov > 0;

            my $i = ($iy * $SS + $ix) * 4;
            next if $d > -$EDGE_FRAC * 1.8;   # interior only: rim band painted separately
            my $t = clamp(($y - 0.04) / 0.92, 0, 1);
            my $r = $C{body_hi}[0] + ($C{body_lo}[0] - $C{body_hi}[0]) * $t;
            my $g = $C{body_hi}[1] + ($C{body_lo}[1] - $C{body_hi}[1]) * $t;
            my $b = $C{body_hi}[2] + ($C{body_lo}[2] - $C{body_hi}[2]) * $t;

            # key light from the upper-left
            my $key = clamp(1 - (sd_seg($x, $y, 0.04, 0.04, 0.66, 0.52) / 0.9), 0, 1) ** 2.2;
            $r += @{$C{glow}}[0] * 0.06 * $key;
            $g += @{$C{glow}}[1] * 0.06 * $key;
            $b += @{$C{glow}}[2] * 0.085 * $key;

            # inner bloom behind the symbol
            my $ig = clamp(1 - sqrt(($x - 0.5) ** 2 + ($y - 0.46) ** 2) / 0.5, 0, 1) ** 2.2;
            $r += @{$C{glow}}[0] * 0.11 * $ig;
            $g += @{$C{glow}}[1] * 0.11 * $ig;
            $b += @{$C{glow}}[2] * 0.13 * $ig;

            # ---- rim light band ------------------------------------------
            my $rim = clamp(1 - abs($d + $EDGE_FRAC) / ($EDGE_FRAC * 1.7), 0, 1);
            if ($rim > 0) {
                my $along = clamp((($x - 0.1) + ($y - 0.1)) / 1.55, 0, 1);
                my $warm = smoothstep(0.66, 0.96, $along);
                my $str = 0.75 * (1 - $warm * 0.2);
                my $rr = $C{rim}[0] + ($C{crimson}[0] - $C{rim}[0]) * $warm;
                my $rg = $C{rim}[1] + ($C{crimson}[1] - $C{rim}[1]) * $warm;
                my $rb = $C{rim}[2] + ($C{crimson}[2] - $C{rim}[2]) * $warm;
                $r += ($rr - $r) * $rim * $str;
                $g += ($rg - $g) * $rim * $str;
                $b += ($rb - $b) * $rim * $str;
            }

            # inner bottom shadow grounds the slab
            my $bot = clamp((0.985 - $y) / 0.12, 0, 1);
            $r *= 0.8 + 0.2 * $bot;
            $g *= 0.8 + 0.2 * $bot;
            $b *= 0.8 + 0.2 * $bot;

            # top gloss sheen
            my $gloss = clamp((0.36 - $y) / 0.36, 0, 1) ** 1.7;
            my $gfade = $gloss * 0.13;
            $r += (255 - $r) * $gfade * 0.32;
            $g += (255 - $g) * $gfade * 0.38;
            $b += (255 - $b) * $gfade * 0.46;

            # specular tick on the upper-left
            {
                my $sx = ($x - 0.205) / 0.105;
                my $sy = ($y - 0.125) / 0.038;
                my $sd = sqrt($sx * $sx + $sy * $sy);
                if ($sd < 1) {
                    my $sp = (1 - $sd) ** 2 * 0.8;
                    $r += (255 - $r) * $sp;
                    $g += (255 - $g) * $sp;
                    $b += (255 - $b) * $sp;
                }
            }

            $buf[$i]     += ($r - $buf[$i])     * $cov;
            $buf[$i + 1] += ($g - $buf[$i + 1]) * $cov;
            $buf[$i + 2] += ($b - $buf[$i + 2]) * $cov;
        }
    }

    # ---- 3. transparent corners: alpha follows the slab silhouette -----------
    # (applied again after the symbol so anti-aliased symbol edges cannot
    # re-opaque a transparent corner)

    # ---- 4. the symbol (masked to inside the slab) ---------------------------
    symbol($slab_d);

    # ---- 5. closing bloom ----------------------------------------------------
    aura(0.52, 0.45, 0.26, @{$C{glow_hi}}, 0.08);

    # ---- 6. re-apply the silhouette: symbol AA must not reopen corners ------
    my $apply_silhouette = sub {
        for my $iy (0 .. $SS - 1) {
            for my $ix (0 .. $SS - 1) {
                my $i = ($iy * $SS + $ix) * 4;
                my $d = $slab_d->[ $iy * $SS + $ix ];
                my $edge = coverage($d + 0.0005, 0.0022);   # 1 inside, 0 outside (see interior note)
                if ($edge < 1) {
                    $buf[$i + 3] *= $edge;
                    $buf[$i]     *= $edge;
                    $buf[$i + 1] *= $edge;
                    $buf[$i + 2] *= $edge;
                }
            }
        }
    };

    $apply_silhouette->();

    # ---- 5b. closing bloom AFTER masking (light only lands on lit pixels) ---
    aura(0.52, 0.45, 0.26, @{$C{glow_hi}}, 0.08);

    $apply_silhouette->();
}

sub symbol {
    my ($slab_d) = @_;

    my ($nx, $ny, $nr) = (0.545, 0.470, 0.150);

    # ---- inlets: two ribbons converging into the node's left facet ----------
    my @inlets = (
        [0.145, 0.315, 0.285, 0.300, 0.418, 0.415],
        [0.145, 0.625, 0.285, 0.610, 0.418, 0.525],
    );
    ribbon(@$_, 0.030, 0.019) for @inlets;

    # ---- the node (hexagon) --------------------------------------------------
    for my $iy (0 .. $SS - 1) {
        for my $ix (0 .. $SS - 1) {
            my $i = ($iy * $SS + $ix) * 4;
            next if $buf[$i + 3] < 0.02;            # only paint on the slab
            my $x = ($ix + 0.5) / $SS;
            my $y = ($iy + 0.5) / $SS;

            my $d = sd_hex($x, $y, $nx, $ny, $nr);
            my $cov = coverage($d, 0.0022);
            next unless $cov > 0;

            my $t = clamp(($y - ($ny - $nr)) / (2 * $nr), 0, 1);
            my $r = $C{body_hi}[0] + ($C{body_lo}[0] - $C{body_hi}[0]) * $t;
            my $g = $C{body_hi}[1] + ($C{body_lo}[1] - $C{body_hi}[1]) * $t;
            my $b = $C{body_hi}[2] + ($C{body_lo}[2] - $C{body_hi}[2]) * $t;

            # internal fire
            my $fire = clamp(1 - sqrt(($x - $nx) ** 2 + ($y - $ny + 0.03) ** 2) / ($nr * 1.2), 0, 1) ** 1.9;
            $r += @{$C{glow}}[0] * 0.34 * $fire;
            $g += @{$C{glow}}[1] * 0.34 * $fire;
            $b += @{$C{glow}}[2] * 0.40 * $fire;

            # rim: cold sky top-left, crimson lower-right
            my $rim = clamp(1 - abs($d + 0.012) / 0.016, 0, 1);
            if ($rim > 0) {
                my $along = clamp((($x - ($nx - $nr)) + ($y - ($ny - $nr))) / (2.1 * $nr), 0, 1);
                my $warm = smoothstep(0.58, 0.94, $along);
                $r += (@{$C{rim}}[0] - $r) * $rim * 0.85 * (1 - $warm * 0.5);
                $g += (@{$C{rim}}[1] - $g) * $rim * 0.85 * (1 - $warm * 0.5);
                $b += (@{$C{rim}}[2] - $b) * $rim * 0.85 * (1 - $warm * 0.5);
                $r += (@{$C{crimson}}[0] - $r) * $rim * 0.75 * $warm;
                $g += (@{$C{crimson}}[1] - $g) * $rim * 0.75 * $warm;
                $b += (@{$C{crimson}}[2] - $b) * $rim * 0.75 * $warm;
            }

            # node gloss
            my $gloss = clamp((($ny - $nr * 0.5) - $y) / ($nr * 0.9), 0, 1) ** 1.5 * 0.22;
            $r += (255 - $r) * $gloss * 0.35;
            $g += (255 - $g) * $gloss * 0.4;
            $b += (255 - $b) * $gloss * 0.48;

            px($x, $y, $r, $g, $b, $cov);
        }
    }

    # node outline: crisp electric stroke
    stroke_path(sub {
        my $t = shift;
        my @v = hex_verts($nx, $ny, $nr);
        my $seg = int($t * 6) % 6;
        my $f = $t * 6 - int($t * 6);
        return ($v[$seg][0] + ($v[($seg + 1) % 6][0] - $v[$seg][0]) * $f,
                $v[$seg][1] + ($v[($seg + 1) % 6][1] - $v[$seg][1]) * $f);
    }, 240, 0.0038, @{$C{glow_hi}}, 0.65);

    # ---- the spine: vertical stroke bridging node to outlet (subtle "P") ----
    {
        my ($ax, $ay) = ($nx + 0.018, $ny - 0.082);
        my ($bx, $by) = ($nx + 0.018, $ny + 0.096);
        stroke_seg($ax, $ay, $bx, $by, 0.026, @{$C{ink}}, 0.95);
        stroke_seg($ax, $ay, $bx, $by, 0.048, @{$C{glow}}, 0.15);
    }

    # ---- outlet: the resolved stream ----------------------------------------
    {
        my ($ox, $oy) = ($nx + $nr * 0.90, $ny + 0.004);
        my ($ex, $ey) = (0.845, $ny + 0.018);
        stroke_seg($ox, $oy, ($ox + $ex) / 2, ($oy + $ey) / 2, 0.027, @{$C{ink}}, 0.95);
        stroke_seg(($ox + $ex) / 2, ($oy + $ey) / 2, $ex, $ey, 0.029, @{$C{ink}}, 0.97);
        stroke_seg($ox, $oy, $ex, $ey, 0.058, @{$C{glow_hi}}, 0.20);
        # chevron point: forward motion
        stroke_seg($ex, $ey, $ex - 0.056, $ey - 0.052, 0.021, @{$C{ink}}, 0.95);
        stroke_seg($ex, $ey, $ex - 0.056, $ey + 0.052, 0.021, @{$C{ink}}, 0.95);
    }

    # ---- crimson signal: lower-right facet edge of the node ------------------
    {
        my @v = hex_verts($nx, $ny, $nr);
        # vertices at 0deg,60deg,...; lower-right edge = v1 -> v2
        stroke_seg($v[1][0], $v[1][1], $v[2][0], $v[2][1], 0.009, @{$C{crimson}}, 0.85);
    }
}

# quadratic bezier ribbon, tapering, with under-glow
sub ribbon {
    my ($ax, $ay, $cx, $cy, $bx, $by, $w0, $w1) = @_;
    my $N = 40;
    my ($px_, $py_, $pw) = ($ax, $ay, $w0);
    for my $i (1 .. $N) {
        my $t = $i / $N;
        my $mt = 1 - $t;
        my $x = $mt * $mt * $ax + 2 * $mt * $t * $cx + $t * $t * $bx;
        my $y = $mt * $mt * $ay + 2 * $mt * $t * $cy + $t * $t * $by;
        my $w = $w0 + ($w1 - $w0) * $t;
        my $hw = ($pw + $w) / 2;
        stroke_seg($px_, $py_, $x, $y, $hw, @{$C{ink}}, 0.92);
        stroke_seg($px_, $py_, $x, $y, $hw + 0.014, @{$C{glow}}, 0.09);
        ($px_, $py_, $pw) = ($x, $y, $w);
    }
}

sub hex_verts {
    my ($cx, $cy, $r) = @_;
    my @v;
    for my $k (0 .. 5) {
        my $a = $k * 3.14159265 / 3;
        push @v, [ $cx + $r * cos($a), $cy + $r * sin($a) ];
    }
    return @v;
}

sub stroke_path {
    my ($fn, $steps, $hw, $r, $g, $b, $alpha) = @_;
    my @pts;
    for my $i (0 .. $steps) { push @pts, [ $fn->($i / $steps) ] }
    stroke_seg($pts[ $_ - 1 ][0], $pts[ $_ - 1 ][1], $pts[$_][0], $pts[$_][1], $hw, $r, $g, $b, $alpha)
        for 1 .. $steps;
}

sub stroke_seg {
    my ($ax, $ay, $bx, $by, $hw, $r, $g, $b, $alpha) = @_;
    my $minx = int((min($ax, $bx) - $hw - 0.008) * $SS);
    my $maxx = int((max($ax, $bx) + $hw + 0.008) * $SS);
    my $miny = int((min($ay, $by) - $hw - 0.008) * $SS);
    my $maxy = int((max($ay, $by) + $hw + 0.008) * $SS);
    $minx = 0 if $minx < 0; $miny = 0 if $miny < 0;
    $maxx = $SS - 1 if $maxx >= $SS; $maxy = $SS - 1 if $maxy >= $SS;
    my $len2 = ($bx - $ax) ** 2 + ($by - $ay) ** 2;
    for my $iy ($miny .. $maxy) {
        my $py = ($iy + 0.5) / $SS;
        for my $ix ($minx .. $maxx) {
            my $pxx = ($ix + 0.5) / $SS;
            my $h = $len2 ? (($pxx - $ax) * ($bx - $ax) + ($py - $ay) * ($by - $ay)) / $len2 : 0;
            $h = 0 if $h < 0; $h = 1 if $h > 1;
            my $d = sqrt(($pxx - ($ax + ($bx - $ax) * $h)) ** 2
                       + ($py - ($ay + ($by - $ay) * $h)) ** 2);
            my $a = coverage($d - $hw, 0.0018) * $alpha;
            next unless $a > 0;
            px($pxx, $py, $r, $g, $b, $a);
        }
    }
}

sub aura {
    my ($cx, $cy, $rad, $r, $g, $b, $peak) = @_;
    return if $peak <= 0;
    for my $iy (0 .. $SS - 1) {
        my $y = ($iy + 0.5) / $SS;
        for my $ix (0 .. $SS - 1) {
            my $x = ($ix + 0.5) / $SS;
            my $d = sqrt(($x - $cx) ** 2 + ($y - $cy) ** 2);
            next if $d >= $rad;
            light($x, $y, $r, $g, $b, (1 - $d / $rad) ** 2.4 * $peak);
        }
    }
}

# ---- helpers -----------------------------------------------------------------

sub sd_seg {
    my ($px, $py, $ax, $ay, $bx, $by) = @_;
    my $pax = $px - $ax; my $pay = $py - $ay;
    my $bax = $bx - $ax; my $bay = $by - $ay;
    my $h = ($pax * $bax + $pay * $bay) / ($bax * $bax + $bay * $bay);
    $h = 0 if $h < 0; $h = 1 if $h > 1;
    return sqrt(($pax - $bax * $h) ** 2 + ($pay - $bay * $h) ** 2);
}

sub clamp { my ($v, $lo, $hi) = @_; $v = $lo if $v < $lo; $v = $hi if $v > $hi; return $v }
sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
sub max { $_[0] > $_[1] ? $_[0] : $_[1] }
sub smoothstep { my ($e0, $e1, $x) = @_; my $t = clamp(($x - $e0) / ($e1 - $e0), 0, 1); $t * $t * (3 - 2 * $t) }

# ---- encode ------------------------------------------------------------------

sub downsample {
    my $f = $PREVIEW_SS;
    return \@buf if $f == 1;
    my @out;
    my $inv = 1 / ($f * $f);
    for my $y (0 .. $S - 1) {
        for my $x (0 .. $S - 1) {
            my ($r, $g, $b, $a) = (0, 0, 0, 0);
            for my $sy (0 .. $f - 1) {
                for my $sx (0 .. $f - 1) {
                    my $i = (($y * $f + $sy) * $SS + ($x * $f + $sx)) * 4;
                    $r += $buf[$i]; $g += $buf[$i + 1]; $b += $buf[$i + 2]; $a += $buf[$i + 3];
                }
            }
            push @out, $r * $inv, $g * $inv, $b * $inv, $a * $inv;
        }
    }
    return \@out;
}

sub chunk {
    my ($type, $data) = @_;
    return pack('N', length $data) . $type . $data . pack('N', crc32($type . $data));
}

sub byte { my ($v) = @_; return 0 if !defined $v || $v != $v; $v = 0 if $v < 0; $v = 255 if $v > 255; int($v + 0.5) }

sub write_png_rgba {
    my ($path, $pix, $w, $h) = @_;
    my $raw = '';
    for my $y (0 .. $h - 1) {
        $raw .= "\0";
        for my $x (0 .. $w - 1) {
            my $i = ($y * $w + $x) * 4;
            $raw .= pack('C4', byte($pix->[$i]), byte($pix->[$i + 1]),
                              byte($pix->[$i + 2]), byte($pix->[$i + 3] * 255));
        }
    }
    my $png = "\x89PNG\r\n\x1a\n"
            . chunk('IHDR', pack('NNCCCCC', $w, $h, 8, 6, 0, 0, 0))
            . chunk('IDAT', compress($raw, 9))
            . chunk('IEND', '');
    spew($path, $png);
    printf "  %-52s %6.1f KB\n", $path, length($png) / 1024;
}

# downscale by integer box filter to an arbitrary smaller size
sub resize_box {
    my ($pix, $src, $dst) = @_;
    return $pix if $dst == $src;
    my @out;
    my $scale = $src / $dst;
    for my $y (0 .. $dst - 1) {
        my $y0 = int($y * $scale); my $y1 = int(($y + 1) * $scale) - 1; $y1 = $y0 if $y1 < $y0;
        for my $x (0 .. $dst - 1) {
            my $x0 = int($x * $scale); my $x1 = int(($x + 1) * $scale) - 1; $x1 = $x0 if $x1 < $x0;
            my ($r, $g, $b, $a) = (0, 0, 0, 0); my $n = 0;
            for my $sy ($y0 .. $y1) {
                for my $sx ($x0 .. $x1) {
                    my $i = ($sy * $src + $sx) * 4;
                    $r += $pix->[$i]; $g += $pix->[$i + 1]; $b += $pix->[$i + 2]; $a += $pix->[$i + 3];
                    $n++;
                }
            }
            push @out, $r / $n, $g / $n, $b / $n, $a / $n;
        }
    }
    return \@out;
}

# ============================================================================

paint();
my $final = downsample();

# quick self-check: any opaque content at all? (every 4th value is alpha;
# downsample returns a fresh array in list context — take a reference)
{
    my $lit = 0;
    for (my $k = 3; $k < @$final; $k += 4) { $lit++ if $final->[$k] > 0.01 }
    die "self-check failed: paint() produced an empty buffer\n" unless $lit > $S * $S * 0.04;
    print "self-check: $lit/$S opaque\n";
}

my $brand_dir = 'website/assets/brand';
unless (-d $brand_dir) {
    require File::Path;
    File::Path::make_path($brand_dir);
}

# preview mode: quick look-dev output only — into its own filename. Writing
# the small preview onto pweevee-1024.png used to quietly destroy the only
# master render.
if ($preview) {
    write_png_rgba('website/assets/brand/pweevee-look-dev.png', $final, $S, $S);
    print "preview done\n";
    exit 0;
}

# master + the renderer hook (square artwork with the ground built in)
write_png_rgba("$brand_dir/pweevee-1024.png", $final, $S, $S);
write_png_rgba("$brand_dir/pweevee.png",      $final, $S, $S);

# deployment sizes
for my $size (512, 256, 180, 64, 48, 32, 16) {
    my $small = resize_box($final, $S, $size);
    write_png_rgba("$brand_dir/pweevee-$size.png", $small, $size, $size);
}

# ---- IPA icon family -------------------------------------------------------
# The one PwEevee-owned alternate app icon that ships inside builds. It is
# written to PwEvevee/brand-icons/ with a small SHA-256 manifest so the build
# (unified.sh + package/patch-alternate-icon.pl) stages it from a pinned,
# committed file instead of depending on website assets at build time.
{
    use Digest::SHA qw(sha256_hex);
    use JSON::PP ();
    my $icons_dir = 'PwEvevee/brand-icons';
    unless (-d $icons_dir) { require File::Path; File::Path::make_path($icons_dir) }
    my $ipa_icon = "$icons_dir/pweevee-icon.png";
    write_png_rgba($ipa_icon, resize_box($final, $S, 180), 180, 180);
    {
        local $/;
        open my $fh, '<:raw', $ipa_icon or die "reopen $ipa_icon: $!\n";
        my $bytes = <$fh>;
        close $fh;
        my $sha = sha256_hex($bytes);
        my $out = JSON::PP->new->canonical->pretty;
        spew("$icons_dir/manifest.json", $out->encode({
            license => 'PwEevee project artwork; not derived from Spotify or any upstream project',
            name    => 'pweevee-brand-icon',
            origin  => 'generated_by PwEvevee/build-system/release/make-app-icon.pl (original PwEevee artwork, no upstream derivation)',
            staged_as => 'staged as Payload/Spotify.app/pweevee-icon.png and registered under CFBundleIcons.CFBundleAlternateIcons by package/patch-alternate-icon.pl',
            files   => [ { path   => 'pweevee-icon.png',
                           sha256 => $sha,
                           size   => length $bytes, } ],
        }) . "\n");
    }
}

print "app icon done\n";
