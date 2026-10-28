// EeveeSpotify's layers, ported, at the top of the Premium, ads & privacy page. Hide ads and Hide
// upsells are on by default; Hide ads keeps the ad services from starting (AdServices.x), takes ad
// components out of Home and Search before they render (AdHubs.x, Feeds.m), and answers their
// requests empty (AdNetwork.x). Hide upsells drops Premium prompts (AdPopups.x, AdServices.x) and
// forces the flags that show them off (AdBlock.m, through Flags.x). Spoof Premium rewrites product
// state and remote config as they arrive (Premium.m), crossfade and automix included (Crossfade.x),
// enables shuffle and repeat in radio/autoplay (RadioModes.m), and keeps the session alive when the
// server disagrees (AdNetwork.x). Hide the video carousel in Search forces its flag off (AdBlock.m,
// through Flags.x).
#import <UIKit/UIKit.h>

#define SGKeyHideAds @"spotifyglass.adblock.ads"
#define SGKeyHideUpsells @"spotifyglass.adblock.upsells"
#define SGKeyFakePremium @"spotifyglass.adblock.premium"
#define SGKeyHideSearchVideos @"spotifyglass.adblock.searchVideos"

// What a switch turning Spoof Premium on is told first.
extern NSString *const SGFakePremiumWarning;

// The value the ads or upsells switch forces a flag to while it is on, or nil. Flags.x asks, and the row for
// it locks.
NSNumber *SGAdBlockForcedFlag(NSString *key);

// What the hooks stopped, by kind, for the counts under the switches (nil label for all of them).
void SGAdBlockCountOne(NSString *label);
NSArray<NSString *> *SGAdBlockLabels(void);
NSUInteger SGAdBlockCount(NSString *label);
// What a hook looked at under `label`, stopped or not, so a 0 can tell a hook Spotify never calls from one that
// found nothing. Kept with the counts but saved only with a stop or as Spotify leaves the screen: some hooks see a
// request a second. SGAdBlockChecked is NSNotFound for a kind that counts no checks, and 0 for one whose hook has
// not run, which on a new Spotify can mean it never will.
void SGAdBlockSawOne(NSString *label);
NSUInteger SGAdBlockChecked(NSString *label);
void SGResetAdBlock(void);

// Premium.m: the body of v1/customize, or the bootstrap message that wraps one, rewritten to a
// Premium account's. nil when the bytes do not parse.
NSData *SGPatchCustomize(NSData *body);
NSData *SGPatchBootstrap(NSData *body);

// Feeds.m: a browsita, casita or scrollsita feed with its ad sections taken out; nil when there
// were none, or the bytes were not the shape expected.
NSData *SGStripFeed(NSData *body);

// The Premium, ads & privacy page: these switches, the ad flags they lock, telemetry, the counters.
UIViewController *SGAdsSettingsPage(void);
