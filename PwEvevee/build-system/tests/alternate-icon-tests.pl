#!/usr/bin/env perl
# Regression tests for build-system/package/patch-alternate-icon.pl and the
# referenced-alternate-icon check inside validate/validate-ipa.pl.
#
#   perl PwEvevee/build-system/tests/alternate-icon-tests.pl
#
# Everything runs on TEMP COPIES (staging dirs + a temp brand-icons dir via
# the PWEEVEE_BRAND_ICONS_DIR override); the committed artwork and fixtures
# are only ever read, never written.
#
# Covers:
#   * patch twice -> idempotent: no duplicate CFBundleAltAlternateIcons entries,
#     Info.plist bytes identical on the second run
#   * unrelated keys, values and nested structures survive the rewrite
#   * other providers' CFBundleAlternateIcons entries are preserved and the
#     PwEevee entry is *added*, not swapped in
#   * the CFBundleIcons~ipad leg mirrors only when the host declares the dict
#   * staged icon file exists and matches the manifest's sha256/size
#   * negatives: corrupted icon, manifest sha mismatch, missing icon file,
#     missing manifest -> hard die, staging tree left fail-safe
#   * validate-ipa.pl: patched staging passes; deleting the staged icon file
#     makes it report ALTERNATE ICON MISSING
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use File::Spec::Functions qw(catfile);
use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use lib dirname($0) . '/../lib';
use bplist;

my $ROOT   = dirname($0) . '/../../..';
my $FIXTURE  = catfile($ROOT, 'PwEvevee', 'build-system', 'tests', 'fixtures', 'Info-Spotify-9.1.90.plist');
my $PATCHER  = catfile($ROOT, 'PwEvevee', 'build-system', 'package', 'patch-alternate-icon.pl');
my $VALIDATE = catfile($ROOT, 'PwEvevee', 'build-system', 'validate', 'validate-ipa.pl');
my $ICON_SRC = catfile($ROOT, 'PwEvevee', 'brand-icons', 'pweevee-icon.png');
my $MAN_SRC  = catfile($ROOT, 'PwEvevee', 'brand-icons', 'manifest.json');

my $pass = 0;
my @failures;
sub ok   { my ($c, $w) = @_; $c ? $pass++ : push @failures, $w }

# dies_like( \&code, qr/pattern/, $msg ): must die with a matching message.
sub dies_like {
  my ($code, $re, $what) = @_;
  my $ran = eval { $code->(); 1 };
  if (!$ran && $@ =~ $re) { $pass++; return }
  push @failures, $what . (defined $@ && length $@ ? '' : ''), "die($@) vs /$re/";
}
sub _slurp { my ($p) = @_; open my $f, '<:raw', $p or die "open $p: $!"; local $/; my $d = <$f>; close $f; $d }
sub _spew  { my ($p, $d) = @_; open my $f, '>:raw', $p or die "write $p: $!"; print $f $d; close $f }

for my $pre ($FIXTURE, $PATCHER, $VALIDATE, $ICON_SRC, $MAN_SRC) {
  -f $pre or die "required input missing: $pre\n";
}

my $icon_bytes = _slurp($ICON_SRC);
my $manifest   = JSON::PP::decode_json(_slurp($MAN_SRC));

# ---------- helpers: fresh staging + fresh temp brand dir per case ----------
my $T = catfile(div_cat(), "alticon-tests-$$");
sub div_cat { return $ENV{TEMP} || '/tmp' }

sub temp_brand_dir {
  my ($dir) = @_;
  make_path($dir);
  _spew(catfile($dir, 'pweevee-icon.png'), $icon_bytes);
  _spew(catfile($dir, 'manifest.json'),    _slurp($MAN_SRC));
  return $dir;
}

sub fresh_app {
  my ($name) = @_;
  my $app = catfile($T, $name, 'Payload', 'Spotify.app');
  make_path($app);
  copy($FIXTURE, catfile($app, 'Info.plist')) or die "copy fixture: $!";
  # minimal structure so validate-ipa.pl's other checks don't interfere
  make_path(catfile($app, 'Frameworks'));
  _spew(catfile($app, 'Spotify'), "not a real binary; structure fixture only\n");
  _spew(catfile($app, 'PkgInfo'), "APPL????\n");
  return $app;
}

sub run_patch {
  my ($app, %env) = @_;
  local %ENV = (%ENV, %env);
  my $out = `$^X "$PATCHER" "$app" 2>&1`;
  die "patcher blew up: $out\n" if $? != 0;
  return $out;
}

