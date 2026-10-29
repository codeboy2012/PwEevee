#import <objc/runtime.h>
#import "Core/SGCore.h"

static void soften(UIScrollView *scrollView) {
    if (@available(iOS 26.0, *)) {
        // The style last set here, so a layout pass the setter itself causes does not set it again.
        static char setKey;
        UIScrollEdgeEffect *top = scrollView.topEdgeEffect;
        if (top.style == objc_getAssociatedObject(scrollView, &setKey)) return;
        UIScrollEdgeEffectStyle *soft = UIScrollEdgeEffectStyle.softStyle;
        top.style = soft;
        objc_setAssociatedObject(scrollView, &setKey, top.style, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"soft top edge: first scroll view %@", NSStringFromClass(scrollView.class)); });
    }
}

%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    if (self.window) soften(self);
}

- (void)layoutSubviews {
    %orig;
    if (self.window) soften(self);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
}
