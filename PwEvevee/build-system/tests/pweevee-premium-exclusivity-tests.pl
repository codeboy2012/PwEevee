#!/usr/bin/env perl
# Premium-spoof exclusivity tests: Spot.pw's Spoof Premium and Eevee's Spoofed Premium must be two
# writable, mutually exclusive settings — turning either on writes the other off, turning the active
# one off leaves both off, the off state persists (a stored NO wins the default-on), and a launch
# that finds both stored on settles for Spot.pw's before the hook files read the switches. These are
# source-wiring checks; runtime behavior needs a device and stays with the report's limitations.
#
#   perl PwEvevee/build-system/tests/pweevee-premium-exclusivity-tests.pl
use strict;
use warnings;
use File::Basename qw(dirname);

my $ROOT = dirname($0) . '/../../..';
my $EXCL = "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/PremiumExclusivity.m";
my $ADBH = "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdBlock.h";
my $ADNET = "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdNetwork.x";
my $EEVEE = "$ROOT/Spotipw/tweak/Sources/App/Eevee/SGEevee.x";
my $MOD = "$ROOT/Spotipw/tweak/Sources/App/ModSettings.x";
my $MODPAGEH = "$ROOT/Spotipw/tweak/Sources/Settings/SGModPage.h";
my $MODPAGEM = "$ROOT/Spotipw/tweak/Sources/Settings/SGModPage.m";

my @failures;
my $pass = 0;
sub ok { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }
sub slurp { local $/; open my $f, '<', $_[0] or return undef; return <$f>; }

my ($excl, $adbh, $adnet, $eevee, $mod) = (slurp($EXCL), slurp($ADBH), slurp($ADNET), slurp($EEVEE), slurp($MOD));
my ($modpageh, $modpagem) = (slurp($MODPAGEH), slurp($MODPAGEM));
ok(defined $excl && defined $adbh && defined $adnet && defined $eevee && defined $mod,
   "exclusivity sources are readable");
ok(defined $modpageh && defined $modpagem, "the settings-page sources are readable");

# ---------- 1. the exclusivity policy is one module, with the documented legacy policy ----------
ok($excl =~ /void SGPremiumSpoofSetOn\(BOOL on\)/ && $excl =~ /void SGEeveePremiumSetOn\(BOOL on\)/,
   "both setters are implemented in one module");
ok($excl =~ /void SGPremiumResolveConflict\(void\)/, "a launch-time conflict resolver exists");
ok($excl =~ /Spot\.pw's Spoof Premium wins/ && $excl =~ /Eevee's patching is written off/,
   "the legacy-conflict policy is documented: Spot.pw keeps its value, Eevee is written off");
ok($excl =~ /SGEeveeSetPatchingPrivate/, "Eevee writes go through Eevee's own patching setter");
ok($excl !~ m{#import "App/}, "the policy module stays within the layers rule (no App import; extern only)");

# ---------- 2. off persists: a stored NO beats Eevee's default-on ----------
ok($excl =~ /setBool:on\s+forKey:SGKeyFakePremium/, "Spoof Premium off is a stored BOOL, not a key removal");
ok($excl =~ /SGSetEnabled\(SGKeyFakePremium,\s*NO\)/, "turning Eevee on stores an explicit NO for Spoof Premium");
ok($eevee =~ /integerValue\]\s*==\s*2\s*:\s*YES/ && $excl =~ /integerValue\]\s*==\s*2\s*:\s*YES/,
   "patchType semantics (1 disabled, 2 requests, unset = on) match on both sides that read it");

# ---------- 3. each setter disables the other when it turns its own side on ----------
ok($excl =~ /void SGPremiumSpoofSetOn\(BOOL on\)\s*\{[^}]*setBool[^}]*SGKeyFakePremium[^}]*if \(on\)\s*SGEeveeSetPatchingPrivate\(NO\);/s,
   "turning Spoof Premium on writes Eevee off");
ok($excl =~ /void SGEeveePremiumSetOn\(BOOL on\)\s*\{[^}]*SGEeveeSetPatchingPrivate\(on\);[^}]*if \(on\)\s*SGSetEnabled\(SGKeyFakePremium,\s*NO\);/s,
   "turning Eevee on writes Spoof Premium off");
ok($excl =~ /ResolveConflict[^;]*SGPremiumSpoofOn\(\)\s*\|\|\s*!SGEeveePremiumOn\(\)\s*\)\s*return;/s,
   "the resolver only acts on a stored both-on pair");
ok($excl =~ /ResolveConflict[^;]*SGEeveeSetPatchingPrivate\(NO\);\s*SGLog/s,
   "the resolver settles the conflict with the Eevee write and a log line");

# ---------- 4. the hook files read the resolved state ----------
ok($adnet =~ /SGPremiumResolveConflict\(\);\s*\n\s*premium = SGFlag\(SGKeyFakePremium,\s*YES\)/,
   "AdNetwork resolves the conflict before it reads the switch");

# ---------- 5. both settings rows are wired to the policy, not to raw keys alone ----------
ok($mod =~ /SGOptionRow\(@"Spoof Premium",\s*nil,\s*SGKeyFakePremium\)/, "Mod Settings carries Spot.pw's Spoof Premium row");
ok($mod =~ /spoofPremium\.defaultOn = YES;/, "Spoof Premium keeps its upstream default (on when unset)");
ok($mod =~ /spoofPremium\.warning = SGFakePremiumWarning;/, "Spoof Premium warns that it is untested and can force a logout");
ok($mod =~ /spoofPremium\.changed = \^\(BOOL on\) \{ SGPremiumSpoofSetOn\(on\); \};/,
   "the Spoof Premium row writes through the exclusivity setter");
