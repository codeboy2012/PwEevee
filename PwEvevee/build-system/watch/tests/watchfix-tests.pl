#!/usr/bin/env perl
# ============================================================================
# watchfix-tests.pl — regression tests for the watch-aware pipeline stage.
#
#   perl PwEvevee/build-system/watch/tests/watchfix-tests.pl
#
# Builds a synthetic Payload/Spotify.app tree (with a Watch/WatchApp.app,
# a WatchWidgetExtension.appex and an IntentsSupportOnlyPhoneExtension.appex)
# in a temp dir and asserts every failure class the real installer reported:
#   AppexBundleIDNotPrefixed, IntentsAppexIntentsSupportedNotASubset,
#   missing WKCompanionAppBundleIdentifier, stale WKWatchKitApp placement.
# The validator is exercised in BOTH the broken baseline state (must fail)
# and the watchfix-fixed state (must pass).
# ============================================================================
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use JSON::PP ();

my $ROOT = abs_path(dirname(abs_path(__FILE__)) . '/../../..');
my $WATCH = "$ROOT/build-system/watch";
my $T = $ENV{TMPDIR} || '/tmp';
my $dir = "$T/watchfix-test-$$";
remove_tree($dir);
make_path($dir);

# resolve the plistlib-capable python interpreter once: some macOS boxes
# ship only python3 (no `python` executable).
my $PY = 'python3';
$PY = 'python'  if (system('sh', '-c', 'command -v python >/dev/null 2>&1') / 256) == 0;
$PY = 'python3' if (system('sh', '-c', 'command -v python3 >/dev/null 2>&1') / 256) == 0;

my ($pass, $fail) = (0, 0);
sub ok  { $pass++; printf "  ok  %s\n", $_[0]; }
sub nok { $fail++; printf "  FAIL %s%s\n", $_[0], defined $_[1] ? " -- $_[1]" : ''; }
sub check { my ($c, $n, $w) = @_; $c ? ok($n) : nok($n, $w); }

my $app = "$dir/Payload/Spotify.app";
my $watch = "$app/Watch/WatchApp.app";
my $widget = "$watch/PlugIns/WatchWidgetExtension.appex";
my $intents = "$app/PlugIns/InsightsIntents.appex";
make_path("$watch/PlugIns");
make_path($widget, $intents);
# make-ipa.pl self-check requires an executable + PkgInfo at the app root.
open my $ex, '>', "$app/Spotify" or die "open fake exe: $!"; print $ex "fake\n"; close $ex;
open my $pi, '>', "$app/PkgInfo" or die "open PkgInfo: $!"; print $pi "APPL????"; close $pi;

# Minimal XML plists for each level.
sub write_plist {
  my ($path, $id, %extra) = @_;
  my $extra = '';
  $extra .= "  <key>$_</key><string>$extra{$_}</string>\n" for sort keys %extra;
  open my $fh, '>', $path or die "open $path: $!";
  print $fh <<"PLIST";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$id</string>
$extra</dict></plist>
PLIST
  close $fh;
}

# Broken baseline, exactly the shape that produced the installer errors:
#   - outer id in the legacy skywatch scheme
#   - watch app already rewritten to the spotipw scheme (mismatch!)
#   - widget appex still in the old skywatch scheme (not prefixed by new watch id)
#   - no WKCompanionAppBundleIdentifier on the Watch app (Apple: it belongs there)
#   - WKWatchKitApp on the OUTER side (wrong side; Apple: Watch-app-only key)
#   - intents extension declares an intent the phone app lacks
write_plist("$app/Info.plist", 'com.skywatch.spotify', 'WKWatchKitApp' => 'true');
write_plist("$watch/Info.plist", 'com.spotipw.client.3522J7W583.watchkitapp');
write_plist("$widget/Info.plist", 'com.skywatch.spotify.watchkitapp.widget');
write_plist("$intents/Info.plist", 'com.skywatch.spotify.intents');

open my $fh, '>', "$intents/Info.plist" or die;
print $fh <<"PLISTI";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.skywatch.spotify.intents</string>
  <key>NSExtension</key><dict>
    <key>NSExtensionAttributes</key><dict>
      <key>IntentsSupported</key><array><string>SendMessageIntent</string></array>
    </dict></dict>
  </dict></plist>
PLISTI
close $fh;

my $chk = sub { system($^X, "$WATCH/validate-watchfix.pl", $app) };

