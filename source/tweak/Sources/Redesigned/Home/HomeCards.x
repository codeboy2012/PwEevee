#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// Below this a card's picture is a glyph or a placeholder, not a cover.
static const CGFloat kCoverMinWidth = 80;

static char kImageKey, kRetryKey;

BOOL SGRHomeGlassStyle(void) {
    static BOOL glass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ glass = SGRedesignedUI() && SGFlag(SGRKeyHomeGlass, YES); });
    return glass;
}

SGModRow *SGRHomeStyleRow(void) {
    return SGWithSymbol(SGSwitchRow(@"Home page", @"Glass playlists and a gradient. Set the first shelf size separately.", SGRKeyHomeGlass), @"house");
}

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
}

static char kBackingKey;

// Top picks' cards sit on a translucent glass card as a whole: the cover at its top, Spotify's text below.
static const CGFloat kCardRadius = 26;

static void backing(UIView *card, BOOL large) {
    UIView *back = objc_getAssociatedObject(card, &kBackingKey);
    if (!large) { back.hidden = YES; return; }
    if (!back) {
        back = [UIView new];
        back.userInteractionEnabled = NO;
        back.accessibilityElementsHidden = YES;
        back.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        back.layer.cornerCurve = kCACornerCurveContinuous;
        back.layer.borderWidth = 1;
        back.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        objc_setAssociatedObject(card, &kBackingKey, back, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (back.superview != card) [card insertSubview:back atIndex:0];
    back.hidden = NO;
    if (!CGRectEqualToRect(back.frame, card.bounds)) back.frame = card.bounds;
    if (back.layer.cornerRadius != kCardRadius) back.layer.cornerRadius = kCardRadius;
}

// A large card's text sits a little in from the glass card's edges, rather than on them.
static const CGFloat kTextInset = 10;

static void centerText(UIView *card, UIView *holder, BOOL large) {
    SGForEachView(card, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || [v isDescendantOfView:holder]) return;
        CGFloat shift = large ? kTextInset : 0;
        if (v.transform.tx == shift) return;
        v.transform = CGAffineTransformMakeTranslation(shift, 0);
    });
}

static void roundCover(UIView *card) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kImageKey);
    if (holder.bounds.size.width < kCoverMinWidth) return;
    BOOL glass = SGRHomeGlassStyle();
    BOOL large = glass && SGRHomeShelfIsLarge(card);
    if (glass) backing(card, large);
    if (glass) centerText(card, holder, large);
    for (UIView *sub in holder.subviews) {
        if (![sub isKindOfClass:UIImageView.class]) continue;
        roundCorners(sub, large ? kCardRadius : SGRRadiusCover);
        CACornerMask corners = large ? (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner) : (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner);
        if (sub.layer.maskedCorners != corners) sub.layer.maskedCorners = corners;
        if (!sub.layer.masksToBounds) sub.layer.masksToBounds = YES;
    }
}

static void calmDJ(UIView *card) {
    for (UIView *sub in card.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"TranscriptView"] && ![name containsString:@"BetaBadge"]) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        sub.accessibilityElementsHidden = YES;
        SGForEachView(sub, ^(UIView *v) {
            if ([v isKindOfClass:UILabel.class]) SGRSuppress(v);
        });
    }
}

static void style(UIView *button) {
    NSString *identifier = button.accessibilityIdentifier;
    if ([identifier isEqualToString:@"Shortcut.Card.Home"]) {
        CGFloat pill = SGRHomeGlassStyle() ? MIN(18, button.bounds.size.height / 2) : SGRRadiusCover;
        roundCorners(button, pill);
        if (button.superview.layer.cornerRadius > 0) roundCorners(button.superview, pill);
        SGRHomeStyleTile(button);
        // The first pass can come before the tile has its size: lay it out once more a moment later.
        if (SGRHomeGlassStyle() && !objc_getAssociatedObject(button, &kRetryKey)) {
            objc_setAssociatedObject(button, &kRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak UIView *weak = button;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weak setNeedsLayout]; });
        }
        return;
    }
    if ([identifier isEqualToString:@"Components.UI.HomeCard"]) {
        roundCover(button);
        return;
    }
    static Class dj;
    if (!dj) dj = NSClassFromString(@"_TtC30Discovery_MediumDensityCardKit9DJMDCView");
    if (dj && [button.superview isKindOfClass:dj]) {
        roundCorners(button, SGRRadiusCard);
        calmDJ(button);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign home: DJ card at the card radius, transcript gone"); });
    }
}

%hook _TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton
- (void)layoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    style((UIView *)self);
    SGRHomeProbeEnd(SGRHomeProbeCards, began);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19LegacyUI_ECMCoreKit31InteractableLayoutBackingButton",
        @"_TtC30Discovery_MediumDensityCardKit9DJMDCView",
    ]);
}
