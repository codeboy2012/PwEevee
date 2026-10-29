#import <UIKit/UIKit.h>
#import "Headers/SPTPlayer.h"

// A URI Spotify types as id (NSURL or NSString) as a string; nil for anything else.
NSString *SGURIString(id uri);

@protocol SGPlayerStateObserver <NSObject>
// Called when the track, context, Canvas metadata, paused, playing, loading or shuffle changed, not for position.
- (void)playerStateDidChange:(SPTPlayerState *)state;
@end
// Observers are held weakly and need no removal.
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer);
// The last state reported, nil before the player has reported one.
SPTPlayerState *SGPlayerState(void);