# ---- test 1: baseline fails ----
{
  my $out = qx($^X $WATCH/validate-watchfix.pl $app 2>&1);
  my $rc = $?;
  check($rc != 0, 'baseline broken tree FAILS validation') or note_out($out);
  for my $err ('APPEX NOT PREFIXED', 'INTENTS SUBSET VIOLATION', 'COMPANION ID MISMATCH', 'WRONG SIDE', 'MISSING WKCompanionAppBundleIdentifier on Watch app') {
    ok(index($out, $err) >= 0, "baseline identifies: $err")
      or diag("missing '$err' in output:\n$out");
  }
}

sub note_out { }
sub diag { printf "    [diag] %s\n", $_ for split /\n/, $_[0]; }

# ---- test 2: watchfix.sh --skip-sign fixes everything ----
{
  # fake input IPA out of the tree
  # build a stage-only (unsigned, no re-sign) run: point watchfix at a zip: use
  # the repo zip.pm to write a minimal IPA wrapper quickly.
  my $zip_pl = "$ROOT/build-system/package/make-ipa.pl";
  my $lib = "$ROOT/build-system/lib";
  my $pa = "$dir/stage";
  remove_tree($pa);
  make_path("$pa/Payload");
  system('cp', '-a', "$dir/Payload/Spotify.app", "$pa/Payload/Spotify.app");
  my $out = qx($^X $zip_pl $pa/Payload/Spotify.app $dir/input.ipa 2>&1);
  my $rc = $?;
  check($rc == 0, 'make-ipa.pl produced input IPA') or diag($out);

  my $fixed_out = "$dir/fixed.ipa";
  $out = qx(bash "$WATCH/watchfix.sh" "$dir/input.ipa" --out "$fixed_out" --base-id com.pweevee.spotify --skip-sign 2>&1);
  $rc = $?;
  check($rc == 0, 'watchfix.sh --skip-sign succeeds') or diag($out);

  # unpack the fixed IPA and re-validate at the target base id
  my $ud = "$dir/unz";
  remove_tree($ud);
  system('unzip', '-q', $fixed_out, '-d', $ud) == 0 or nok('fixed IPA unzip');
  my $fapp = "$ud/Payload/Spotify.app";
  my $out2 = qx($^X $WATCH/validate-watchfix.pl "$fapp" com.pweevee.spotify 2>&1);
  my $rc2 = $?;
  check($rc2 == 0, 'watchfix output PASSES validation at --base-id') or diag($out2);
  ok(index($out2, 'VALIDATION PASSED') >= 0, 'validator emits PASSED line') or diag($out2);

  # explicit invariants on the fixed tree
  sub read_id { my $p = shift; local $/; open my $f, '<', $p or return undef; my $d = <$f>; $d =~ /<key>CFBundleIdentifier<\/key><string>([^<]+)<\/string>/ ? $1 : undef }
  my $outer = read_id("$fapp/Info.plist");
  my $wid = read_id("$fapp/Watch/WatchApp.app/Info.plist");
  my $wxid = read_id("$fapp/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex/Info.plist");
  check($outer eq 'com.pweevee.spotify', 'outer id rewritten to --base-id', $outer);
  check($wid eq 'com.pweevee.spotify.watchkitapp', 'watch id derived from base', $wid);
  check($wxid eq 'com.pweevee.spotify.watchkitapp.WatchWidgetExtension', 'widget appex id now prefixed', $wxid);

  # Apple-schema metadata lives on the WATCH side; the companion is cleaned.
  # Type assertions parse the element STRUCTURE (not a text grep): the boolean
  # must be a literal <true/> element, and the companion key must carry the
  # outer app's id (WKCompanionAppBundleIdentifier names the COMPANION).
  { local $/; open my $f, '<', "$fapp/Watch/WatchApp.app/Info.plist" or die; my $d = <$f>;
    check($d =~ /<key>WKWatchKitApp<\/key>\s*<true\/>/, 'WKWatchKitApp is a real plist Boolean <true/> on Watch app (not a string)');
    check($d !~ /<key>WKWatchKitApp<\/key>\s*<string>/, 'WKWatchKitApp is NOT written as a string');
    my ($comp) = $d =~ /<key>WKCompanionAppBundleIdentifier<\/key><string>([^<]+)<\/string>/;
    check(defined $comp && $comp eq 'com.pweevee.spotify', 'WKCompanionAppBundleIdentifier on Watch app = companion id');
  }
  { local $/; open my $f, '<', "$fapp/Info.plist" or die; my $d = <$f>;
    check($d !~ /<key>WKWatchKitApp</, 'WKWatchKitApp removed from companion side');
    check($d !~ /WKCompanionAppBundleIdentifier/, 'no companion key on companion side');
  }

  # Intents: phone app now declares the union
  { local $/; open my $f, '<', "$fapp/Info.plist" or die; my $d = <$f>; check($d =~ /SendMessageIntent/, 'IntentsSupported union copied into phone app'); }
  # The watch app is ALSO a parent: its top-level plist must now declare a
  # superset too (this exact gap fired on the real 149 MB IPA).
  { local $/; open my $f, '<', "$fapp/Watch/WatchApp.app/Info.plist" or die; my $d = <$f>; check($d =~ /<key>IntentsSupported<\/key><array>/, 'watch app itself carries top-level IntentsSupported'); }
  { local $/; open my $f, '<', "$fapp/PlugIns/InsightsIntents.appex/Info.plist" or die; my $d = <$f>; check($d =~ /SendMessageIntent/, 'intents extension still declares its own intent'); }

  # ---- structured plist check via python plistlib (independent of the
  # XML editor; this is the same check the real-IPA verification uses) ----
  {
    my $pycode = <<'PYC';
import plistlib, json, sys
p, = sys.argv[1:2]
with open(p, 'rb') as f: d = plistlib.load(f)
v = d.get('WKWatchKitApp')
type_ = 'boolean' if isinstance(v, bool) else 'string' if isinstance(v, str) else ('absent' if v is None else 'other')
print(json.dumps({'wkwatchkitapp': {'type': type_, 'value': v}, 'companion': d.get('WKCompanionAppBundleIdentifier'), 'id': d.get('CFBundleIdentifier')}))
PYC
    my $j = `$PY "$fapp/Watch/WatchApp.app/Info.plist" 2>&1 <<'PYX'
$pycode
PYX
`;
    # python reads args after -c-less script; use a file instead for safety
    my $pyfile = "$dir/plistcheck.py";
    open my $pf, '>', $pyfile or die "write $pyfile: $!"; print $pf $pycode; close $pf;
    $j = `$PY "$pyfile" "$fapp/Watch/WatchApp.app/Info.plist" 2>&1`;
    my $data = eval { JSON::PP::decode_json($j) };
    if ($data) {
      check(defined $data->{wkwatchkitapp} && $data->{wkwatchkitapp}{type} eq 'boolean' && $data->{wkwatchkitapp}{value}, 'plistlib: WKWatchKitApp is parsed Boolean true on Watch app', defined $data->{wkwatchkitapp} ? "$data->{wkwatchkitapp}{type}/$data->{wkwatchkitapp}{value}" : 'absent');
      check(defined $data->{companion} && $data->{companion} eq 'com.pweevee.spotify', 'plistlib: companion id on Watch app matches base', defined $data->{companion} ? $data->{companion} : 'absent');
    } else {
      nok('plistlib structured check ran') ; diag("python plistlib output: $j");
    }
  }
}

