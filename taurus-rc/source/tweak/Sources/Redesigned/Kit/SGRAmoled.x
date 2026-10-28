#import "Core/SGCore.h"

// Neutral and darker than #1A1A1A, but not already black.
static BOOL isBaseGrey(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID()) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    size_t n = CGColorGetNumberOfComponents(color);
    if (n == 2) return c[0] > 0.01 && c[0] <= 0.10;
    if (n < 3) return NO;
    return c[0] > 0.01 && c[0] <= 0.10 && fabs(c[0] - c[1]) < 0.02 && fabs(c[1] - c[2]) < 0.02;
}

// Layers get set from background threads too, so no autoreleased UIColor here.
static CGColorRef copyBlack(CGColorRef color) {
    return CGColorCreateGenericGray(0, CGColorGetAlpha(color));
}

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (!isBaseGrey(color)) {
        %orig;
        return;
    }
    CGColorRef black = copyBlack(color);
    %orig(black);
    CGColorRelease(black);
}
%end

%hook CAGradientLayer
- (void)setColors:(NSArray *)colors {
    NSMutableArray *mapped = [[NSMutableArray alloc] initWithCapacity:colors.count];
    for (id entry in colors) {
        CGColorRef color = (__bridge CGColorRef)entry;
        if (!isBaseGrey(color)) {
            [mapped addObject:entry];
            continue;
        }
        CGColorRef black = copyBlack(color);
        [mapped addObject:(__bridge id)black];
        CGColorRelease(black);
    }
    %orig(colors ? mapped : nil);
}
%end

%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    for (UIView *sub in ((UIViewController *)self).view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) sub.backgroundColor = UIColor.blackColor;
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
