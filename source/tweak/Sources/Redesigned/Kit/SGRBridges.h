#import <UIKit/UIKit.h>
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"

#pragma mark - now playing artwork

typedef NS_ENUM(NSInteger, SGRArtworkQuality) {
    SGRArtworkQualityLow,     // the now playing bar's 40pt cover
    SGRArtworkQualityHigh,    // the player's own cover
    SGRArtworkQualityExact,   // the picture the track's metadata names, fetched by the Kit
};
// Posted when the artwork changes, object nil, userInfo image, trackURI and quality.
extern NSNotificationName const SGRNowPlayingArtworkDidChangeNotification;
void SGRSetNowPlayingArtwork(UIImage *image, NSString *trackURI, SGRArtworkQuality quality);
UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity);

#pragma mark - the player's open and close

// While the full screen player opens or closes (Shared/Player/PlayerEvents.x announces it).
BOOL SGRPlayerIsTransitioning(void);
void SGRObservePlayerTransition(id owner, void (^began)(id owner), void (^ended)(id owner));