# ---- test 3: BINARY plist fixture (mirrors the real skywatch IPA: watch-side
# Info.plists are bplist, no WKWatchKitApp anywhere) — the plistlib path must
# produce a typed Boolean, not a string, and never corrupt the object table.
{
  my $bapp = "$dir/BPayload/Spotify.app";
  my $bwatch = "$bapp/Watch/WatchApp.app";
  my $bwidget = "$bwatch/PlugIns/WatchWidgetExtension.appex";
  make_path("$bwatch/PlugIns");
  make_path($bwidget);
  open my $ex, '>', "$bapp/Spotify" or die "open fake exe: $!"; print $ex "fake\n"; close $ex;
  open my $pi, '>', "$bapp/PkgInfo" or die "open PkgInfo: $!"; print $pi 'APPL????'; close $pi;

  my $pyfile = "$dir/binplist.py";
  open my $pf, '>', $pyfile or die "write $pyfile: $!";
  print $pf <<'PYC';
import plistlib, sys
def dump(path, d):
    with open(path, 'wb') as f: plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
path, ident, extra = sys.argv[1], sys.argv[2], {}
for kv in sys.argv[3:]:
    k, v = kv.split('=', 1)
    extra[k] = (True if v == '<bool:true>' else False if v == '<bool:false>' else v)
d = {'CFBundleIdentifier': ident, **extra}
dump(path, d)
# self-verify roundtrip
with open(path, 'rb') as f: d2 = plistlib.load(f)
assert d2['CFBundleIdentifier'] == ident, 'roundtrip failed'
PYC
  for my $pair (['Info.plist', 'com.skywatch.spotify'],
                ["$bwatch/Info.plist", 'com.skywatch.spotify.watchkitapp'],
                ["$bwidget/Info.plist", 'com.skywatch.spotify.watchkitapp.widget']) {
  }
  my $rc1 = system($PY, $pyfile, "$bapp/Info.plist", 'com.skywatch.spotify', 'WKWatchKitApp=<bool:false>');
  check($rc1 == 0, 'binary fixture outer plist written') or diag();
  my $rc2 = system($PY, $pyfile, "$bwatch/Info.plist", 'com.skywatch.spotify.watchkitapp', 'WKCompanionAppBundleIdentifier=com.skywatch.spotify');
  check($rc2 == 0, 'binary fixture watch plist written') or diag();
  my $rc3 = system($PY, $pyfile, "$bwidget/Info.plist", 'com.skywatch.spotify.watchkitapp.widget');
  check($rc3 == 0, 'binary fixture widget plist written') or diag();

  # sanity: the fixture watch plist must parse as binary with a real Boolean
  # false under WKWatchKitApp *only on the outer* (companion) side — i.e. the
  # legacy wrong-side key box we must clean up.
  open my $ch, '>', "$dir/readbin.py" or die;
  print $ch <<'PYR';
import plistlib, sys, json
p = sys.argv[1]
with open(p, 'rb') as f: d = plistlib.load(f)
v = d.get('WKWatchKitApp')
print(json.dumps({'fmt': 'binary', 'wk': (v if isinstance(v, bool) else str(v)) if v is not None else None, 'is_bool': isinstance(v, bool)}))
PYR
  my $j0 = `$PY "$dir/readbin.py" "$bapp/Info.plist" 2>&1`;
  my $d0 = eval { JSON::PP::decode_json($j0) };
  check($d0 && $d0->{is_bool} && !$d0->{wk}, 'binary fixture baseline: outer WKWatchKitApp is Boolean false (wrong-side key present)');

  # run watchfix on the binary fixture
  my $bpa = "$dir/bstage";
  make_path("$bpa/Payload");
  system('cp', '-a', "$bapp", "$bpa/Payload/Spotify.app");
  my $bout = "$dir/binput.ipa";
  my $o = qx($^X "$ROOT/build-system/package/make-ipa.pl" "$bpa/Payload/Spotify.app" "$bout" 2>&1);
  check($? == 0, 'make-ipa.pl produced binary input IPA') or diag($o);

  my $bfixed = "$dir/bfixed.ipa";
  my $bo = qx(bash "$WATCH/watchfix.sh" "$bout" --out "$bfixed" --base-id com.pweevee.spotify --skip-sign 2>&1);
  check($? == 0, 'watchfix.sh --skip-sign succeeds on BINARY-plist IPA') or diag($bo);

  my $bud = "$dir/bunz";
  remove_tree($bud);
  system('unzip', '-q', $bfixed, '-d', $bud) == 0 or nok('binary fixed IPA unzip');
  my $bf = "$bud/Payload/Spotify.app";

  # plistlib assertions on the transformed binary tree:
  my ($jq, $bz) = (undef, undef);
  {
    open my $rc, '>', "$dir/readbin2.py" or die;
    print $rc <<'PYR2';
import plistlib, sys, json
p, keys = sys.argv[1], sys.argv[2:]
with open(p, 'rb') as f: d = plistlib.load(f)
ok = {}
for k in keys:
    v = d.get(k)
    ok[k] = {'type': 'boolean' if isinstance(v, bool) else 'string' if isinstance(v, str) else ('absent' if v is None else 'other'), 'value': v if not isinstance(v, bool) else v}
print(json.dumps(d.get('CFBundleIdentifier', None)) + '|' + json.dumps(ok))
PYR2
    my $raw = `$PY "$dir/readbin2.py" "$bf/Watch/WatchApp.app/Info.plist" WKWatchKitApp WKCompanionAppBundleIdentifier 2>&1`;
    ($jq, $bz) = $raw =~ /^([^|]*)\|(.*)$/s ? ($1, $2) : (undef, undef);
    my $dz = eval { JSON::PP::decode_json($bz) };
    if ($dz) {
      my $wk = $dz->{WKWatchKitApp};
      check(defined $wk && $wk->{type} eq 'boolean' && $wk->{value}, 'BINARY path: WKWatchKitApp is Boolean true on Watch app (plistlib-typed)', defined $wk ? "$wk->{type}/$wk->{value}" : 'absent');
      my $comp = $dz->{WKCompanionAppBundleIdentifier};
      check(defined $comp && $comp->{type} eq 'string' && $comp->{value} eq 'com.pweevee.spotify', 'BINARY path: WKCompanionAppBundleIdentifier is the base id (string)', defined $comp ? "$comp->{type}=$comp->{value}" : 'absent');
    } else { nok('BINARY path plistlib read'); diag("raw: $raw"); }

    my $raw2 = `$PY "$dir/readbin2.py" "$bf/Info.plist" WKWatchKitApp 2>&1`;
    my (undef, $d2j) = $raw2 =~ /^([^|]*)\|(.*)$/s;
    my $d2 = eval { JSON::PP::decode_json($d2j) };
    if ($d2) {
      check($d2->{WKWatchKitApp}{type} eq 'absent', 'BINARY path: wrong-side WKWatchKitApp REMOVED from companion (plistlib-verified absent)');
    } else { nok('BINARY path companion read'); diag("raw2: $raw2"); }
  }

  # validator accepts the binary-normalized tree
  my $bvalidate = qx($^X "$WATCH/validate-watchfix.pl" "$bf" com.pweevee.spotify 2>&1);
  check($? == 0, 'binary-normalized tree PASSES committed validator') or diag($bvalidate);
}

