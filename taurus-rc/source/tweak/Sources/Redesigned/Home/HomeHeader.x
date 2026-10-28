// Home redesign: the header the way the Music app has it. The filter pills (All, Music, Podcasts) go and
// a large title takes their place at the leading edge; the avatar that opens the side drawer moves to the
// trailing edge; the scrim Spotify lays behind the header goes too, the soft scroll edge (Kit/SGREdgeEffect.x)
// being what keeps the title clear of the page scrolling under it, as on every other redesigned page.
//
// Tree (trees/clean/home/10.txt:3018-3051): FunkisViewController's view holds a 402x112 UIView around
// Reprise_LiquidGlassKit LiquidGlass.GradientView (the scrim) and, at {0, 62}, an
// ElementView<HomeHeaderElement> 402x50 holding HomeHeaderView > UIStackView {0, 8} 402x34 of two arranged
// views: ListeningActivity_ElementsKit.AdaptiveFaceContainer {16, 0} 32x34 (the avatar,
// id=Components.UI.SideDrawerButton) and LiquidGlass.LeadingFadeMaskView {48, 1} 354x32 around
// Home_PillUIKit.PillScrollView.
//
// The avatar moves by the stack's layout direction rather than by a frame of ours. Right to left, the stack
// lays its first view out at the trailing edge itself on every pass, whatever width the face container
// takes when friends listening show beside the avatar; its leading margin, 16pt, is the one Spotify gives
// the header in a right to left language. The pills stay in the stack with no alpha rather than hidden,
// the way the redesign takes any view out of a stack Spotify arranges (Kit/SGRRestyle.h).
//
// The title is Spotify's own name for the tab, read off its tab bar item (id=TabBar.Item.Home, 10.txt:3100),
// so it follows the app's language.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Home.h"

// Tries at finding the tab's name before settling for the English one: a miss walks the window.
static const NSUInteger kTitleTries = 8;

static char kTitleKey, kTabKey, kStackWatchedKey, kLayoutKey;
static __weak UILabel *sg_title;
static __weak UIView *sg_face;
static UIVisualEffectView *sg_bar;
static CAGradientLayer *sg_barMask, *sg_barTint;
static CGFloat sg_scrollProgress;
// How far the page scrolls before the big title and the avatar are gone and the bar is fully in.
static const CGFloat kFadeDistance = 48;
static NSString *sg_tabName;

static void vanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

static NSString *tabName(UIWindow *window) {
    if (sg_tabName || !window) return sg_tabName ?: @"Home";
    static NSUInteger tries;
    if (tries >= kTitleTries) return @"Home";
    tries++;
    UIView *item = SGRFindByIdentifier(window, @"TabBar.Item.Home", &kTabKey);
    __block NSString *name = nil;
    if (item) SGForEachView(item, ^(UIView *v) {
        if (!name && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) name = ((UILabel *)v).text;
    });
    if (!name) {
        if (tries == kTitleTries) SGLog(@"redesign home: the Home tab's name not found, the title stays English");
        return @"Home";
    }
    sg_tabName = [name copy];
    SGLog(@"redesign home: title \"%@\" from the tab bar", sg_tabName);
    return sg_tabName;
}

static UILabel *titleIn(UIView *header) {
    UILabel *title = objc_getAssociatedObject(header, &kTitleKey);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(header, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != header) [header addSubview:title];
    return title;
}

// The header's views, found once: the page lays out again as it appears, and the walk names classes.
static __weak UIView *sg_header;
static __weak UIStackView *sg_stack;
static __weak UIView *sg_scrim;

static BOOL findHeader(UIView *view) {
    if (sg_stack && [sg_stack isDescendantOfView:view]) return YES;
    sg_stack = nil;
    sg_scrim = nil;
    for (UIView *wrapper in view.subviews) {
        UIView *scrim = childNamed(wrapper, @"GradientView");
        if (scrim) sg_scrim = scrim;
    }
    UIView *header = childNamed(childNamed(view, @"HomeHeaderElement"), @"HomeHeaderView");
    for (UIView *sub in header.subviews) {
        if ([sub isKindOfClass:UIStackView.class]) sg_stack = (UIStackView *)sub;
    }
    sg_header = header;
    if (sg_stack) return YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign home: header stack not found, header left as Spotify's"); });
    return NO;
}

static UIVisualEffectView *barIn(UIView *wrapper) {
    if (!sg_bar) {
        sg_bar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
        sg_bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        sg_bar.userInteractionEnabled = NO;
        sg_bar.accessibilityElementsHidden = YES;
        sg_bar.alpha = 0;
        sg_barMask = [CAGradientLayer layer];
        sg_barMask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        sg_barMask.locations = @[@0, @0.45, @1];
        sg_bar.layer.mask = sg_barMask;
        sg_barTint = [CAGradientLayer layer];
        sg_barTint.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.92].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.55].CGColor,
                              (id)[UIColor colorWithWhite:0 alpha:0].CGColor];
        sg_barTint.locations = @[@0, @0.5, @1];
        [sg_bar.contentView.layer addSublayer:sg_barTint];
    }
    return sg_bar;
}