# ---------- 1. happy path + idempotence on a REAL Info.plist copy ----------
{
  my $brand = temp_brand_dir(catfile($T, 'brand'));
  my $app   = fresh_app('app1');

  my $before = _slurp(catfile($app, 'Info.plist'));
  my ($out1, $out2);
  {
    local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
    $out1 = run_patch($app);
    ok(-f catfile($app, 'pweevee-icon.png'), 'patcher stages pweevee-icon.png at the app root');
    ok(sha256_hex(_slurp(catfile($app, 'pweevee-icon.png'))) eq sha256_hex($icon_bytes),
       'staged icon bytes match the committed artwork');
    my $after1 = _slurp(catfile($app, 'Info.plist'));
    $out2 = run_patch($app);
    my $after2 = _slurp(catfile($app, 'Info.plist'));
    ok($after1 eq $after2, 'second run leaves Info.plist byte-identical (idempotent)');
    ok($out2 =~ /already registered, no change/, 'second run reports already-registered');
  }

  my $tree = bplist::read_file(catfile($app, 'Info.plist'));
  my $entry = bplist::get_if($tree, 'CFBundleIcons', 'CFBundleAlternateIcons', 'PwEevee');
  ok(defined $entry && bplist::same($entry,
     bplist::mkdict(CFBundleIconFiles => bplist::mkarray(bplist::mkstr('pweevee-icon')),
                    UIPrerenderedIcon => bplist::mkbool(1))),
     'CFBundleIcons -> CFBundleAlternateIcons -> PwEevee registered with icon files + UIPrerenderedIcon');

  # no duplicate PwEevee entries anywhere
  my $alts = bplist::get_if($tree, 'CFBundleIcons', 'CFBundleAlternateIcons');
  my $n_pweevee = 0;
  { my $p = $alts->[1]; for (my $i = 0; $i < @$p; $i += 2) { $n_pweevee++ if $p->[$i] eq 'PwEevee' } }
  ok($n_pweevee == 1, 'exactly one PwEevee key inside CFBundleAlternateIcons (no duplicates)');

  # unrelated keys and the host's own CFBundleIcons payload survive
  for my $k (qw(CFBundleShortVersionString CFBundleIdentifier CFBundleExecutable SpotifyVersionPacked CFBundleDisplayName)) {
    ok(bplist::has_key($tree, $k), 'unrelated top-level key survives: ' . $k);
  }
  my $icons = bplist::get_if($tree, 'CFBundleIcons');
  my $host_keys = grep { $_ ne 'CFBundleAlternateIcons' } map { $icons->[1][ $_*2 ] } 0 .. ($#{ $icons->[1] } / 2);
  ok($host_keys > 0, 'host-declared keys inside CFBundleIcons are preserved alongside the added dict');
}

# ---------- 2. ~ipad mirroring honors the host declaration ----------
{
  my $brand = temp_brand_dir(catfile($T, 'brand2'));
  my $app   = fresh_app('app2');
  my $tree0 = bplist::read_file(catfile($FIXTURE));
  ok(bplist::has_key($tree0, 'CFBundleIcons~ipad'),
     'fixture declares CFBundleIcons~ipad (real Spotify 9.1.90 behavior)');
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  run_patch($app);
  my $tree = bplist::read_file(catfile($app, 'Info.plist'));
  ok(defined bplist::get_if($tree, 'CFBundleIcons~ipad', 'CFBundleAlternateIcons', 'PwEevee'),
     '~ipad leg mirrors the PwEevee entry because the host declares the dict');

  # a host WITHOUT ~ipad must not gain one
  my $app3 = fresh_app('app3');
  my $t3 = bplist::read_file(catfile($app3, 'Info.plist'));
  { # remove the ~ipad dict to simulate a host that never shipped it
    my $p = $t3->{root}[1];
    for (my $i = 0; $i < @$p; $i += 2) {
      if ($p->[$i] eq 'CFBundleIcons~ipad') { splice(@$p, $i, 2); last }
    }
  }
  bplist::write_file(catfile($app3, 'Info.plist'), $t3);
  run_patch($app3);
  my $t3b = bplist::read_file(catfile($app3, 'Info.plist'));
  ok(!bplist::has_key($t3b, 'CFBundleIcons~ipad'), 'absent ~ipad key is never created');
  ok(defined bplist::get_if($t3b, 'CFBundleIcons', 'CFBundleAlternateIcons', 'PwEevee'), 'iPhone leg still registered');
}

# ---------- 3. other providers' alternate entries are preserved ----------
{
  my $brand = temp_brand_dir(catfile($T, 'brand3'));
  my $app   = fresh_app('app4');
  my $tree  = bplist::read_file(catfile($app, 'Info.plist'));
  my $foreign = bplist::mkdict(
    CFBundleIconFiles => bplist::mkarray(bplist::mkstr('OtherGuy')),
    UIPrerenderedIcon => bplist::mkbool(0));
  bplist::set($tree, 'CFBundleIcons', 'CFBundleAlternateIcons', 'SomeOtherProvider' => $foreign);
  bplist::write_file(catfile($app, 'Info.plist'), $tree);
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  run_patch($app);
  my $after = bplist::read_file(catfile($app, 'Info.plist'));
  ok(bplist::same(bplist::get_if($after, 'CFBundleIcons', 'CFBundleAlternateIcons', 'SomeOtherProvider'),
                  $foreign), 'foreign provider entry survives byte-equal');
  ok(defined bplist::get_if($after, 'CFBundleIcons', 'CFBundleAlternateIcons', 'PwEevee'), 'PwEevee added next to it');
}

# ---------- 4. negatives: corrupt icon / manifest -> hard die ----------
{
  my $brand = temp_brand_dir(catfile($T, 'brand4'));
  my $app   = fresh_app('app5');
  # a. corrupt the icon bytes (same size, different content)
  my $bad = $icon_bytes; substr($bad, 900, 1) = chr((ord(substr($bad, 900, 1)) + 7) % 256);
  _spew(catfile($brand, 'pweevee-icon.png'), $bad);
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  dies_like(sub { run_patch($app) }, qr/sha256 mismatch/, 'corrupted icon bytes are rejected by the manifest sha256');
}

{
  my $brand = temp_brand_dir(catfile($T, 'brand5'));
  my $app   = fresh_app('app6');
  my $m = JSON::PP::decode_json(_slurp($MAN_SRC));
  $m->{files}[0]{sha256} = '0' x 64;
  _spew(catfile($brand, 'manifest.json'), JSON::PP->new->canonical->encode($m));
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  dies_like(sub { run_patch($app) }, qr/sha256 mismatch/, 'manifest with the wrong sha256 is rejected');
  ok(!-f catfile($app, 'pweevee-icon.png'), 'die happens BEFORE the icon is staged');
}

{
  my $brand = temp_brand_dir(catfile($T, 'brand6'));
  unlink catfile($brand, 'pweevee-icon.png');
  my $app = fresh_app('app7');
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  dies_like(sub { run_patch($app) }, qr/open icon:/, 'missing icon file is rejected');
}

{
  my $brand = temp_brand_dir(catfile($T, 'brand7'));
  unlink catfile($brand, 'manifest.json');
  my $app = fresh_app('app8');
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  dies_like(sub { run_patch($app) }, qr/manifest\.json/, 'missing manifest.json is rejected');
}

# ---------- 5. validate-ipa.pl: referenced icon must exist ----------
{
  my $brand = temp_brand_dir(catfile($T, 'brand8'));
  my $app   = fresh_app('app9');
  local $ENV{PWEEVEE_BRAND_ICONS_DIR} = $brand;
  run_patch($app);
  my $out = `$^X "$VALIDATE" "$app" 2>&1`;
  ok($? == 0, 'validate-ipa passes on a fully patched staging') or diag($out);
  ok($out !~ /ALTERNATE ICON MISSING/, 'no missing-icon report when the file is staged');

  unlink catfile($app, 'pweevee-icon.png');
  my $out2 = `$^X "$VALIDATE" "$app" 2>&1`;
  ok($? != 0, 'validate-ipa fails after the staged icon file is deleted');
  ok($out2 =~ qr{ALTERNATE ICON MISSING: PwEevee/pweevee-icon}, 'the missing-icon line names the provider and file') or diag($out2);

  # unrelated staging without alternate icons passes untouched
  my $app_bare = fresh_app('app10');
  my $out3 = `$^X "$VALIDATE" "$app_bare" 2>&1`;
  ok($? == 0 && $out3 !~ /ALTERNATE ICON/, 'staging with no alternate icons validates without icon messages');
}

remove_tree($T);
if (@failures) {
  print "ALTERNATE-ICON TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
print "ALTERNATE-ICON TESTS PASSED ($pass checks)\n";
exit 0;