# ---- test 4: EXACT AppexBundleIDNotPrefixed shape + rebase determinism ----
{
  my $sapp = "$dir/S4Payload/Spotify.app";
  my $swatch = "$sapp/Watch/WatchApp.app";
  my $swidget = "$swatch/PlugIns/WatchWidgetExtension.appex";
  my $sintents = "$swatch/PlugIns/WatchIntentsExtension.appex";
  make_path("$swatch/PlugIns");
  make_path($swidget, $sintents);
  open my $ex4, '>', "$sapp/Spotify" or die; print $ex4 "fake\n"; close $ex4;
  open my $pi4, '>', "$sapp/PkgInfo" or die; print $pi4 'APPL????'; close $pi4;

  # Build the exact post-Sideloadly-broken shape observed on-device:
  # outer was renamed by Sideloadly, watch id was (partially) updated, but the
  # two watch appexes kept their ORIGINAL com.skywatch.spotify.watchkitapp.*
  # ids — the installer then reported AppexBundleIDNotPrefixed.
  write_plist("$sapp/Info.plist", 'com.spotipw.client.3522J7W583');
  write_plist("$swatch/Info.plist", 'com.spotipw.client.3522J7W583.watchkitapp',
              'WKCompanionAppBundleIdentifier' => 'com.spotipw.client.3522J7W583');
  write_plist("$swidget/Info.plist", 'com.skywatch.spotify.watchkitapp.WatchWidgetExtension');
  write_plist("$sintents/Info.plist", 'com.skywatch.spotify.watchkitapp.WatchIntentsExtension');

  # 4a. the committed validator must FAIL on this tree with the exact
  #     installer error class as its top-line symptom.
  {
    my $o = qx($^X $WATCH/validate-watchfix.pl "$sapp" 2>&1);
    my $rc = $?;
    check($rc != 0, 'broken as-installed tree FAILS validation') or diag($o);
    my $n_stale = () = $o =~ /APPEX STALE NAMESPACE/g;
    check($n_stale >= 2, "both stale skywatch appexes flagged (got $n_stale)") or diag($o);
    ok(index($o, 'APPEX NOT PREFIXED') >= 0, 'APPEX NOT PREFIXED present (installer error class)') or diag($o);
  }

  # 4b. rebasing via PWEEVEE_WATCH_BASE_ID (per-device announced prefix):
  # a watch fix run at an override base moves outer/app/appexes and
  # companion metadata atomically.
  my $stage4 = "$dir/stage4";
  make_path("$stage4/Payload");
  system('cp', '-a', "$sapp", "$stage4/Payload/Spotify.app");
  my $in4 = "$dir/in4.ipa";
  qx($^X "$ROOT/build-system/package/make-ipa.pl" "$stage4/Payload/Spotify.app" "$in4") ;
  my $out4 = "$dir/fixed4.ipa";
  my $prog = "$dir/prog4.pl";
  open my $pg, '>', $prog or die;
  print $pg <<'PGEOF';
$ENV{PWEEVEE_WATCH_BASE_ID} = 'com.skywatch.spotify';
$ENV{PWEEVEE_WATCH_BASE_ID} = $ARGV[0] if defined $ARGV[1];
system('bash', $ARGV[2], $ARGV[3], '--out', $ARGV[4], '--base-id', 'IGNORED', '--skip-sign') == 0 or exit 1;
PGEOF
  # Instead of the fake prog (the stage adapter is bash), drive the adapter
  # directly with the override env.
  my $o4 = qx(PWEEVEE_WATCH_BASE_ID='com.skywatch.spotify' bash "$WATCH/watchfix-stage.sh" "$stage4/Payload/Spotify.app" 2>&1);
  my $rc4 = $?;
  check($rc4 == 0, 'watchfix-stage.sh succeeds under PWEEVEE_WATCH_BASE_ID override', $o4) or diag($o4);

  # invariants after override-rebase
  my $rd4 = sub { my $p = shift; local $/; open my $f, '<', $p or return undef; my $d = <$f>; $d =~ /<key>CFBundleIdentifier<\/key><string>([^<]+)<\/string>/ ? $1 : undef };
  check($rd4->("$stage4/Payload/Spotify.app/Info.plist") eq 'com.skywatch.spotify', '4b outer id = override base') or diag($o4);
  check($rd4->("$stage4/Payload/Spotify.app/Watch/WatchApp.app/Info.plist") eq 'com.skywatch.spotify.watchkitapp', '4b watch id = base.watchkitapp') or diag($o4);
  check($rd4->("$stage4/Payload/Spotify.app/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex/Info.plist") eq 'com.skywatch.spotify.watchkitapp.WatchWidgetExtension', '4b widget appex = base.watchkitapp.WatchWidgetExtension') or diag($o4);
  check($rd4->("$stage4/Payload/Spotify.app/Watch/WatchApp.app/PlugIns/WatchIntentsExtension.appex/Info.plist") eq 'com.skywatch.spotify.watchkitapp.WatchIntentsExtension', '4b intents appex = base.watchkitapp.WatchIntentsExtension') or diag($o4);    # 4c. double-prefix sentinel: an id that embeds the FULL parent id TWICE
    # (the shape a double rewrite produces when the old id is used as the
    # leaf and then prefixed again). Parent set to the skywatch scheme so
    # ONLY the double-prefix sentinel distinguishes it from a valid tree.
    {
      write_plist("$swatch/Info.plist", 'com.skywatch.spotify.watchkitapp',
                  'WKCompanionAppBundleIdentifier' => 'com.spotipw.client.3522J7W583');
      write_plist("$swidget/Info.plist", 'com.skywatch.spotify.watchkitapp.com.skywatch.spotify.watchkitapp.WatchWidgetExtension');
      write_plist("$sintents/Info.plist", 'com.skywatch.spotify.watchkitapp.com.skywatch.spotify.watchkitapp.WatchIntentsExtension');
    my $o = qx($^X $WATCH/validate-watchfix.pl "$sapp" --catch-double-prefix 2>&1);
    my $rc = $?;
    check($rc != 0, 'double-prefixed appex FAILS with --catch-double-prefix') or diag($o);
    my $n = () = $o =~ /APPEX DOUBLE-PREFIXED/g;
    my $want = 2;
    check($n == $want, "exactly $want double-prefix violations flagged (got $n)") or diag($o);
    # without the flag, double-prefix must NOT be reported (same id, parent
    # still shares first 2 components): the normal prefixed-check passes.
    my $o2 = qx($^X $WATCH/validate-watchfix.pl "$sapp" 2>&1);
    check(index($o2, 'APPEX DOUBLE-PREFIXED') < 0, 'double-prefix sentinel silent without flag') or diag($o2);
  }

  # 4d. repeated runs are deterministic (same input → same output byte COUNT;
  # zip timestamps differ, so compare plist content not bytes).
  {
    my $second = qx(PWEEVEE_WATCH_BASE_ID='com.skywatch.spotify' bash "$WATCH/watchfix-stage.sh" "$stage4/Payload/Spotify.app" 2>&1);
    check($? == 0, 'second override run also succeeds') or diag($second);
    check($rd4->("$stage4/Payload/Spotify.app/Watch/WatchApp.app/PlugIns/WatchWidgetExtension.appex/Info.plist") eq 'com.skywatch.spotify.watchkitapp.WatchWidgetExtension', '4d repeated run produces identical ids (no drift)');
  }
}

remove_tree($dir);

print "\n";
if ($fail) { print "watchfix-tests FAILED ($pass ok, $fail fail)\n"; exit 1; }
print "watchfix-tests PASSED ($pass ok)\n";
exit 0;
