#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Settings/SGPage.h"
#import "Shared/Navigation/TabIcons.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/message.h>

static char kBarKey, kHostKey, kDockKey;
static __weak UIView *sg_stockBar;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic) BOOL holding;
@end

static void syncBar(UIView *stockBar);
static void applyMinimized(UIView *stockBar, BOOL animated);

// The mod's own tab the user last opened a page with; it overrides Spotify's label whites until a stock
// tab is tapped, because Spotify has no idea one of the mod's tabs is showing a page.
static __weak UIView *sg_customSource;

void SGRTabBarMarkCustomSelected(UIView *customItem) {
    sg_customSource = customItem;
    UIView *stockBar = sg_stockBar;
    if (customItem && stockBar) syncBar(stockBar);
}

#pragma mark - minimizing the glass bar

// TabBarMinimize.x decides this from a page's scroll. Minimized, the bar gives way to its first and last tab as two
// round glass buttons at its ends, and the now playing card takes the row between them (applyMinimized).
static BOOL sg_minimized;

BOOL SGRTabBarMinimized(void) {
    return sg_minimized;
}

void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {
    if (sg_minimized == minimized) return;
    // With nothing playing there is no pill for the row between the buttons: the bar stays whole.
    if (minimized && !SGRNowPlayingAvailable()) return;
    sg_minimized = minimized;
    UIView *stockBar = sg_stockBar;
    if (stockBar) applyMinimized(stockBar, animated);
}

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

static UIImage *customGlyph(NSString *name, BOOL symbols) {
    if (!name.length) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%@", symbols ? @"symbols" : @"encore", name];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    UIView *custom = SGTabIconView(name, symbols, UIColor.whiteColor);
    CGSize size = CGSizeMake(24, 24);
    custom.translatesAutoresizingMaskIntoConstraints = YES;
    custom.frame = (CGRect){CGPointZero, size};
    [custom layoutIfNeeded];
    UIImage *image = renderLayer(custom.layer, size);
    if (image) [cache setObject:image forKey:key];
    return image;
}

static UIImage *stockGlyph(NSString *name, BOOL active) {
    if (!name.length) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@:%d", name, active];
    UIImage *cached = [cache objectForKey:key];
    if (cached) return cached;
    Class iconClass = NSClassFromString(@"SPTEncoreIcon");
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    SEL selector = NSSelectorFromString(name);
    if (!iconClass || !viewClass || ![iconClass respondsToSelector:selector]) return nil;
    id icon = ((id (*)(id, SEL))objc_msgSend)(iconClass, selector);
    if (!icon) return nil;
    SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
    view.frame = CGRectMake(0, 0, 24, 24);
    [view setForegroundColor:UIColor.whiteColor];
    if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
    if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
    [view layoutIfNeeded];
    UIImage *image = renderLayer(view.layer, view.bounds.size);
    if (image) [cache setObject:image forKey:key];
    return image;
}

static NSString *appleMusicSymbolForTab(NSString *title) {
    static NSDictionary<NSString *, NSString *> *symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        symbols = @{
            @"home": @"house.fill",
            @"listen now": @"house.fill",
            @"search": @"magnifyingglass",
            @"your library": @"square.stack.fill",
            @"library": @"square.stack.fill",
            @"browse": @"square.grid.2x2.fill",
            @"radio": @"dot.radiowaves.left.and.right",
        };
    });
    return symbols[title.lowercaseString];
}

