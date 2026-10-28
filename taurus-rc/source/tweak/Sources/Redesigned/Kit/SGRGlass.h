#import <UIKit/UIKit.h>

UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side);

UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent);

// Shows or hides a shape's material without touching an alpha over it: a glass shape's effect is set or
// cleared, so it fades as the system's glass does; under Reduce Transparency (a solid fill) it fades by
// alpha. Call inside an SGRAnimate block.
void SGRShowGlass(UIView *shape, BOOL shown);
