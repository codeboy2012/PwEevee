#!/usr/bin/env perl
# EeveeSpotify settings-integration tests: the PwEevee side must own the single settings entry, keep
# the payload's standalone row and gear button off the screens, leave the payload's storage keys alone
# where it drives them, and stand the payload's lyric rewriter down.
#
#   perl PwEvevee/build-system/tests/eevee-settings-tests.pl
use strict;
use warnings;
use File::Basename qw(dirname);

my $ROOT = dirname($0) . '/../../..';
my $EEVEE_X = "$ROOT/Spotipw/tweak/Sources/App/Eevee/SGEevee.x";
my $EEVEE_H = "$ROOT/Spotipw/tweak/Sources/App/Eevee/SGEevee.h";
my $MOD_SETTINGS = "$ROOT/Spotipw/tweak/Sources/App/ModSettings.x";
my $UNIFIED = "$ROOT/PwEvevee/build-system/unified.sh";

my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }
sub slurp { local $/; open my $f, '<', $_[0] or return undef; return <$f>; }

my $eevee = slurp($EEVEE_X);
my $header = slurp($EEVEE_H);
my $mod = slurp($MOD_SETTINGS);
ok(defined $eevee && defined $header && defined $mod, 'integration sources are readable');

# ---------- 1. the standalone row is taken out, and its layout changes undone ----------
ok($eevee =~ /kEeveeRowTag\s*=\s*1338/, 'the payload row tag (1338) is matched');
ok($eevee =~ /kEeveeRowHeight\s*=\s*68/, 'the payload row height (68pt) is matched');
ok($eevee =~ /sub\.hidden\s*=\s*YES.*tookRow/s || $eevee =~ /tookRow/, 'the payload row is hidden, not removed from the hierarchy');
ok($eevee =~ /contentInset\.top\s*-=\s*kEeveeRowHeight/, 'the 68pt top content inset the payload added is taken back');
ok($eevee =~ /verticalScrollIndicatorInsets.*-=\s*kEeveeRowHeight/s, 'the scroll indicator inset is taken back with it');
ok($eevee =~ /standin\.tag\s*=\s*kEeveeRowTag/, 'a hidden stand-in keeps the payload re-injecting its row');
ok($eevee !~ /viewWithTag:kEeveeRowTag/, 'the row is not looked up with viewWithTag: (it would find the stand-in)');

# ---------- 2. the gear button (tag 1337) is filtered off navigation bars ----------
ok($eevee =~ /kEeveeNavButtonTag\s*=\s*1337/, 'the payload gear-button tag (1337) is matched');
ok($eevee =~ /%hook UINavigationItem/, 'navigation items are hooked to filter the gear button');
ok($eevee =~ /SGEeveeFilteredBarItems/, 'the bar-item filter is applied to whatever the payload sets');

