#import <UIKit/UIKit.h>

@interface SGRPlayCapsule : UIControl
// Spotify's play button, the one the capsule reads and fires. Set by -feedFrom:.
@property (nonatomic, weak, readonly) UIView *source;
@property (nonatomic, copy) UIColor *fillColor;
// The glyph's and the word's colour; nil is the accent.
@property (nonatomic, copy) UIColor *contentColor;
- (void)feedFrom:(UIView *)source;
- (CGFloat)sgr_width;
@end

@interface SGRMirrorButton : UIControl
@property (nonatomic, weak, readonly) UIView *source;
// Drawn, in white, when Spotify's button has no image view to copy (a glyph it draws itself).
@property (nonatomic, strong) UIImage *fallbackGlyph;
@property (nonatomic, copy) UIColor *glyphColor;
@property (nonatomic, copy) UIColor *onGlyphColor;
@property (nonatomic, copy) BOOL (^readState)(BOOL *on);
@property (nonatomic, copy) NSString *stateOffSymbol;
@property (nonatomic, copy) NSString *stateOnSymbol;
- (void)feedFrom:(UIView *)source;
@end

SGRMirrorButton *SGRPinnedMore(UIView *page, const void *key, UIView *source);

// A sheet opening within this long of a tap on a pinned ⋯ is that page's context menu.
static const NSTimeInterval SGRPinnedMoreWindow = 3;
UIView *SGRPinnedMoreRecentPage(void);
