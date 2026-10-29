#import <UIKit/UIKit.h>

extern NSNotificationName const SGRFieldColorDidChangeNotification;

@interface SGRArtworkField : UIView
@property (nonatomic) UIEdgeInsets bleed;
@property (nonatomic) BOOL showsBackdrop;
@property (nonatomic) BOOL flows;
// The sharp artwork layered over the blurred backdrop, fading into it toward the bottom.
@property (nonatomic) BOOL fills;
@property (nonatomic) CGFloat backdropOpacity;
@property (nonatomic) CGFloat fillOpacity;
@property (nonatomic) CGFloat fluidOpacity;
// Fluid artwork instead (SGRFluid.h): the cover itself blurred and slowly turning over the whole of the
// bounds, under the same conditions for moving as `flows`. Setting one turns the other off.
@property (nonatomic) BOOL fluid;
// Held still by the owner (the player while playback is paused).
@property (nonatomic) BOOL motionHeld;
// Covered by something opaque the owner lays over the whole of the bounds (the player's Animated artwork
// clip): the Fluid copies are hidden rather than composited under it for nothing, and come back where they
// were when it is NO again. Set it only once the cover is opaque, and back before it starts to fade.
@property (nonatomic) BOOL covered;
// The backdrop's height in points from the top of the bounds; 0 is the window's height.
@property (nonatomic) CGFloat backdropHeight;
// SGRNeutralField until a colour arrives.
@property (nonatomic, readonly) UIColor *fieldColor;

- (void)setProvisionalColor:(UIColor *)color;
- (void)setPreferredColor:(UIColor *)color;
- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated;
- (void)refreshStyleAnimated:(BOOL)animated;
- (void)whenColored:(void (^)(void))colored;
// A light blur over the Fill artwork while the lyrics are open, so their text and the header read over a sharp
// cover. Only the Fill background takes it; the other backgrounds are already soft.
- (void)setLyricsBlurred:(BOOL)blurred animated:(BOOL)animated;
@end