// Scrolled down: the big title and the avatar fade away and a dark glass gradient takes the top of the screen.
static void applyScroll(UIScrollView *list) {
    CGFloat p = (list.contentOffset.y + list.adjustedContentInset.top) / kFadeDistance;
    p = MAX(0, MIN(1, p));
    sg_scrollProgress = p;
    if (sg_bar && sg_bar.alpha != p) sg_bar.alpha = p;
    if (sg_title && sg_title.alpha != 1 - p) sg_title.alpha = 1 - p;
    if (sg_face) {
        BOOL visible = SGFlag(SGRKeyNavbarProfilePhoto, YES);
        CGFloat alpha = visible ? 1 - p : 0;
        if (sg_face.alpha != alpha) sg_face.alpha = alpha;
        sg_face.userInteractionEnabled = visible && p < 0.5;
        sg_face.accessibilityElementsHidden = !visible;
    }
}

void SGRHomeProfilePhotoPreferenceChanged(void) {
    if (!sg_face) return;
    BOOL visible = SGFlag(SGRKeyNavbarProfilePhoto, YES);
    sg_face.alpha = visible ? 1 - sg_scrollProgress : 0;
    sg_face.userInteractionEnabled = visible && sg_scrollProgress < 0.5;
    sg_face.accessibilityElementsHidden = !visible;
}

static void layoutHeader(UIViewController *page) {
    UIView *view = page.viewIfLoaded;
    if (!view || !findHeader(view)) return;
    if ([objc_getAssociatedObject(page, &kLayoutKey) boolValue]) return;
    objc_setAssociatedObject(page, &kLayoutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *header = sg_header;
    UIStackView *stack = sg_stack;
    __weak UIViewController *weakPage = page;
    if (!objc_getAssociatedObject(stack, &kStackWatchedKey)) {
        objc_setAssociatedObject(stack, &kStackWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRObserveLayout(stack, ^(UIView *laidOut) {
            UIViewController *owner = weakPage;
            if (owner && [laidOut isDescendantOfView:owner.viewIfLoaded]) layoutHeader(owner);
        });
    }
    vanish(sg_scrim);

    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    UIView *face = nil;
    for (UIView *part in stack.arrangedSubviews) {
        if (faceClass && [part isKindOfClass:faceClass]) face = part;
        else vanish(part);
    }
    SGRNavbarSetProfilePhotoVisible(face);
    if (stack.semanticContentAttribute != UISemanticContentAttributeForceRightToLeft) {
        stack.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        [stack setNeedsLayout];
    }
    [stack layoutIfNeeded];

    UILabel *title = titleIn(header);
    NSString *text = tabName(header.window);
    if (![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGRFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    CGFloat trailing = face ? CGRectGetMinX([stack convertRect:face.frame toView:header]) - SGRGrid : header.bounds.size.width - SGRSideMargin;
    CGFloat height = ceil(font.lineHeight);
    CGRect frame = CGRectMake(SGRSideMargin, round(CGRectGetMidY(stack.frame) - height / 2), MAX(0, trailing - SGRSideMargin), height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;

    sg_title = title;
    sg_face = face;
    UIView *wrapper = header.superview;
    if (wrapper && SGRHomeGlassStyle()) {
        UIVisualEffectView *bar = barIn(wrapper);
        CGFloat bottom = CGRectGetMaxY([header convertRect:header.bounds toView:view]) + 28;
        CGRect barFrame = [view convertRect:CGRectMake(0, 0, view.bounds.size.width, bottom) toView:wrapper];
        if (bar.superview != wrapper) [wrapper insertSubview:bar belowSubview:header];
        if (!CGRectEqualToRect(bar.frame, barFrame)) bar.frame = barFrame;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        sg_barMask.frame = bar.bounds;
        sg_barTint.frame = bar.bounds;
        [CATransaction commit];
    }

    static BOOL logged;
    if (!logged && header.window && frame.size.width > 0 && header.bounds.size.height > 0) {
        logged = YES;
        SGLog(@"redesign home: header %@, avatar %@ in the stack %@, title %@, scrim %@", NSStringFromCGRect(header.frame),
              face ? NSStringFromCGRect(face.frame) : @"not found", NSStringFromCGRect(stack.frame), NSStringFromCGRect(frame),
              sg_scrim ? @"found" : @"not found");
    }
    objc_setAssociatedObject(page, &kLayoutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The page's own list is the one collection view with no other inside which it sits: the shelves are nested in it.
%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    UIScrollView *list = (UIScrollView *)self;
    if (list.bounds.size.height < 300 || !sg_bar) return;
    for (UIView *v = list.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return;
    }
    applyScroll(list);
}
%end

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLayoutSubviews {
    %orig;
    CFTimeInterval began = SGRHomeProbeBegin();
    layoutHeader((UIViewController *)self);
    SGRHomeProbeEnd(SGRHomeProbeHeader, began);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    [((UIViewController *)self).viewIfLoaded setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC19Home_FunkisPageImpl20FunkisViewController",
        @"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
    ]);
}