ok($eevee =~ /SGSwitchRow\(@"Eevee's Spoofed Premium"/, "the Eevee page's row reads Eevee's Spoofed Premium");
ok($eevee !~ /SGSwitchRow\(@"Patch Premium"/, "the old Patch Premium label is gone from the row");
ok($eevee =~ /patching\.changed = \^\(BOOL on\) \{ SGEeveePremiumSetOn\(on\); \};/,
   "the Eevee row writes through the exclusivity setter");
ok($eevee =~ /%ctor \{[^}]*SGPremiumResolveConflict\(\);/s, "the Eevee integration also settles the conflict at launch");
ok($eevee =~ /void SGEeveeSetPatchingPrivate\(BOOL on\)\s*\{[^}]*eeveeSetPatching\(on\);/s,
   "the Eevee setter implementation takes the same path the page's switch does");

# ---------- 6. the trimmed feature: premium only, no ad-block surface ----------
ok($adbh =~ /#define SGKeyFakePremium @"spotifyglass\.adblock\.premium"/, "the switch keeps upstream's key");
ok($adbh !~ /SGKeyHideAds|SGKeyHideUpsells|SGKeyHideSearchVideos/, "the ad-block switches stay out of the unified build");
ok($adnet =~ /%hook SPTDataLoaderService/ && $adnet =~ /%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession/,
   "the premium rewrite hooks target the app's own delegates");
ok($adnet !~ /SPTCoreURLSessionDataDelegate/, "the C++ core ad path is not grafted");
ok($adnet !~ /SGStripFeed/, "the feed stripper stays out with its feature");
ok($adbh =~ /NSData \*SGPatchCustomize\(NSData \*body\);/ && $adbh =~ /NSData \*SGPatchBootstrap\(NSData \*body\);/,
   "the product-state rewrite API is declared");
ok(-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/Premium.m"
   && -e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/Crossfade.x"
   && -e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/RadioModes.m"
   && -e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/RadioModes.h",
   "the premium feature files are present");
ok(!-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdBlock.m"
   && !-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdBlockSettings.m"
   && !-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdHubs.x"
   && !-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdPopups.x"
   && !-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/AdServices.x"
   && !-e "$ROOT/Spotipw/tweak/Sources/Shared/AdBlock/Feeds.m",
   "the ad-block feature files stay out");

# ---------- 7. Eevee keeps its own page behaviour beyond the rename ----------
ok($eevee =~ /kPatchType = @"patchType"/, "the Eevee row still drives Eevee's own patchType key");
ok($eevee =~ /eeveeResetData/, "patch changes still reset the payload's caches");
ok($mod =~ /eevee\.value = \^NSString \* \{ return SGEeveePremiumOn\(\) \? @"On" : @"Off"; \};/,
   "the Mod Settings Eevee row reads the resolved state, not a stale mirror key");

# ---------- 8. the gray-out UI (Spot.pw's established disabled-row treatment) ----------
# The exclusion must not rest on the setters alone: whichever premium row the active one holds off
# is DRAWM disabled — Spot.pw's " (grayed out)" title suffix, grey labels, an untouchable switch —
# and re-enabled the moment the active one is flipped off, without matching the switch handlers.
ok($modpageh =~ /\@property \(nonatomic, copy\) BOOL \(\^enabled\)\(void\);/,
   "SGModRow carries an enabled block that grays and disables a switched row");
ok($modpageh =~ /\(grayed out\)/, "the enabled property documents the gray-out convention");
ok($modpagem =~ /BOOL rowEnabled = !row\.enabled \|\| row\.enabled\(\);/,
   "the page asks every switched row for its enabled state when it draws it");
ok($modpagem =~ /BOOL grayed = row\.key && !rowEnabled;/,
   "only switched rows gray out; page and value rows keep their face");
ok($modpagem =~ /grayed \? \[row\.title stringByAppendingString:@" \(grayed out\)"\]/,
   "the grayed row's title carries Spot.pw's \" (grayed out)\" suffix");
ok($modpagem =~ /if \(grayed\) content\.textProperties\.color = SGGrey\(\);/,
   "the grayed row's title goes grey, not merely dimmed");
ok($modpagem =~ /toggle\.enabled = !locked && !grayed;/
   && $modpagem =~ /toggle\.userInteractionEnabled = !locked && !grayed;/,
   "the grayed row's switch is disabled AND cannot take a tap"
);
ok($modpagem !~ /cell\.userInteractionEnabled/ || $modpagem =~ /toggle\.userInteractionEnabled/,
   "the lock-out lands on the switch, not on the row (the row keeps its tap path)");
ok($mod =~ /spoofPremium\.enabled = \^\{ return !SGEeveePremiumOn\(\); \};/,
   "Spot.pw's row grays out while Eevee's Spoofed Premium holds");
ok($eevee =~ /patching\.enabled = \^\{ return !SGFlag\(SGKeyFakePremium, YES\); \};/,
   "Eevee's row grays out while Spot.pw's Spoof Premium holds");
ok($modpagem =~ /\[self\.tableView reloadData\]/,
   "the flip path reloads the table, so a switch-off re-enables the grayed row right away");
ok($modpagem =~ /- \(void\)viewWillAppear.*\[self\.tableView reloadData\];/s,
   "a page pushed after the other side was switched off reloads its rows on appearance");

if (@failures) {
    printf STDERR "premium-exclusivity-tests: %d passed, %d FAILED\n", $pass, scalar(@failures);
    printf STDERR "  - %s\n", $_ for @failures;
    exit 1;
}
printf "premium-exclusivity-tests: %d passed, 0 failed\n", $pass;
exit 0;
