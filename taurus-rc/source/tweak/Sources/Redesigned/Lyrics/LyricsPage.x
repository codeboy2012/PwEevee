#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"

static char kPageGlassKey;

static UIView *clearAncestors(UIView *view) {
    UIView *top = view;
    for (UIView *v = view; v && ![v isKindOfClass:UIWindow.class]
            && ![NSStringFromClass(v.class) hasPrefix:@"UITransition"]; v = v.superview) {
        v.layer.backgroundColor = NULL;
        top = v;
    }
    return top;
}

%hook _TtC32Lyrics_FullscreenElementPageImpl14FullscreenView
// A colour kept here is re-applied whenever UIKit feels like it, so it is refused outright.
- (void)setBackgroundColor:(UIColor *)color {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"lyrics page paints itself %@ through UIView", color); });
    %orig(nil);
}

- (void)layoutSubviews {
    %orig;
    UIView *page = (UIView *)self;
    if (page.bounds.size.height < 200) return;

    page.layer.backgroundColor = NULL;
    sgr_lyricsPageRoot = clearAncestors(page);

    UIVisualEffectView *glass = SGGlassFor(page, &kPageGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.frame = page.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    // Full bleed, so the shape is spelled out: a fresh pane does not promise square corners.
    SGShapeGlass(glass, 0, NO);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl14FullscreenView"]);
}
