#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

@interface SGRKaraokeView : UIView
// Hides Spotify's own lyrics next to this view while it has lyrics to show, and brings them back when not.
- (void)syncSiblings;
@property (nonatomic, readonly) UIEdgeInsets lineInsets;
// duration 0 moves everything at once.
- (void)setLineInsets:(UIEdgeInsets)insets duration:(NSTimeInterval)duration;
- (void)useCompactFontSize:(CGFloat)size;
@property (nonatomic, copy) BOOL (^takesTap)(void);
// YES keeps Sing's microphone up (and undimmed) while the lines are shown, for the player's Sing mode.
@property (nonatomic) BOOL keepsSing;
// YES hides the pronunciation/translation control, for when the lines are on their own in the player.
@property (nonatomic) BOOL extrasHidden;
// Allows the player to independently hide its translation control.
@property (nonatomic) BOOL extrasEnabled;
// Called as the user begins dragging the lines, for the player to bring its controls back.
@property (nonatomic, copy) void (^browsingBegan)(void);
// The preview's song: swaps in other lines, looped over `length` ms, from their start.
- (void)setSampleLines:(NSArray<SGKaraokeLine *> *)lines length:(NSTimeInterval)length;
// Freezes the preview's clock where it is, and lets it go on again from there.
@property (nonatomic) BOOL samplePaused;
- (instancetype)initWithSampleLines:(NSArray<SGKaraokeLine *> *)lines length:(NSTimeInterval)length;
@end
