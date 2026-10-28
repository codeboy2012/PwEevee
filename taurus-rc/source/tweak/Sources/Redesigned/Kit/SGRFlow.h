#import <UIKit/UIKit.h>

@interface SGRFlowLayer : CALayer
- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated;
// The colour under the discs, darker than the artwork's main one; nil before any colours are set.
@property (nonatomic, readonly) UIColor *baseColor;
// Drifting, or held still where it is. Off to begin with.
@property (nonatomic) BOOL moving;
@end