static UIImage *glyphOf(UIView *item, BOOL active) {
    if ([NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"]) {
        NSArray<NSString *> *parts = [item.accessibilityIdentifier componentsSeparatedByString:@":"];
        if (parts.count >= 2) return customGlyph(parts[1], [parts[0] isEqualToString:@"symbols"]);
    } else {
        NSString *title = labelIn(item).text;
        NSDictionary *stockEntry = nil;
        for (NSDictionary *entry in SGRNavbarLayout()) {
            if ([entry[SGRNavbarID] isEqualToString:title] && !entry[SGRNavbarURI]) {
                stockEntry = entry;
                NSString *name = entry[SGRNavbarIcon];
                if (SGRNavbarEntryHasCustomIcon(entry) && [name isKindOfClass:NSString.class]) {
                    return customGlyph(name, [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols]);
                }
                break;
            }
        }
        if (SGFlag(SGRKeyNavbarAppleIcons, NO)) {
            NSString *symbol = appleMusicSymbolForTab(title);
            if (symbol) return customGlyph(symbol, YES);
        }
        UIImage *defaultIcon = stockGlyph(SGRNavbarDefaultIcon(stockEntry[SGRNavbarID] ?: title), active);
        if (defaultIcon) return defaultIcon;
    }

    UIView *live = iconIn(item);
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) cache = [NSCache new];
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", [icon respondsToSelector:@selector(name)] ? [icon name] : icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    // Tabs of the mod's own draw a UIImageView, or an icon Encore would not draw off screen.
    return size.width >= 2 ? renderLayer(live.layer, size) : nil;
}

#pragma mark - passing a tap on

static BOOL fireTapRecognizers(UIView *view) {
    Ivar targetsIvar = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
    if (!targetsIvar) return NO;
    BOOL fired = NO;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled) continue;
        for (id pair in object_getIvar(recognizer, targetsIvar)) {
            Ivar targetIvar = class_getInstanceVariable([pair class], "_target");
            Ivar actionIvar = class_getInstanceVariable([pair class], "_action");
            if (!targetIvar || !actionIvar) continue;
            id target = object_getIvar(pair, targetIvar);
            SEL action = *(SEL *)((char *)(__bridge void *)pair + ivar_getOffset(actionIvar));
            if (!target || !action || ![target respondsToSelector:action]) continue;
            SGLog(@"tab bar: tap -> %@ %@", NSStringFromClass([target class]), NSStringFromSelector(action));
            ((void (*)(id, SEL, id))objc_msgSend)(target, action, recognizer);
            fired = YES;
        }
    }
    return fired;
}

BOOL SGRFireTapRecognizers(UIView *view) {
    return fireTapRecognizers(view);
}

