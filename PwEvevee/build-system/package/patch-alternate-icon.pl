#!/usr/bin/env perl
# Register the PwEevee brand icon as an alternate iOS app icon on a STAGED app
# (not a packaged IPA — unified.sh runs this before packaging).
#
#   PwEvevee/build-system/package/patch-alternate-icon.pl <staged Spotify.app>
#
# What it does, idempotently (running twice changes nothing the second time):
#   1. verifies PwEvevee/brand-icons/manifest.json against the SHA-256 of the
#      committed pweevee-icon.png and stages that file at the app root as
#      pweevee-icon.png (only when missing or byte-different);
#   2. mutates the app's Info.plist — XML or binary, format preserved — to add
#      CFBundleIcons.CFBundleAlternateIcons["PwEevee"]:
#          CFBundleIcons         (must already exist as a dict, or absent)
#          └ CFBundleAlternateIcons            (created if absent; other
#                                               providers' entries preserved)
#              └ PwEevee = { CFBundleIconFiles: ["pweevee-icon"],
#                            UIPrerenderedIcon: true }
# setAlternateIconName("PwEevee") (used by the Eevee settings icon page) then
# selects it at runtime; the host's own icon keys are never touched.
#
# Faithfulness: the plist is parsed and re-serialized through lib/bplist.pm, so
# unrelated keys, values and nesting survive byte-for-byte in structure; only
# the canonical writer's byte layout may differ from Apple's (content equal).
use strict;
use warnings;
use File::Basename qw(dirname);
use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use lib dirname($0) . '/../lib';
use bplist;

my $app = $ARGV[0] or die "usage: patch-alternate-icon.pl <staged app dir>\n";
-d $app or die "not a directory: $app\n";
my $BS = dirname($0) . '/..';
my $icons_dir = "$BS/../../PwEvevee/brand-icons";   # repo-root relative to this script
# override hook for tests: negatives patch temp copies of brand-icons without
# touching the committed artwork
$icons_dir = $ENV{PWEEVEE_BRAND_ICONS_DIR} if defined $ENV{PWEEVEE_BRAND_ICONS_DIR} && length $ENV{PWEEVEE_BRAND_ICONS_DIR};
$app =~ s{/+$}{};

# ---------- 1. verify + stage the icon file ----------
my $manifest_file = "$icons_dir/manifest.json";
my $icon_rel = 'pweevee-icon.png';
open(my $mf, '<', $manifest_file) or die "open $manifest_file: $!\n";
local $/; my $mbytes = <$mf>; close $mf;
my $manifest = JSON::PP::decode_json($mbytes);

my ($entry) = grep { $_->{path} eq $icon_rel } @{ $manifest->{files} // [] };
defined $entry or die "manifest $manifest_file: no entry for $icon_rel\n";
open(my $ic, '<:raw', "$icons_dir/$icon_rel") or die "open icon: $!\n";
my $icon_bytes = <$ic>; close $ic;
my $sha = sha256_hex($icon_bytes);
die "brand icon sha256 mismatch\n  manifest: $entry->{sha256}\n  actual:   $sha\n"
  unless $sha eq $entry->{sha256};
die "brand icon size mismatch (manifest $entry->{size}, actual " . length($icon_bytes) . ")\n"
  unless $entry->{size} == length($icon_bytes);

my $staged = "$app/$icon_rel";
if (-f $staged) {
  open(my $e, '<:raw', $staged) or die "open staged icon: $!\n";
  my $prev = <$e>; close $e;
  if ($prev eq $icon_bytes) {
    print "    icon: already staged, byte-identical (idempotent)\n";
  } else {
    open(my $o, '>:raw', $staged) or die "write $staged: $!\n";
    print $o $icon_bytes; close $o;
    print "    icon: restaged pweevee-icon.png (previous copy differed)\n";
  }
} else {
  open(my $o, '>:raw', $staged) or die "write $staged: $!\n";
  print $o $icon_bytes; close $o;
  print "    icon: staged pweevee-icon.png (" . length($icon_bytes) . " bytes)\n";
}

# ---------- 2. patch Info.plist ----------
my $plist_path = "$app/Info.plist";
my $tree = bplist::read_file($plist_path);
my $fmt = $tree->{fmt};

my $changed =
  bplist::set($tree, 'CFBundleIcons', 'CFBundleAlternateIcons', 'PwEevee' =>
    bplist::mkdict(
      'CFBundleIconFiles' => bplist::mkarray(bplist::mkstr('pweevee-icon')),
      'UIPrerenderedIcon' => bplist::mkbool(1)));

# Mirror into CFBundleIcons~ipad ONLY when the host already declares that key
# (like stock Spotify 9.1.90 does): iPad resolves alternate icons through the
# ~ipad variant, and an icon registerable on iPhone but not iPad is half a
# feature. We never CREATE ~ipad ourselves — adding a device-variant dict the
# host did not ship is not our call.
my $ipad = bplist::get_if($tree, 'CFBundleIcons~ipad');
if ($ipad && $ipad->[0] eq 'dict') {
  my $ipad_changed =
    bplist::set($tree, 'CFBundleIcons~ipad', 'CFBundleAlternateIcons', 'PwEevee' =>
      bplist::mkdict(
        'CFBundleIconFiles' => bplist::mkarray(bplist::mkstr('pweevee-icon')),
        'UIPrerenderedIcon' => bplist::mkbool(1)));
  if ($ipad_changed) { print "    plist: mirrored into CFBundleIcons~ipad (host declares it)\n" }
  else { print "    plist: CFBundleIcons~ipad already carries PwEevee\n" }
  $changed ||= $ipad_changed;
}

if ($changed) {
  bplist::write_file($plist_path, $tree);
  print "    plist: CFBundleIcons.CFBundleAlternateIcons.PwEevee registered ($fmt, faithful rewrite)\n";
} else {
  print "    plist: alternate icon already registered, no change (idempotent)\n";
}

# ---------- 3. self-check: re-read and confirm the structure ----------
my $check = bplist::read_file($plist_path);
my $node = bplist::get_if($check, 'CFBundleIcons', 'CFBundleAlternateIcons', 'PwEevee');
die "post-patch self-check failed: PwEevee entry not readable\n"
  unless $node && bplist::same($node,
           bplist::mkdict('CFBundleIconFiles' => bplist::mkarray(bplist::mkstr('pweevee-icon')),
                          'UIPrerenderedIcon' => bplist::mkbool(1)));
print "    self-check: patched plist reads back correct\n";
exit 0;
