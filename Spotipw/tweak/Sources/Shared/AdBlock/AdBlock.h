// Spoof Premium, from EeveeSpotify's layers as Spot.pw shipped them. It rewrites the product state
// and remote config as they arrive (Premium.m) so the client sees a Premium account, keeps the
// crossfade and automix working (Crossfade.x), enables shuffle and repeat in radio/autoplay
// (RadioModes.m) and keeps the session alive when the server disagrees (AdNetwork.x). This tree
// carries only the premium part: the ad-blocking switches (Hide ads, Hide upsells, the search video
// carousel) and the counters stay in upstream Spot.pw/Taurus and are not part of the unified build.
//
// The one switch is mutually exclusive with EeveeSpotify's premium patching (App/Eevee/SGEevee.x):
// while one is on the other is written off, and the launch-time resolver settles a state where both
// are stored on (SGPremiumResolveConflict, whose policy is documented next to its implementation).
#import <UIKit/UIKit.h>

// Spot.pw's switch is a plain Bool under this key. Eevee's own stored key is `patchType`
// (Int: 1 disabled, 2 requests), driven by App/Eevee/SGEevee.x as its own page always has.
#define SGKeyFakePremium @"spotifyglass.adblock.premium"

// What a switch turning Spoof Premium on is told first.
extern NSString *const SGFakePremiumWarning;

// Premium.m: the body of v1/customize, or the bootstrap message that wraps one, rewritten to a
// Premium account's. nil when the bytes do not parse.
NSData *SGPatchCustomize(NSData *body);
NSData *SGPatchBootstrap(NSData *body);

// The two premium spoofs, as the exclusivity policy behind both pages. Turning one on writes the
// other off; turning the active one off leaves both off. Implemented in PremiumExclusivity.m, which
// drives Eevee's patching key through SGEeveeSetPatchingPrivate (implemented in App/Eevee/SGEevee.x
// — an extern across the layers, not an import: check-layers.sh allows the link but not the import).
BOOL SGPremiumSpoofOn(void);
void SGPremiumSpoofSetOn(BOOL on);
BOOL SGEeveePremiumOn(void);
void SGEeveePremiumSetOn(BOOL on);

// At launch, a state where both are stored on (legacy installs, restores, hand edits) is settled
// before the hooks read the switches: Spot.pw's Spoof Premium keeps its value and Eevee's patching
// is written off. The write persists, so it happens once; the hook files read the resolved state.
void SGPremiumResolveConflict(void);
