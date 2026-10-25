#!/usr/bin/env perl
# ============================================================================
# make-social-card.pl — render website/assets/social-card.png
# ============================================================================
#
#   perl PwEvevee/build-system/release/make-social-card.pl [out.png]
#
# Writes the 1200x630 Open Graph image used by website-src/layout.html, in the
# site's own visual language: paper, a hairline frame, the app icon presented as
# an app icon, and one short dash of the logo blue. It is deliberately the same
# composition as the hero figure (.showcase in pweevee.css) — a link preview
# should look like the page it links to.
#
# There is no gradient, no glow, no floor reflection and no plinth. A preview
# thumbnail is usually rendered small, so the card carries one idea.
#
# If website/assets/brand/pweevee-logo.png exists it is composited as-is — never
# recoloured, never stretched, never cropped. Otherwise the same original
# circle-and-chevron mark as website/assets/favicon.svg is drawn procedurally,
# flat, in the site's ink colour.
#
# Pure core Perl. Compress::Zlib ships with perl and provides deflate, inflate
# and CRC32, which is everything needed to both read and write a PNG. No image
# library, no ImageMagick.
# ============================================================================
use strict;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/lib";
use Compress::Zlib qw(compress crc32);
use PwSite qw(repo_root spew);
use PwPng qw(png_read);      # shared PNG reader, also used by make-brand-assets.pl

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $OUT = $ARGV[0] || 'website/assets/social-card.png';
my ($W, $H) = (1200, 630);

# The palette, identical to the six values in pweevee.css plus the logo blue.
my @PAPER      = (0xf5, 0xf5, 0xf3);   # --off-white
my @SURFACE    = (0xff, 0xff, 0xff);   # --white
my @RULE       = (0xe8, 0xe8, 0xe6);   # --light-gray
my @RULE_FIRM  = (0xd2, 0xd2, 0xcf);   # --rule-strong
my @INK        = (0x08, 0x08, 0x08);   # --near-black
my @BLUE       = (0x2a, 0x37, 0x62);   # --blue, sampled from the logo artwork

my @buf = (0) x ($W * $H * 3);

# ---------------------------------------------------------------- the paper

fill(@PAPER);

# ------------------------------------------------------------- the composition

# A square frame, a gap, and a short accent dash — centred as one group, exactly
# like .showcase / .showcase__caption on the page. The frame is large enough that
# the artwork still reads when a feed renders the card at thumbnail size.
my $FRAME  = 400;
my $GAP    = 40;
my $DASH_W = 52;
my $DASH_H = 2;

my $group = $FRAME + $GAP + $DASH_H;
my $FX = int(($W - $FRAME) / 2);
my $FY = int(($H - $group) / 2);

rrect($FX, $FY, $FRAME, $FRAME, 32, @SURFACE, 1);            # paper fill
rrect_stroke($FX, $FY, $FRAME, $FRAME, 32, @RULE, 1.4);      # hairline border

my $PAD = 44;                              # matches the frame padding on the page
my $ART = $FRAME - $PAD * 2;

my $art = find_art();
if ($art) {
    my $img = png_read($art);
    if ($img) {
        draw_image($img, $FX + $PAD, $FY + $PAD, $ART, $ART);
        printf "  composited %s (%dx%d)\n", $art, $img->{w}, $img->{h};
    } else {
        warn "!! could not decode $art; drawing the procedural mark instead\n";
        draw_mark();
    }
} else {
    draw_mark();
}

# the accent: the only colour on the card beyond ink and paper
rect(int($W / 2) - int($DASH_W / 2), $FY + $FRAME + $GAP, $DASH_W, $DASH_H, @BLUE, 1);

# ------------------------------------------------------------------ encode

my $raw = '';
for my $y (0 .. $H - 1) {
    $raw .= "\0";
    for my $x (0 .. $W - 1) {
        my $i = ($y * $W + $x) * 3;
        $raw .= pack('C3', byte($buf[$i]), byte($buf[$i + 1]), byte($buf[$i + 2]));
    }
}

my $png = "\x89PNG\r\n\x1a\n"
        . chunk('IHDR', pack('NNCCCCC', $W, $H, 8, 2, 0, 0, 0))
        . chunk('IDAT', compress($raw, 9))
        . chunk('IEND', '');

spew($OUT, $png);
printf "Wrote %s (%dx%d, %.1f KB)\n", $OUT, $W, $H, length($png) / 1024;

# ============================================================ the mark

# The official BRAND artwork (the original PwEevee render), by its canonical
# name. Only PNG is decodable here. The Spotify-derived app-icon depiction is
# deliberately NOT a brand source.
sub find_art {
    for my $base (qw(pweevee)) {
        my $p = "website/assets/brand/$base.png";
        return $p if -f $p && -s $p;
    }
    return undef;
}

