#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Artist.h"

static NSString *const kPageIdentifier = @"creator-page";

// Above for the bounce at the top of the page, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page

UIView *SGRArtistPageOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPageIdentifier]) return v;
    }
    return nil;
}

#pragma mark - the page's field

static SGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        SGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *SGRArtistFieldColor(UIView *view) {
    SGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: SGRNeutralField();
}

void SGRArtistSetArtwork(UIView *view, UIImage *image) {
    if (image) [fieldOn(view) setArtwork:image identity:nil animated:YES];
}

static SGRArtworkField *fieldIn(UIView *page) {
    SGRArtworkField *field = objc_getAssociatedObject(page, &kFieldKey);
    if (field) return field;
    field = [[SGRArtworkField alloc] initWithFrame:page.bounds];
    field.bleed = kBleed;
    objc_setAssociatedObject(page, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakPage = page;
    [field whenColored:^{ SGRRevealMark(weakPage, SGRRevealColor); }];
    SGLog(@"redesign artist: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC32CreativeWorkPlatform_TemplateKit12TemplateView
- (void)layoutSubviews {
    %orig;
    UIView *page = (UIView *)self;
    if (![page.accessibilityIdentifier isEqualToString:kPageIdentifier] || page.bounds.size.height < 200) return;
    // The page the repaint hook keeps clear is the one laying out, which is the one on screen.
    sgr_artistRoot = page;
    SGRRevealHold(page, 0);
    SGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}
%end

%hook _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView
- (void)layoutSubviews {
    %orig;
    UIView *list = (UIView *)self;
    if (!SGRArtistPageOf(list)) return;
    if (list.backgroundColor && SGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
    for (UIView *sub in list.subviews) {
        if (sub.backgroundColor && SGIsBaseSurface(sub.backgroundColor.CGColor)) sub.backgroundColor = UIColor.clearColor;
    }
}
%end

#pragma mark - the tab strip

static void hideStrip(UIView *strip) {
    if (strip.alpha != 0) strip.alpha = 0;
    if (strip.userInteractionEnabled) strip.userInteractionEnabled = NO;
    strip.accessibilityElementsHidden = YES;
    CGFloat lift = CGRectGetHeight(strip.bounds);
    for (UIView *v in strip.superview.subviews) {
        if (![v isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *pages = (UIScrollView *)v;
        if (pages.scrollEnabled) pages.scrollEnabled = NO;
        CGAffineTransform move = CGAffineTransformMakeTranslation(0, -lift);
        if (!CGAffineTransformEqualToTransform(pages.transform, move)) pages.transform = move;
    }
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign artist: the tab strip gone, the Music list up %.0fpt into its place", lift);
    }
}

// The strip's buttons are the one class of it Spotify names, and they lay out whenever the strip does.
%hook _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton
- (void)layoutSubviews {
    %orig;
    for (UIView *v = ((UIView *)self).superview; v; v = v.superview) {
        if (![v.accessibilityIdentifier isEqualToString:@"Components.UI.TabsSectionHeading"]) continue;
        if (SGRArtistPageOf(v)) hideStrip(v);
        return;
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC32CreativeWorkPlatform_TemplateKit12TemplateView",
        @"_TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView",
        @"_TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton",
    ]);
}