static void forwardTap(UIView *item) {
    __block BOOL sent = NO;
    SGForEachView(item, ^(UIView *v) {
        if (!sent) sent = fireTapRecognizers(v);
    });
    SGForEachView(item, ^(UIView *v) {
        if (sent || ![v isKindOfClass:UIControl.class]) return;
        SGLog(@"tab bar: tap -> control %@", NSStringFromClass(v.class));
        [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        sent = YES;
    });
    if (!sent) {
        NSMutableString *out = [NSMutableString stringWithFormat:@"tab bar: nothing to tap in %@", NSStringFromClass(item.class)];
        SGForEachView(item, ^(UIView *v) {
            for (UIGestureRecognizer *r in v.gestureRecognizers) [out appendFormat:@"\n  %@ on %@", r, NSStringFromClass(v.class)];
        });
        SGLogLong(@"navbar", out);
    }
}

#pragma mark - the two round buttons

static const CGFloat kDockSize = 48, kDockGap = 8;

@interface SGRDockButton : UIVisualEffectView
@property (nonatomic, weak) UIView *source;
@property (nonatomic, readonly) UIImageView *glyph;
@end

@implementation SGRDockButton
- (instancetype)init {
    UIVisualEffect *effect = SGGlassEffect();
    if ([effect respondsToSelector:@selector(setInteractive:)]) ((void (*)(id, SEL, BOOL))objc_msgSend)(effect, @selector(setInteractive:), YES);
    if (!(self = [super initWithEffect:effect])) return nil;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    SGShapeGlass(self, kDockSize / 2, YES);
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeCenter;
    [self.contentView addSubview:_glyph];
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _glyph.frame = self.bounds;
}
// A tap on a round button opens its tab and brings the bar back, as the Music app's does: the pill and the two
// buttons gather into the full bar again, with the now playing card above it.
- (void)tapped {
    UIView *source = self.source;
    if (source) forwardTap(source);
    SGRSetTabBarMinimized(NO, YES);
}
@end

// The bar's glass platter, in the host's coordinates: the widest view of a bar's height inside the system bar.
static CGRect pillIn(UIView *host, UITabBar *bar) {
    __block CGRect best = CGRectNull;
    __block CGFloat widest = 0;
    SGForEachView(bar, ^(UIView *v) {
        CGSize size = v.bounds.size;
        if (v == bar || size.width < bar.bounds.size.width * 0.5 || size.height < 44 || size.height > 72) return;
        if (size.width > widest) {
            widest = size.width;
            best = SGFrameIn(v, host);
        }
    });
    if (!CGRectIsNull(best)) return best;
    CGFloat bottom = host.window.safeAreaInsets.bottom;
    CGFloat height = 62;
    return CGRectMake(20, host.bounds.size.height - bottom - height, host.bounds.size.width - 40, height);
}

// Sets a view's place without its frame, which means nothing while it is scaled.
static void place(UIView *view, CGRect frame) {
    CGRect bounds = (CGRect){CGPointZero, frame.size};
    CGPoint center = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (!CGRectEqualToRect(view.bounds, bounds)) view.bounds = bounds;
    if (!CGPointEqualToPoint(view.center, center)) view.center = center;
}

static NSArray<SGRDockButton *> *dockButtons(UIView *stockBar) {
    NSArray *buttons = objc_getAssociatedObject(stockBar, &kDockKey);
    if (!buttons) {
        buttons = @[[SGRDockButton new], [SGRDockButton new]];
        // Out of sight until the bar minimizes.
        for (SGRDockButton *button in buttons) {
            button.alpha = 0;
            button.userInteractionEnabled = NO;
        }
        objc_setAssociatedObject(stockBar, &kDockKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return buttons;
}

// The first and last tab's glyphs and places; the row left between them, in window coordinates.
//
// Minimized, the two buttons are 48 pt circles at the bar's ends. Expanded, they are where the bar draws its own: the
// first one grows into the capsule that holds the tabs and the last one into the round button beside it, and that
// growth is the animation between the two (applyMinimized). `circles` and `shapes` answer for the two states, left
// then right. When they are asked for, the caller animates the buttons and they are not placed here; otherwise they
// are placed where the current state has them.
static CGRect layoutDock(UIView *stockBar, UIView *host, UITabBar *bar, CGRect circles[2], CGRect shapes[2]) {
    NSArray<UIView *> *sources = ((SGRSystemTabBar *)bar).sources;
    NSArray<SGRDockButton *> *buttons = dockButtons(stockBar);
    CGRect pill = pillIn(host, bar);
    CGFloat middle = CGRectGetMidY(pill);
    CGRect left = CGRectMake(CGRectGetMinX(pill), middle - kDockSize / 2, kDockSize, kDockSize);
    CGRect right = CGRectOffset(left, CGRectGetMaxX(pill) - CGRectGetMinX(pill) - kDockSize, 0);
    // The bar's own shapes: the tabs' capsule, and the round search button at the end with a gap between them.
    CGFloat full = pill.size.height;
    CGRect fullRight = CGRectMake(CGRectGetMaxX(pill) - full, CGRectGetMinY(pill), full, full);
    CGRect capsule = CGRectMake(CGRectGetMinX(pill), CGRectGetMinY(pill), CGRectGetMinX(fullRight) - kDockGap - CGRectGetMinX(pill), full);
    if (circles) { circles[0] = left; circles[1] = right; }
    if (shapes) { shapes[0] = capsule; shapes[1] = fullRight; }
    UIColor *accent = SGRAccent();
    for (NSUInteger i = 0; i < 2; i++) {
        SGRDockButton *button = buttons[i];
        UIView *source = sources.count > 1 || i == 0 ? (i == 0 ? sources.firstObject : sources.lastObject) : nil;
        button.source = source;
        if (button.superview != host) [host addSubview:button];
        if (!circles) place(button, sg_minimized ? (i == 0 ? left : right) : (i == 0 ? capsule : fullRight));
        else if (CGRectIsEmpty(button.bounds)) place(button, sg_minimized ? (i == 0 ? capsule : fullRight) : (i == 0 ? left : right));
        if (!source) continue;
        BOOL active = isActive(source);
        UIImage *image = glyphOf(source, active);
        if (image && button.glyph.image != image) button.glyph.image = image;
        UIColor *tint = active ? accent : [UIColor colorWithWhite:1 alpha:0.92];
        if (![button.glyph.tintColor isEqual:tint]) button.glyph.tintColor = tint;
        button.accessibilityLabel = labelIn(source).text;
    }
    // One tab alone has no second button to stand at the right.
    if (sources.count < 2) buttons[1].hidden = YES;
    else buttons[1].hidden = NO;
    CGRect row = CGRectMake(CGRectGetMaxX(left) + kDockGap, middle - kDockSize / 2,
                            CGRectGetMinX(right) - CGRectGetMaxX(left) - 2 * kDockGap, kDockSize);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"tab bar: pill %@, buttons %@ / %@, capsule %@ / %@, row %@ (host %@)", NSStringFromCGRect(pill), NSStringFromCGRect(left),
              NSStringFromCGRect(right), NSStringFromCGRect(capsule), NSStringFromCGRect(fullRight), NSStringFromCGRect(row), NSStringFromCGRect(host.bounds));
    });
    return [host convertRect:row toView:nil];
}