# Original circle-and-chevron mark, matching website/assets/favicon.svg. Flat
# ink on paper: no sphere shading, no rim light, no specular highlight.
sub draw_mark {
    my $cx = $FX + $FRAME / 2;
    my $cy = $FY + $FRAME / 2;
    my $rad = $ART / 2;

    # the circle as a hairline outline, so the chevrons carry the weight
    for my $y (int($cy - $rad - 3) .. int($cy + $rad + 3)) {
        next if $y < 0 || $y >= $H;
        for my $x (int($cx - $rad - 3) .. int($cx + $rad + 3)) {
            next if $x < 0 || $x >= $W;
            my $d = sqrt(($x + 0.5 - $cx) ** 2 + ($y + 0.5 - $cy) ** 2);
            my $cov = clamp(0.9 - abs($d - $rad), 0, 1);
            blend_px($x, $y, @RULE_FIRM, $cov) if $cov > 0;
        }
    }

    my $u = $ART / 64;
    chevron(1,    4.6, 0,  \@INK, $u);
    chevron(0.55, 4.6, 12, \@INK, $u);
    # the base rule, in the accent rather than in ink
    stamp(0.9, [ [ 21, 50, 43, 50, 3 ] ], \@BLUE, $u);
}

sub chevron {
    my ($alpha, $width, $dy, $ink, $u) = @_;
    stamp($alpha, [
        [ 19, 30 + $dy,   32, 19.5 + $dy, $width ],
        [ 32, 19.5 + $dy, 45, 30 + $dy,   $width ],
    ], $ink, $u);
}

# Rasterise a shape into one coverage mask, then composite once — drawing the
# arms separately would double-blend where the round caps overlap at the apex.
sub stamp {
    my ($alpha, $segments, $ink, $u) = @_;
    my $ox = $FX + $PAD;
    my $oy = $FY + $PAD;
    my %mask;
    for my $s (@$segments) {
        my ($x1, $y1, $x2, $y2, $w) = @$s;
        seg_mask(\%mask, $ox + $x1 * $u, $oy + $y1 * $u,
                         $ox + $x2 * $u, $oy + $y2 * $u, $w * $u / 2);
    }
    for my $key (keys %mask) {
        my ($x, $y) = split /,/, $key;
        blend_px($x, $y, @$ink, $mask{$key} * $alpha);
    }
}

# ============================================================ compositing

# The PNG reader lives in lib/PwPng.pm so make-brand-assets.pl and this
# script share one implementation. What stays here is card-specific
# compositing: sampling and placement.
sub sample {
    my ($img, $u, $v) = @_;
    my $sx = int($u * $img->{w});
    my $sy = int($v * $img->{h});
    $sx = $img->{w} - 1 if $sx >= $img->{w};
    $sy = $img->{h} - 1 if $sy >= $img->{h};
    $sx = 0 if $sx < 0;
    $sy = 0 if $sy < 0;
    my $row = $img->{rows}[$sy];
    my $o = $sx * $img->{bpp};
    my @c = unpack('C' . $img->{bpp}, substr($row, $o, $img->{bpp}));
    my $a = $img->{bpp} == 4 ? $c[3] / 255 : 1;
    return ($c[0], $c[1], $c[2], $a);
}

# Contained, never stretched: the artwork keeps its aspect ratio inside the box.
sub draw_image {
    my ($img, $dx, $dy, $dw, $dh) = @_;

    my $scale = min($dw / $img->{w}, $dh / $img->{h});
    my $fw = int($img->{w} * $scale + 0.5);
    my $fh = int($img->{h} * $scale + 0.5);
    $dx += int(($dw - $fw) / 2);
    $dy += int(($dh - $fh) / 2);

    # 2x2 supersample so the downscale does not alias
    for my $y (0 .. $fh - 1) {
        my $ty = $dy + $y;
        next if $ty < 0 || $ty >= $H;
        for my $x (0 .. $fw - 1) {
            my $tx = $dx + $x;
            next if $tx < 0 || $tx >= $W;
            my ($r, $g, $b, $a) = (0, 0, 0, 0);
            for my $sy (0, 1) {
                for my $sx (0, 1) {
                    my ($pr, $pg, $pb, $pa) =
                        sample($img, ($x + ($sx + 0.5) / 2) / $fw, ($y + ($sy + 0.5) / 2) / $fh);
                    $r += $pr * $pa; $g += $pg * $pa; $b += $pb * $pa; $a += $pa;
                }
            }
            next unless $a > 0;
            blend_px($tx, $ty, $r / $a, $g / $a, $b / $a, $a / 4);
        }
    }
}

# ============================================================ primitives

sub fill {
    my ($r, $g, $b) = @_;
    for my $i (0 .. $W * $H - 1) {
        @buf[ $i * 3, $i * 3 + 1, $i * 3 + 2 ] = ($r, $g, $b);
    }
}

