#import <UIKit/UIKit.h>

#pragma mark - views

void SGRSuppress(UIView *view);

void SGRMonospacedDigits(UILabel *label);

BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view));

BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view));

UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey);

@interface SGRShadowPlate : UIView
@property (nonatomic) CGFloat cornerRadius;   // SGRRadiusArtwork unless set
@end
SGRShadowPlate *SGRShadowPlateIn(UIView *host, const void *key);

#pragma mark - Spotify's controls and pages

void SGRClearCellPaint(UIView *cell);

void SGRActivate(UIView *source);

BOOL SGRFire(UIControl *control);