// Minimizing gathers the bar into its two ends; expanding is the reverse, and the buttons are what moves: the first
// widens into the capsule of the tabs, the last grows into the search circle, and the bar's own drawing takes over
// as they arrive, so the circles read as the bar opening out rather than one thing replaced by another.
static void applyMinimized(UIView *stockBar, BOOL animated) {
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!host || !bar || !host.window) return;
    BOOL minimized = sg_minimized;
    CGRect circles[2], shapes[2];
    CGRect row = layoutDock(stockBar, host, bar, circles, shapes);
    // Blocks cannot capture C arrays under ARC; copy the four CGRect values into scalar locals.
    CGRect circle0 = circles[0], circle1 = circles[1];
    CGRect shape0 = shapes[0], shape1 = shapes[1];
    NSArray<SGRDockButton *> *buttons = dockButtons(stockBar);
    bar.userInteractionEnabled = !minimized;
    for (SGRDockButton *button in buttons) button.userInteractionEnabled = minimized;
    SGRDockNowPlayingCard(minimized, row, host, animated);

    void (^move)(void) = ^{
        for (NSUInteger i = 0; i < 2; i++) {
            SGRDockButton *button = buttons[i];
            place(button, minimized ? (i == 0 ? circle0 : circle1) : (i == 0 ? shape0 : shape1));
            [button layoutIfNeeded];
        }
    };
    // A button comes in from where the other state had it, unless it is already showing.
    void (^start)(void) = ^{
        for (NSUInteger i = 0; i < 2; i++) {
            SGRDockButton *button = buttons[i];
            if (button.alpha > 0.01) continue;
            place(button, minimized ? (i == 0 ? shape0 : shape1) : (i == 0 ? circle0 : circle1));
            [button layoutIfNeeded];
        }
    };
    void (^settle)(void) = ^{
        bar.alpha = minimized ? 0 : 1;
        for (SGRDockButton *button in buttons) {
            button.alpha = minimized ? 1 : 0;
            button.glyph.alpha = 1;
        }
    };
    BOOL reduced = UIAccessibilityIsReduceMotionEnabled();
    if (!animated || reduced) {
        [UIView performWithoutAnimation:^{ start(); move(); settle(); }];
        return;
    }
    [UIView performWithoutAnimation:start];
    // Springs with no bounce: a scroll turned around mid-way starts from where the buttons are.
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:move completion:nil];
    UIViewAnimationOptions fade = options | UIViewAnimationOptionCurveEaseInOut;
    if (minimized) {
        [UIView animateWithDuration:0.18 delay:0 options:fade animations:^{ bar.alpha = 0; } completion:nil];
        [UIView animateWithDuration:0.2 delay:0 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.alpha = 1;
        } completion:nil];
        [UIView animateWithDuration:0.2 delay:0.2 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.glyph.alpha = 1;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.12 delay:0 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.glyph.alpha = 0;
        } completion:nil];
        [UIView animateWithDuration:0.25 delay:0.18 options:fade animations:^{ bar.alpha = 1; } completion:nil];
        [UIView animateWithDuration:0.22 delay:0.26 options:fade animations:^{
            for (SGRDockButton *button in buttons) button.alpha = 0;
        } completion:nil];
    }
}

