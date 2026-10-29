#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#define SGKeyLockScreenArtwork @"spotifyglass.lockscreen.animatedartwork"
#define SGKeyLockScreenArtworkSources @"spotifyglass.lockscreen.artworksources"

// Where a clip can come from: the track's Canvas, or the album's animated cover on Apple Music.
extern NSString *const SGArtworkSourceSpotify;
extern NSString *const SGArtworkSourceApple;
// The sources in the user's order, the ones switched off left out; Apple Music, then Spotify until set.
NSArray<NSString *> *SGArtworkOrder(void);
void SGArtworkSetOrder(NSArray<NSString *> *order);

// Whether this iOS has MPMediaItemAnimatedArtwork at all.
BOOL SGAnimatedArtworkAvailable(void);
NSArray<NSString *> *SGAnimatedArtworkKeys(void);
NSString *SGAnimatedArtworkKey(CGFloat *aspect);
NSDictionary *SGArtworkInInfo(NSDictionary *info, id artwork, NSString *key);
// The rows for the Lock screen widget page; below iOS 26 one row reads out what is missing instead.
@class SGModRow;
NSArray<SGModRow *> *SGAnimatedArtworkRows(void);