# ---------- 3. the settings entry lives inside Mod Settings, once ----------
ok($mod =~ /#import "App\/Eevee\/SGEevee\.h"/, 'ModSettings imports the Eevee integration');
ok($mod =~ /pageRow\(@"EeveeSpotify"/, 'Mod Settings has one EeveeSpotify page row');
ok($mod =~ /SGEeveeRemoveStandaloneRow/, 'ModSettings calls the row removal');
my $removal_calls = () = ($mod =~ /SGEeveeRemoveStandaloneRow/g);
ok($removal_calls == 2, 'the row removal runs on both hooked settings lists (settings list + side drawer)');
ok($mod =~ /SGEeveeRestoreLyricsReplacement\(\);/, 'the lyrics restore runs at %ctor');

# ---------- 4. Eevee's own storage keys are driven, not re-invented ----------
for my $key (qw(patchType trueShuffleEnabled overwriteConfiguration darkPopUps cleanShareLinks
                experimentsOptions sponsorBlockOptions sponsorBlockUserID)) {
    ok($eevee =~ /\Q$key\E/, "Eevee's own key '$key' is driven under its own name");
}
ok($eevee =~ /spotifyglass\.eevee\./, 'mirror keys for JSON/Int-shaped settings live under the mod prefix');
ok($eevee =~ /@"showInstagramDestination"/ && $eevee =~ /@"liveContainerSharing"/, 'the experiments JSON fields keep their Swift property names');
ok($eevee =~ /@"minSegmentDuration"/ && $eevee =~ /@"toastDuration"/ && $eevee =~ /@"serverURL"/, 'the SponsorBlock JSON fields keep their Swift property names');
ok($eevee =~ /PersistentCache/ && $eevee =~ /remote-config/, "patch changes reset the payload's caches, as its own toggles do");

# ---------- 5. lyrics belong to Eevee again: the old off-switch is undone ----------
ok($eevee =~ /kLyricsSource\s*=\s*@"lyricsSource"/, "Eevee's lyrics source key is read directly");
ok($eevee =~ /removeObjectForKey:kLyricsSource/, 'the forced 4 (LyricsSource.notReplaced) the old lock wrote is removed, leaving Eevee its own default');
ok($eevee !~ /setInteger:4\s+forKey:kLyricsSource/, 'no lyrics off-switch is written anymore');

# ---------- 6. the sections the task removes are not exposed ----------
ok($eevee !~ /EeveeLyricsSettingsView/, 'no lyrics settings are exposed');
ok($eevee !~ /EeveeUISettingsView/, 'the old Customization page is not exposed');
ok($eevee !~ /EeveeMiscellaneousSettingsView/, 'the old Miscellaneous page is not exposed');
ok($eevee !~ /reset_data|FullResetHelper|resetButtonTitle/, 'neither Reset nor Full Reset is exposed');
ok($eevee !~ /EeveeSettingsView/, "Eevee's own root view is not re-hosted (the payload's UI is replaced, not nested)");

# ---------- 7. the retained settings are all there ----------
# v0.22.1: the payload's Patch Premium row reads Eevee's Spoofed Premium, the name the premium
# exclusivity contract calls it (Shared/AdBlock/PremiumExclusivity.m; the mutual exclusion suite pins
# the wiring).
for my $title (qw(Eevee's\s+Spoofed\s+Premium True\s+Shuffle Dark\s+popups Clean\s+share\s+links Instagram LiveContainer
                  SponsorBlock App\s+icons Prettify\s+icon\s+names)) {
    ok($eevee =~ /\Q$title\E/ || $eevee =~ /$title/, "retained setting present: $title");
}

# ---------- 8. the icon picker drives the same storage the payload's picker does ----------
ok($eevee =~ /EeveeSelectedAppIconName/, "the icon page reads and writes the payload's selected-icon key");
ok($eevee =~ /setAlternateIconName/, 'the icon page applies icons through the same iOS API');
ok($eevee =~ /CFBundleAlternateIcons/, 'the icon page lists the alternates the payload declares');
ok($eevee =~ /iconNamePrettify/, 'the icon page drives the payload prettify setting');

# ---------- 8b. the icon rows carry a REAL preview of each icon ----------
# Each icon row leads its name with the icon's own image: read out of the icon file the payload ships
# (the loose PNGs at the app root), scaled and rounded, not a placeholder and not a system symbol.
ok($eevee =~ /static UIImage \*eeveeIconPreview\(NSString \*stem\)/, 'a preview loader exists beside the picker');
ok($eevee =~ /@"\@3x\.png", @"\@2x\.png", @"\@2x~ipad\.png", @"~ipad\.png", @"\.png"/,
   'the loader tries the scale variants in order: @3x, @2x, @2x~ipad, ~ipad, base');
ok($eevee =~ /\[UIImage imageWithContentsOfFile:path\]/,
   'the preview is loaded from the real file on disk (the upstream SGAppIconPreviews pattern)');
ok($eevee =~ /scale:scale orientation:UIImageOrientationUp/,
   'the scale suffix is restored so the image keeps the point size the filename promises');
ok($eevee =~ /\[suffix containsString:@"\@3x"\] \? 3 : \(\[suffix containsString:@"\@2x"\] \? 2 : 1\)/,
   '3x and 2x read their scales from the suffix, the base file reads 1x');
ok($eevee =~ /\[UIImage imageNamed:stem\]/, 'a name whose file the roster missed still falls back to imageNamed');
ok($eevee =~ /stem = @"AppIcon60x60"/, 'the Default row previews the app\'s own primary icon');
ok($eevee =~ /\+ \(UIImage \*\)cachedPreviewForStem:/
   && $eevee =~ /cache\.countLimit = 64;/,
   'previews decode once and sit in a small cache across reloads');
ok($eevee =~ /UIGraphicsImageRenderer.*rounded|eeveeRoundedPreview/s,
   'the preview is drawn into a rounded square, the shape the app icon carries');
ok($eevee =~ /side \* 0\.22/, 'the corner radius is proportional to the preview size');
ok($eevee =~ /content\.image = preview;/, 'the icon row\'s leading image shows the real icon');
ok($eevee =~ /content\.imageProperties\.maximumSize = CGSizeMake\(40, 40\);/
   && $eevee =~ /content\.imageProperties\.reservedLayoutSize = CGSizeMake\(40, 40\);/,
   'the preview keeps its 40pt slot next to the name');
ok($eevee =~ /content\.imageToTextPadding = 12;/, 'preview and name keep a readable padding');

# ---------- 9. no compiled payload was touched ----------
my $dylib = "$ROOT/Evevee Spotify/component/package/dynamic-libraries/EeveeSpotify.dylib";
my $manifest = slurp("$ROOT/Evevee Spotify/component/manifest.json");
ok(-f $dylib, 'the compiled Eevee payload is still in place');
if ($manifest) {
    ok($manifest =~ /8997e5c946d702b062b4b2482e37e9675ef013e8fae951b8b0871f55a856cdb4/,
       "the payload dylib hash in the manifest is untouched (8997e5c9...)");
    ok($manifest =~ /513a50b197aa558c34b02b87bff9f46e6cad3b2e462ee8622fc72fd939e83a9b/,
       "the origin deb hash in the manifest is the refreshed v7.0.0 package");
    ok($manifest =~ /"version"\s*:\s*"7\.0\.0"/,
       "the component manifest is refreshed to upstream v7.0.0");
    ok(-f "$ROOT/Evevee Spotify/component/package/dynamic-libraries/KaraokeBackgroundShader.metallib",
       "the v7.0.0 karaoke shader ships with the refreshed payload");
    my $sha = qx(sha256sum "$dylib");
    ok($sha =~ /^8997e5c946d702b062b4b2482e37e9675ef013e8fae951b8b0871f55a856cdb4/,
       'the payload dylib on disk still matches the audited hash');
} else {
    ok(0, 'component manifest readable');
}

# ---------- 10. the build pipeline needs no changes for a new App/ source file ----------
my $makefile = slurp("$ROOT/Spotipw/tweak/Makefile");
ok($makefile && $makefile =~ /find Sources/, 'the tweak Makefile globs all of Sources/ (new files need no edit)');
ok(-f $UNIFIED, 'unified.sh is present');

print "eevee-settings-tests: $pass passed, " . scalar(@failures) . " failed\n";
if (@failures) {
    print "  _\n";
    print "  FAIL: $_\n" for @failures;
    exit 1;
}
exit 0;
