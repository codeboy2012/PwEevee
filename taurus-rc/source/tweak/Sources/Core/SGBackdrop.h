#import <UIKit/UIKit.h>

UIImage *SGBackdropSample(UIImage *cover);
// The scrim runs from 0.40 black at the top to `bottomAlpha` at the bottom.
UIView *SGBackdropMake(CGRect frame, CGFloat bottomAlpha);
UIImageView *SGBackdropImageView(UIView *backdrop);