#pragma mark - the system bar

@implementation SGRSystemTabBar

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    // A stock tab chosen for real takes the highlight back from the mod's own tab.
    if (sg_customSource) sg_customSource = nil;
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (!self.holding) forwardTap(self.sources[index]);
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

- (UITabBarItem *)itemAt:(CGPoint)point {
    __block UITabBarItem *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(self, ^(UIView *v) {
        BOOL label = [v isKindOfClass:UILabel.class], glyph = [v isKindOfClass:UIImageView.class];
        if ((!label && !glyph) || v.bounds.size.width < 1) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:self].x - point.x);
        if (distance >= best) return;
        for (UITabBarItem *item in self.items) {
            UIImage *image = glyph ? ((UIImageView *)v).image : nil;
            if (label ? ![((UILabel *)v).text isEqualToString:item.title] : !image || (image != item.image && image != item.selectedImage)) continue;
            best = distance;
            nearest = item;
            break;
        }
    });
    return nearest;
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isHome(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick Home as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

static const CGFloat kFadeRise = 112;
static const NSUInteger kFadeStops = 7;

@interface SGRTabBarHost : UIView
- (void)setFadeVisible:(BOOL)visible;
@end

@implementation SGRTabBarHost {
    CAGradientLayer *_fade;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _fade = [CAGradientLayer layer];
    NSNull *off = NSNull.null;
    _fade.actions = @{@"bounds": off, @"position": off, @"frame": off};
    // Fade to half black on a smoothstep, so there is no edge where it starts.
    NSMutableArray *colors = [NSMutableArray array], *locations = [NSMutableArray array];
    for (NSUInteger i = 0; i < kFadeStops; i++) {
        CGFloat t = (CGFloat)i / (kFadeStops - 1);
        [colors addObject:(id)[UIColor colorWithWhite:0 alpha:0.5 * t * t * (3 - 2 * t)].CGColor];
        [locations addObject:@(t)];
    }
    _fade.colors = colors;
    _fade.locations = locations;
    _fade.hidden = !SGFlag(SGRKeyNavbarBottomGradient, YES);
    [self.layer insertSublayer:_fade atIndex:0];
    return self;
}

- (void)setFadeVisible:(BOOL)visible {
    _fade.hidden = !visible;
    _fade.opacity = visible ? 1 : 0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL visible = SGFlag(SGRKeyNavbarBottomGradient, YES);
    _fade.hidden = !visible;
    _fade.opacity = visible ? 1 : 0;
    CGRect bounds = self.bounds;
    CGRect fade = CGRectMake(0, -kFadeRise, bounds.size.width, bounds.size.height + kFadeRise);
    if (!CGRectEqualToRect(_fade.frame, fade)) _fade.frame = fade;
}

- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    insets.bottom = MAX(0, insets.bottom - sg_room);
    return insets;
}

// Minimized, the row between the two buttons is the now playing card's: a touch there is not the host's.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return sg_minimized && hit == self ? nil : hit;
}
@end

void SGRSetTabBarGradientVisible(BOOL visible) {
    UIView *stockBar = sg_stockBar;
    if (stockBar) syncBar(stockBar);
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    if ([host isKindOfClass:SGRTabBarHost.class]) {
        [(SGRTabBarHost *)host setFadeVisible:visible];
        [host setNeedsLayout];
        [host layoutIfNeeded];
    }
    SGRRefreshTabBar();
}

@interface SGRHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRHomeHold
+ (void)held:(SGRHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRHomeHold alloc] initWithTarget:SGRHomeHold.class action:@selector(held:)]];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
}

