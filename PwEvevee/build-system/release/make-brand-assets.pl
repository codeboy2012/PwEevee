#!/usr/bin/env perl
# ============================================================================
# make-brand-assets.pl — derive the icon sizes from the official PwEevee logo
# ============================================================================
#
#   perl PwEvevee/build-system/release/make-brand-assets.pl
#
# Source of truth:
#     website/assets/brand/pweevee-1024.png   (the ORIGINAL PwEevee render by
#                                              make-app-icon.pl; also copied to
#                                              pweevee.png)
# The Spotify-derived artwork (pweevee-app-icon.png) NEVER feeds these sizes:
# it is third-party depiction used only in the "App icon" showcase.
#
# Writes, by DOWNSCALING ONLY (from the original PwEevee artwork):
#     website/assets/icon-32.png     favicon
#     website/assets/icon-180.png    Apple touch icon
#     website/assets/icon-512.png    large / installable icon
#
# The official artwork is never recoloured, redrawn, cropped or replaced. These
# outputs exist because a favicon slot genuinely needs a small raster — shipping
# a 1280x1280 / 477 KB PNG as a favicon would be wasteful. Everywhere the size
# does not matter (hero, project cards, Open Graph) the site references the
# original file directly.
#
# Alpha is premultiplied during the box-average so the rounded corners stay
# clean instead of picking up a dark fringe.
#
# Re-run this whenever the logo is replaced, then re-run render-site.pl.
# ============================================================================
use strict;
use warnings;
use FindBin ();
use lib "$FindBin::Bin/lib";
use PwSite qw(repo_root);
use PwPng qw(png_read png_write png_resize png_info);

my $ROOT = $ENV{PWEEVEE_ROOT} || repo_root($FindBin::Bin);
chdir $ROOT or die "cannot chdir to $ROOT: $!\n";

my $SRC = 'website/assets/brand/pweevee-1024.png';
my @SIZES = (32, 180, 512);

unless (-f $SRC && -s $SRC) {
    print STDERR "!! missing $SRC\n"
               . "   The official logo must be present before the icon sizes can be derived.\n";
    exit 2;
}

my $img = png_read($SRC);
unless ($img) {
    print STDERR "!! could not decode $SRC\n"
               . "   Expected a non-interlaced 8-bit RGB or RGBA PNG.\n";
    exit 2;
}

printf "Source: %s (%s, %.1f KB)\n", $SRC, png_info($img), (-s $SRC) / 1024;
printf "  %s square source\n", $img->{w} == $img->{h} ? 'yes,' : 'WARNING: not a';
warn "!! the logo is not square ($img->{w}x$img->{h}); the derived icons will keep the\n"
   . "   source aspect ratio rather than distort the artwork\n"
    if $img->{w} != $img->{h};

for my $size (@SIZES) {
    my $out = "website/assets/icon-$size.png";
    # keep the source aspect ratio; never stretch to a square
    my $tw = $size;
    my $th = $img->{w} == $img->{h} ? $size : int($size * $img->{h} / $img->{w} + 0.5);
    my $small = png_resize($img, $tw, $th)
        or die "!! resize to ${tw}x${th} failed\n";
    my $bytes = png_write($out, $small);
    printf "  wrote %-30s %4dx%-4d %6.1f KB\n", $out, $tw, $th, $bytes / 1024;
}

print "Done. Re-run render-site.pl so the pages pick these up.\n";
