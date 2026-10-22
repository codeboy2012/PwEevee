// The premium-spoof exclusivity policy, in one place so both settings pages and the launch hooks
// hold the same rules:
//
//   * Turning Spot.pw's Spoof Premium on writes Eevee's Spoofed Premium off, and turning Eevee's
//     Spoofed Premium on writes Spoof Premium off (SGPremiumSpoofSetOn / SGEeveePremiumSetOn).
//     Disabling the active option leaves both off — nothing re-enables by itself.
//   * Every write is persisted, so the state the user last chose is what a restart finds.
//   * A launch that finds BOTH stored on (a legacy install of the standalone fork plus the old
//     Taurus tweak, an iCloud defaults restore, a hand edit) is settled by SGPremiumResolveConflict:
//     the deterministic policy is that Spot.pw's Spoof Premium wins and Eevee's patching is written
//     off. Spot.pw's switch is the original behavior this tree carried first and its stored (or
//     default-on) value is what the resolver keeps, so an upgrading install keeps the behavior it
//     had; the Eevee write persists, so the resolution happens once and not at every launch.
//
// Eevee's own stored key is `patchType` (Int: 1 disabled, 2 requests, default: patch — see
// App/Eevee/SGEevee.x, whose eeveePatchingOn reads the same default). Reading it here duplicates two
// lines of Eevee's semantics on purpose: the layers rule keeps Shared/AdBlock from importing App/,
// and the exclusivity policy must not depend on a settings page being built first.
#import "Core/SGCore.h"
#import "AdBlock.h"

// Implemented in App/Eevee/SGEevee.x next to the page's own patching switch, so the exclusivity
// writes go through Eevee's own setter (setInteger + the patch-data reset Eevee does after it).
extern void SGEeveeSetPatchingPrivate(BOOL on);

NSString *const SGFakePremiumWarning = @"This is the part of EeveeSpotify Spotify's takedown went after, and it has not been tested here. It can end in a forced logout or worse for the account. A Premium account gains nothing from it.";

BOOL SGPremiumSpoofOn(void) {
    return SGFlag(SGKeyFakePremium, YES);
}

void SGPremiumSpoofSetOn(BOOL on) {
    // A real BOOL write, not a key removal: the row's unset value is default-on, and "off" must stay
    // off with that default.
    [NSUserDefaults.standardUserDefaults setBool:on forKey:SGKeyFakePremium];
    if (on) SGEeveeSetPatchingPrivate(NO);
}

BOOL SGEeveePremiumOn(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:@"patchType"];
    return value ? [value integerValue] == 2 : YES;
}

void SGEeveePremiumSetOn(BOOL on) {
    SGEeveeSetPatchingPrivate(on);
    if (on) SGSetEnabled(SGKeyFakePremium, NO);
}

void SGPremiumResolveConflict(void) {
    if (!SGPremiumSpoofOn() || !SGEeveePremiumOn()) return;
    SGEeveeSetPatchingPrivate(NO);
    SGLog(@"premium exclusivity: both spoofs were on; Spot.pw's Spoof Premium kept, Eevee's written off");
}