#pragma mark - room for the glass bar

static const CGFloat kStockRow = 49;

static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static void syncBar(UIView *stockBar) {
    sg_stockBar = stockBar;

    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
        bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        bar.delegate = bar;
        bar.stockBar = stockBar;
        UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
        hold.delegate = bar;
        [bar addGestureRecognizer:hold];
        bar.hold = hold;
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *accent = SGRAccent();
    if (![bar.tintColor isEqual:accent]) bar.tintColor = accent;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host) continue;
        if (sub.alpha != 0) sub.alpha = 0;
        if (sub.userInteractionEnabled) sub.userInteractionEnabled = NO;
    }
    stockBar.superview.layer.backgroundColor = NULL;

    NSArray<UIView *> *sources = tabItems(stockBar);
    if (!sources.count) return;
    // An item with no title is drawn by UIKit as its glyph alone, centred, on a bar of the same height.
    BOOL hideLabels = SGFlag(SGRKeyNavbarHideLabels, YES);

    if (![sources isEqualToArray:bar.sources]) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : labelIn(source).text image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
        for (UIView *source in sources) {
            UIView *live = iconIn(source);
            id icon = live ? encoreIconOf(live) : nil;
            id variant = [icon respondsToSelector:NSSelectorFromString(@"active")] ? ((id (*)(id, SEL))objc_msgSend)(icon, NSSelectorFromString(@"active")) : nil;
            [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                 [icon respondsToSelector:@selector(name)] ? [icon name] : icon, [variant respondsToSelector:@selector(name)] ? [variant name] : variant,
                 [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
        }
        SGLogLong(@"navbar", out);
    }

    UITabBarItem *selected = nil;
    // The mod's own tab wins while it is last known as the open one; once the custom item is gone from
    // the row, Spotify's own state takes the lead again.
    if (sg_customSource) {
        for (NSUInteger i = 0; i < sources.count; i++)
            if (sources[i] == sg_customSource) { selected = bar.items[i]; break; }
        if (!selected) sg_customSource = nil;
    }
    BOOL missing = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = bar.items[i];
        UIImage *image = glyphOf(sources[i], sources[i] == sg_customSource);
        UIImage *selectedImage = glyphOf(sources[i], YES);
        if (image) item.image = image;
        if (selectedImage) item.selectedImage = selectedImage;
        missing |= !item.image || !item.selectedImage;
        NSString *title = hideLabels ? nil : labelIn(sources[i]).text;
        if (hideLabels ? item.title != nil : title.length && ![title isEqualToString:item.title]) item.title = title;
        if (!selected && isActive(sources[i])) selected = item;
    }
    if (selected && bar.selectedItem != selected) bar.selectedItem = selected;
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    static NSUInteger retries;
    if (missing && retries++ < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            syncBar(stockBar);
        });
    }

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;
    place(bar, host.bounds);
    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    if (host.window) {
        CGRect row = layoutDock(stockBar, host, bar, NULL, NULL);
        if (sg_minimized) SGRDockNowPlayingCard(YES, row, host, NO);
    }
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// Set while the bar lays its items out itself, so each item's pass leaves the work to the bar's one.
static BOOL sg_barPass, sg_itemsLaidOut;

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
// Minimized, the middle of the row is the now playing card's, which lies under this view.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    return sg_minimized && hit == (UIView *)self ? nil : hit;
}
- (void)layoutSubviews {
    %orig;
    SGRComposeTabBar((UIView *)self);
    sg_barPass = YES;
    sg_itemsLaidOut = NO;
    for (UIView *sub in ((UIView *)self).subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class]) [sub layoutIfNeeded];
    }
    sg_barPass = NO;
    if (sg_itemsLaidOut) SGRComposeTabBar((UIView *)self);
    holdHome((UIView *)self);
    syncBar((UIView *)self);
    SGRLogTabBarRow((UIView *)self);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive.
static void itemDidLayOut(UIView *item) {
    if (sg_barPass) {
        sg_itemsLaidOut = YES;
        return;
    }
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
    SGRLogTabBarRow(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
