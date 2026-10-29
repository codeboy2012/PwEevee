// The top of the Vibrations page: rings of dots that ripple out from the middle when tapped, while the
// Taptic Engine plays the tap of the page's first feature that is on, and a line under them naming it.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@interface SGVibrationsPreview : UIView
// Music Haptics' taps pulse the rings gently while this is on; the page turns it on only while it shows.
@property (nonatomic) BOOL listening;
// Reads again which feature a tap plays, for the line under the rings.
- (void)reload;
// The height the preview needs at `width`, its line at the current text size.
- (CGFloat)heightForWidth:(CGFloat)width;
// A ripple with no tap of its own, at a strength of 0 to 1: for a tap played elsewhere on the page.
- (void)rippleAt:(CGFloat)strength;
@end
