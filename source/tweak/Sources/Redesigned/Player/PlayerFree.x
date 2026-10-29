// Player redesign: a Spotify Free account opens the redesigned player too.
//
// Spotify lays its player out by a mode: the now playing modes service asks the modes it holds in turn,
// -[SPTNowPlayingMode isActiveFor:productState:], and takes the first that answers YES. In 9.1.78 a music
// track meets, by their identifiers, NowPlayingReinventFreeMode first (8, ReinventFree_ReinventFreeNpvImpl,
// the free tier Spotify calls "MFT+ (Reinvented Free)"), which answers YES on a Free account with pick and
// shuffle (-[SPTNowPlayingProductState isPickAndShuffleEnabled]), then NowPlayingMusicFreeMode (9,
// NowPlaying_ModesImpl), which answers YES on any Free account, then NowPlayingMusicPremiumMode (11), which
// answers YES to everything. The Reinvented Free mode's units are classes of its own module
// (ReinventFreeNavigationBarUnitViewController, ReinventFreeInformationElementsUnit,
// ReinventFreePlaybackControlsElementsUnit, ReinventFreeFooterElementsUnit, DurationElementsUnit), which none
// of the redesign's hooks reach: they are on NowPlaying_ModesImpl's units, the ones both of that module's
// music modes are built from. So on a Free account the field came in behind Spotify's own header, controls
// and footer.
//
// While the redesign runs, the Reinvented Free mode declines, and the track falls to NowPlayingMusicFreeMode:
// still Spotify's player for a Free account, with its controls and its limits, laid out by the units the
// redesign styles. Nothing about the account changes, and a Premium account never reaches either mode.
// Read from the binary only (the selectors and identifiers above); no Free account's player has been
// recorded in trees/clean/.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

%hook _TtC32ReinventFree_ReinventFreeNpvImpl26NowPlayingReinventFreeMode
- (BOOL)isActiveFor:(id)playerState productState:(id)productState {
    BOOL active = %orig;
    static dispatch_once_t once;
    if (active) dispatch_once(&once, ^{ SGLog(@"redesign player: Reinvented Free player declined, Spotify's Free player takes the track"); });
    return NO;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32ReinventFree_ReinventFreeNpvImpl26NowPlayingReinventFreeMode"]);
}