sub rect {
    my ($x, $y, $w, $h, $r, $g, $b, $a) = @_;
    for my $py ($y .. $y + $h - 1) {
        for my $px ($x .. $x + $w - 1) {
            blend_px($px, $py, $r, $g, $b, $a);
        }
    }
}

# Signed distance to a rounded rectangle, so both the fill and the border are
# antialiased from the same geometry and cannot disagree by half a pixel.
sub rr_dist {
    my ($px, $py, $x, $y, $w, $h, $rad) = @_;
    my $cx = $x + $w / 2;
    my $cy = $y + $h / 2;
    my $qx = abs($px - $cx) - ($w / 2 - $rad);
    my $qy = abs($py - $cy) - ($h / 2 - $rad);
    my $ax = $qx > 0 ? $qx : 0;
    my $ay = $qy > 0 ? $qy : 0;
    my $outside = sqrt($ax * $ax + $ay * $ay);
    my $inside = max($qx, $qy);
    $inside = 0 if $inside > 0;
    return $outside + $inside - $rad;
}

sub rrect {
    my ($x, $y, $w, $h, $rad, $r, $g, $b, $a) = @_;
    for my $py ($y - 2 .. $y + $h + 2) {
        next if $py < 0 || $py >= $H;
        for my $px ($x - 2 .. $x + $w + 2) {
            next if $px < 0 || $px >= $W;
            my $d = rr_dist($px + 0.5, $py + 0.5, $x, $y, $w, $h, $rad);
            my $cov = clamp(0.5 - $d, 0, 1);
            blend_px($px, $py, $r, $g, $b, $cov * $a) if $cov > 0;
        }
    }
}

sub rrect_stroke {
    my ($x, $y, $w, $h, $rad, $r, $g, $b, $t) = @_;
    my $hw = $t / 2;
    for my $py ($y - 3 .. $y + $h + 3) {
        next if $py < 0 || $py >= $H;
        for my $px ($x - 3 .. $x + $w + 3) {
            next if $px < 0 || $px >= $W;
            my $d = rr_dist($px + 0.5, $py + 0.5, $x, $y, $w, $h, $rad);
            my $cov = clamp(0.5 - (abs($d) - $hw), 0, 1);
            blend_px($px, $py, $r, $g, $b, $cov) if $cov > 0;
        }
    }
}

# ============================================================ helpers

sub chunk {
    my ($type, $data) = @_;
    return pack('N', length $data) . $type . $data . pack('N', crc32($type . $data));
}

# Also guards against NaN: a NaN fails every comparison, so the != self test
# catches it before pack() does.
sub byte {
    my ($v) = @_;
    return 0 if !defined $v || $v != $v;
    $v = 0 if $v < 0;
    $v = 255 if $v > 255;
    return int($v + 0.5);
}
sub clamp { my ($v, $lo, $hi) = @_; return $v < $lo ? $lo : $v > $hi ? $hi : $v }
sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
sub max { $_[0] > $_[1] ? $_[0] : $_[1] }

sub blend_px {
    my ($x, $y, $r, $g, $b, $a) = @_;
    return if $a <= 0 || $x < 0 || $y < 0 || $x >= $W || $y >= $H;
    $a = 1 if $a > 1;
    my $i = (int($y) * $W + int($x)) * 3;
    $buf[$i]     += ($r - $buf[$i])     * $a;
    $buf[$i + 1] += ($g - $buf[$i + 1]) * $a;
    $buf[$i + 2] += ($b - $buf[$i + 2]) * $a;
}

sub seg_mask {
    my ($mask, $x1, $y1, $x2, $y2, $hw) = @_;
    my $pad = $hw + 2;
    my ($x0, $xe) = (int(min($x1, $x2) - $pad), int(max($x1, $x2) + $pad));
    my ($y0, $ye) = (int(min($y1, $y2) - $pad), int(max($y1, $y2) + $pad));
    my $dx = $x2 - $x1;
    my $dy = $y2 - $y1;
    my $len2 = $dx * $dx + $dy * $dy;
    for my $y ($y0 .. $ye) {
        next if $y < 0 || $y >= $H;
        for my $x ($x0 .. $xe) {
            next if $x < 0 || $x >= $W;
            my $px = $x + 0.5;
            my $py = $y + 0.5;
            my $t = $len2 ? clamp((($px - $x1) * $dx + ($py - $y1) * $dy) / $len2, 0, 1) : 0;
            my $d = sqrt(($px - ($x1 + $t * $dx)) ** 2 + ($py - ($y1 + $t * $dy)) ** 2);
            my $a = clamp(($hw - $d) + 0.5, 0, 1);
            next unless $a > 0;
            my $key = "$x,$y";
            $mask->{$key} = $a if !exists $mask->{$key} || $mask->{$key} < $a;
        }
    }
}
