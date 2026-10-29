// The top of the Live Activity page: a slice of the lock screen, its date and clock over a mock of the card,
// drawn here in UIKit after extension/LiveActivity/LiveActivityWidget.swift's layout, with a made-up song. It
// follows the page's settings as they change, and shows the view picked under Shows, stepping through it every
// 3 s with a crossfade: the Lyrics view through a few lines being sung and then a track with no lyrics, the
// Control menu through its tabs. The Queue view rests, as the card does. Under Reduce Motion it rests on the
// first step and a tap moves it on. Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGLiveActivityPreview : UIView
// Steps only while this is on; the page turns it on while it shows.
@property (nonatomic) BOOL running;
// Reads the page's settings again. Another view crossfades in from its first step.
- (void)reload;
// The same at every width: the card is clipped at the 160 points iOS gives it, so the slice never changes height.
- (CGFloat)heightForWidth:(CGFloat)width;
@end
