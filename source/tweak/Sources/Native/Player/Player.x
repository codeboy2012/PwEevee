#import "Core/SGCore.h"
#import "Native/Appearance/Repaint.h"
#import "NowPlaying.h"
#import "Native/Appearance/Appearance.h"

static const CGFloat kButtonMin = 36, kButtonMax = 48;
static const CGFloat kArtRadius = 12;

static BOOL backdropOn(void) {
    return SGFlag(SGKeyPlayerBackdrop, NO);
}

#pragma mark - glass behind the header buttons

static void glassBehindRoundButtons(UIViewController *unit) {
    if (!SGFlag(SGKeyPlayer, NO)) return;
    UIView *host = unit.viewIfLoaded;
    UIStackView *row = SGRowIn(host);
    if (!row) return;
    [row layoutIfNeeded];
    NSUInteger index = 0;
    for (UIView *child in row.arrangedSubviews) {
        CGRect f = SGFrameIn(child, host);
        if (child.hidden || child.alpha == 0 || f.size.width < 20 || f.size.height < 20) continue;
        if (f.size.width > f.size.height * 1.4) continue;
        CGFloat side = MAX(kButtonMin, MIN(MAX(f.size.width, f.size.height), kButtonMax));
        UIVisualEffectView *glass = SGGlassAt(host, index++);
        if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        glass.frame = CGRectMake(CGRectGetMidX(f) - side / 2, CGRectGetMidY(f) - side / 2, side, side);
        SGShapeGlass(glass, side / 2, YES);
    }
    SGHideGlassFrom(host, index);
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    glassBehindRoundButtons((UIViewController *)self);
}
%end

#pragma mark - the cover behind the player

static char kBackdropKey;

static UIImage *sg_cover;       // the cover the backdrop stands on, compared by pointer
static UIImage *sg_coverSmall;
static __weak UIImageView *sg_coverView;

static void showCover(UIImage *cover) {
    if (!cover || cover == sg_cover) return;
    sg_cover = cover;
    sg_coverSmall = SGBackdropSample(cover);
    UIImageView *view = sg_coverView;
    if (!view) return;
    [UIView transitionWithView:view duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        view.image = sg_coverSmall;
    } completion:nil];
}

static UIImage *coverInFront(UIScrollView *list) {
    CGFloat middle = list.contentOffset.x + list.bounds.size.width / 2;
    __block UIImage *cover = nil;
    // The cover is 354pt across, the glyph standing in for a missing one 64pt.
    __block CGFloat widest = 200;
    for (UIView *cell in list.subviews) {
        if (middle < CGRectGetMinX(cell.frame) || middle > CGRectGetMaxX(cell.frame)) continue;
        SGForEachView(cell, ^(UIView *view) {
            UIImageView *image = (UIImageView *)view;
            if (![view isKindOfClass:UIImageView.class] || !image.image || image.bounds.size.width <= widest) return;
            widest = image.bounds.size.width;
            cover = image.image;
        });
    }
    return cover;
}

static UIView *backdropIn(UIView *plane) {
    UIView *backdrop = objc_getAssociatedObject(plane, &kBackdropKey);
    if (backdrop) return backdrop;

    backdrop = SGBackdropMake(plane.bounds, SGFlag(SGKeyAmoled, NO) ? 1 : 0.94);
    UIImageView *cover = SGBackdropImageView(backdrop);
    cover.image = sg_coverSmall;
    sg_coverView = cover;

    objc_setAssociatedObject(plane, &kBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return backdrop;
}

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!backdropOn()) return;
    UIView *plane = ((UIViewController *)self).viewIfLoaded;
    if (!plane || plane.bounds.size.height < 200) return;
    sg_npvBackdropRoot = plane;
    UIView *backdrop = backdropIn(plane);
    for (UIView *sub in plane.subviews) {
        if (sub != backdrop) SGStripBackgrounds(sub);
    }
    plane.layer.backgroundColor = NULL;
    if (backdrop.superview != plane) [plane insertSubview:backdrop atIndex:0];
}
%end

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    %orig;
    if (backdropOn()) showCover(coverInFront((UIScrollView *)self));
}
%end

#pragma mark - what the cover behind it changes around the player

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    %orig;
    if (!backdropOn()) return;
    UIView *tilt = (UIView *)self;
    CGSize size = tilt.bounds.size;
    // The player's cover only; the bar downstairs carries a 40pt one of its own.
    if (size.width < 200) return;
    SGForEachView(tilt, ^(UIView *view) {
        if (view == tilt || !CGSizeEqualToSize(view.bounds.size, size)) return;
        view.layer.cornerRadius = kArtRadius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
        view.clipsToBounds = YES;
    });
    tilt.layer.shadowColor = UIColor.blackColor.CGColor;
    tilt.layer.shadowOpacity = 0.45;
    tilt.layer.shadowRadius = 32;
    tilt.layer.shadowOffset = CGSizeMake(0, 12);
    tilt.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:tilt.bounds cornerRadius:kArtRadius].CGPath;
}
%end

%hook _TtC22Lyrics_NPVContainerKit19LyricsContainerView
- (void)layoutSubviews {
    %orig;
    if (backdropOn()) ((UIView *)self).alpha = 0.72;
}
%end

static UIFont *timeFont(void) {
    static UIFont *font;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    });
    return font;
}

%hook _TtC20NowPlaying_ModesImpl19DurationElementUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = backdropOn() ? ((UIViewController *)self).viewIfLoaded : nil;
    if (!host) return;
    SGForEachView(host, ^(UIView *view) {
        UILabel *label = (UILabel *)view;
        if (![view isKindOfClass:UILabel.class] || label.font.pointSize > 11 || label.font == timeFont()) return;
        label.font = timeFont();
    });
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit",
        @"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController",
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC22Lyrics_NPVContainerKit19LyricsContainerView",
        @"_TtC20NowPlaying_ModesImpl19DurationElementUnit",
    ]);
}
