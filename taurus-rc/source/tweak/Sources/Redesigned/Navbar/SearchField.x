#import "Core/SGCore.h"
#import "Diagnostics/Diagnostics.h"

@interface UIView (SGEncoreIcon)
- (void)setForegroundColor:(UIColor *)color;
@end

static char kStyledKey;
static __weak UIView *sg_searchField;

static BOOL isSearchField(UIView *button) {
    if ([button.accessibilityIdentifier isEqualToString:@"SearchHeaderFind.SearchBar"]) return YES;
    return SGIsLightColor(button.layer.backgroundColor);
}

static void whiten(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        ((UILabel *)view).textColor = UIColor.whiteColor;
    } else if ([NSStringFromClass(view.class) containsString:@"IconView"]) {
        if ([view respondsToSelector:@selector(setForegroundColor:)]) [view setForegroundColor:UIColor.whiteColor];
        else view.tintColor = UIColor.whiteColor;
    }
}

static void traceField(UIView *button, NSString *when) {
    if (!SGIsDebugBuild()) return;
    UIView *pane = nil, *dim = nil;
    for (UIView *sub in button.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) pane = sub;
    }
    for (UIView *v = button; v && !dim; v = v.superview) {
        if (v.hidden || v.alpha < 0.99) dim = v;
    }
    SGLog(@"search field %@: window %d, %@, pane %@, hidden by %@", when, button.window != nil,
          NSStringFromCGSize(button.bounds.size), pane ? @"attached" : @"missing",
          dim ? NSStringFromClass(dim.class) : @"nothing");
}

static void sampleField(__weak UIView *weakButton, int step) {
    UIView *button = weakButton;
    if (!button || step > 40) return;
    UIWindow *window = button.window;
    UIView *dim = nil;
    for (UIView *v = button; v && !dim; v = v.superview) {
        if (v.hidden || v.alpha < 0.99) dim = v;
    }
    UIView *pane = nil;
    for (UIView *sub in button.subviews) {
        if ([sub isKindOfClass:UIVisualEffectView.class]) pane = sub;
    }
    CGColorRef fill = button.layer.backgroundColor;
    SGLog(@"search field +%4dms: window %d, in window %@, alpha %.2f hidden %d, dimmed by %@, pane %@ alpha %.2f, fill alpha %.2f, radius %.1f",
          step * 50, window != nil,
          NSStringFromCGRect([button convertRect:button.bounds toView:window]),
          button.alpha, button.hidden, dim ? NSStringFromClass(dim.class) : @"nothing",
          pane ? @"attached" : @"missing", pane ? pane.alpha : -1,
          fill ? CGColorGetAlpha(fill) : -1, button.layer.cornerRadius);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sampleField(weakButton, step + 1);
    });
}

// One burst per arrival, so three trips in and out read as three bursts rather than three overlaid.
static void traceFieldArriving(UIView *button) {
    if (!SGIsDebugBuild() || !button.window) return;
    static NSTimeInterval last;
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (now - last < 2.5) return;
    last = now;
    sampleField(button, 0);
}

static void styleSearchField(UIView *button) {
    CGSize size = button.bounds.size;
    if (size.width < 200 || size.height < 40 || size.height > 60) return;
    BOOL styled = [objc_getAssociatedObject(button, &kStyledKey) boolValue];
    if (!styled && !isSearchField(button)) return;
    objc_setAssociatedObject(button, &kStyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (sg_searchField != button) sg_searchField = button;

    button.layer.backgroundColor = NULL;
    button.layer.cornerRadius = size.height / 2;
    button.layer.cornerCurve = kCACornerCurveContinuous;

    UIVisualEffectView *glass = SGGlassAt(button, 0);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.frame = button.bounds;
    SGShapeGlass(glass, size.height / 2, YES);

    SGForEachView(button, ^(UIView *v) { whiten(v); });
    traceField(button, @"styled");
}

%hook _TtCCE16Encore_ButtonKitO16EncoreFoundation6Encore6Button8Tertiary
- (void)layoutSubviews {
    %orig;
    styleSearchField((UIView *)self);
}
// Back from the full screen search the field is styled before it draws, not a layout pass later.
- (void)didMoveToWindow {
    %orig;
    if (isSearchField((UIView *)self)) {
        traceField((UIView *)self, @"moved");
        traceFieldArriving((UIView *)self);
    }
    styleSearchField((UIView *)self);
}
- (void)didAddSubview:(UIView *)subview {
    %orig;
    if (![subview isKindOfClass:UIVisualEffectView.class]) styleSearchField((UIView *)self);
}
%end

%hook UILabel
- (void)setTextColor:(UIColor *)color {
    %orig(SGIsInside((UIView *)self, sg_searchField) ? UIColor.whiteColor : color);
}
%end

%hook SPTEncoreIconView
- (void)setForegroundColor:(UIColor *)color {
    %orig(SGIsInside((UIView *)self, sg_searchField) ? UIColor.whiteColor : color);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtCCE16Encore_ButtonKitO16EncoreFoundation6Encore6Button8Tertiary", @"SPTEncoreIconView"]);
}
