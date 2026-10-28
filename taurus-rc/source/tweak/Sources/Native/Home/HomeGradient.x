#import "Core/SGCore.h"
#import "Native/Appearance/Repaint.h"
#import "Home.h"

static const CGFloat kLevelHeight = 52;
static const CGFloat kOverscroll = 600;

static const uint32_t kTints[] = {0x0B4110, 0x0B4138, 0x0B2B41, 0x160B41, 0x330B41, 0x410B2E, 0x410B10, 0x412A0B};
static const CGFloat kStrengths[] = {0.62, 1.0, 1.45};
// 0 stands for the whole screen, which is only known once the page has been laid out.
static const CGFloat kHeights[] = {260, 390, 560, 0};

#define SGCount(table) (sizeof(table) / sizeof((table)[0]))

static char kGradientKey, kStrippedKey;

static NSUInteger clamp(NSInteger index, NSUInteger count) {
    if (index < 0) return 0;
    return (NSUInteger)index >= count ? count - 1 : (NSUInteger)index;
}

static UIColor *unpacked(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1];
}

static uint32_t strengthened(uint32_t rgb, CGFloat factor) {
    uint32_t out = 0;
    for (int shift = 16; shift >= 0; shift -= 8) {
        uint32_t channel = (uint32_t)round(MIN(255.0, ((rgb >> shift) & 0xFF) * factor));
        out |= channel << shift;
    }
    return out;
}

@interface SGHomeGradientView : UIView
- (void)paintColor:(uint32_t)color span:(CGFloat)span;
@end

@implementation SGHomeGradientView {
    uint32_t _color;
    CGFloat _span;
}

+ (Class)layerClass {
    return CAGradientLayer.class;
}

- (void)paintColor:(uint32_t)color span:(CGFloat)span {
    if (color == _color && span == _span) return;
    _color = color;
    _span = span;
    UIColor *tint = unpacked(color);
    CGFloat total = kOverscroll + span;
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    gradient.colors = @[(id)tint.CGColor, (id)tint.CGColor, (id)[tint colorWithAlphaComponent:0].CGColor];
    gradient.locations = @[@0, @((kOverscroll + kLevelHeight) / total), @1];
}

@end

static void stripCells(UIScrollView *list) {
    for (UIView *cell in list.subviews) {
        if (objc_getAssociatedObject(cell, &kStrippedKey)) continue;
        objc_setAssociatedObject(cell, &kStrippedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGForEachView(cell, ^(UIView *v) {
            if (SGIsBaseSurface(v.layer.backgroundColor)) v.layer.backgroundColor = NULL;
        });
    }
}

static SGHomeGradientView *gradientIn(UIScrollView *list) {
    SGHomeGradientView *view = objc_getAssociatedObject(list, &kGradientKey);
    if (!view) {
        view = [SGHomeGradientView new];
        view.userInteractionEnabled = NO;
        view.layer.zPosition = -1;
        objc_setAssociatedObject(list, &kGradientKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"home gradient behind %@", NSStringFromClass(list.class));
    }
    if (view.superview != list) [list insertSubview:view atIndex:0];
    return view;
}

static void layoutGradient(UIScrollView *list) {
    SGHomeGradientView *view = gradientIn(list);
    if (sg_homeRoot != list) sg_homeRoot = list;
    stripCells(list);

    CGFloat height = kHeights[clamp(SGHomeChoiceValue(SGHomeChoiceHeight), SGCount(kHeights))];
    CGFloat span = height > 0 ? height : list.bounds.size.height;
    uint32_t color = strengthened(kTints[clamp(SGHomeChoiceValue(SGHomeChoiceTint), SGCount(kTints))],
                                  kStrengths[clamp(SGHomeChoiceValue(SGHomeChoiceStrength), SGCount(kStrengths))]);

    CGRect frame = CGRectMake(0, -kOverscroll - list.adjustedContentInset.top,
                              list.bounds.size.width, kOverscroll + span);
    if (!CGRectEqualToRect(view.frame, frame)) view.frame = frame;
    [view paintColor:color span:span];
}

// The one collection view of the page; the shelves are collection views nested inside it.
static UIScrollView *pageList(UIView *view) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) return (UIScrollView *)sub;
    }
    return nil;
}

%hook _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIScrollView *list = pageList(((UIViewController *)self).viewIfLoaded);
    if (list) layoutGradient(list);
}
%end

%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    if ((UIView *)self == sg_homeRoot) layoutGradient((UIScrollView *)self);
}
%end

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (!page || !sg_homeRoot || ![sg_homeRoot isDescendantOfView:page]) return;
    for (UIView *wrapper in page.subviews) {
        for (UIView *view in wrapper.subviews) {
            if ([NSStringFromClass(view.class) containsString:@"GradientView"]) view.hidden = YES;
        }
    }
}
%end

%ctor {
    if (!SGNativeUI() || !SGFlag(SGKeyHomeGradient, NO)) return;
    %init;
    SGRequireClasses(@[
        @"_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
        @"_TtC19Home_FunkisPageImpl20FunkisViewController",
    ]);
}
