#import "Core/SGCore.h"
#import "Navbar.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/Links.h"
#import <objc/message.h>

static const CGFloat kIconSize = 24;
static const CGFloat kIconTop = 12.5;
static const CGFloat kLabelTop = 35;
static const CGFloat kLabelHeight = 14;
static char kCustomKey, kOrderKey;

static CGRect sg_iconBox = {{0, kIconTop}, {kIconSize, kIconSize}};
static CGRect sg_labelBox = {{0, kLabelTop}, {0, kLabelHeight}};

static __weak UIView *sg_navbarRoot;
// The bar's row of items, given its frames by placeRow after each of its own passes.
static __weak UIStackView *sg_row;
static UIFont *sg_tabFont;
static NSMutableArray<NSString *> *sg_stockOrder;

static UIColor *itemColor(void) { return [UIColor colorWithWhite:0xB3 / 255.0 alpha:1]; }

#pragma mark - the mod's own items

static UIView *iconView(NSString *name) {
    Class icon = NSClassFromString(@"SPTEncoreIcon");
    Class view = NSClassFromString(@"SPTEncoreIconView");
    SEL glyphSel = NSSelectorFromString(name.length ? name : @"star");
    if (icon && view && [icon respondsToSelector:glyphSel]) {
        id (*glyphFor)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        id glyph = glyphFor(icon, glyphSel);
        SPTEncoreIconView *encore = glyph ? [[view alloc] initWithIcon:glyph] : nil;
        if (encore) {
            [encore setForegroundColor:itemColor()];
            return encore;
        }
    }
    UIImage *image = [UIImage systemImageNamed:@"star.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]];
    UIImageView *fallback = [[UIImageView alloc] initWithImage:image];
    fallback.tintColor = itemColor();
    fallback.contentMode = UIViewContentModeCenter;
    return fallback;
}

@interface SGTabItemView : UIControl
@property (nonatomic, copy) NSString *uri;
- (instancetype)initWithEntry:(NSDictionary *)entry;
- (void)applyEntry:(NSDictionary *)entry;
@end

@implementation SGTabItemView {
    NSString *_iconName;
    UIView *_icon;
    UILabel *_title;
}

- (instancetype)initWithEntry:(NSDictionary *)entry {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _title = [UILabel new];
    _title.textAlignment = NSTextAlignmentCenter;
    _title.textColor = itemColor();
    [self addSubview:_title];
    [self applyEntry:entry];
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)applyEntry:(NSDictionary *)entry {
    self.uri = entry[SGNavbarURI];
    _title.text = entry[SGNavbarTitle];
    NSString *name = entry[SGNavbarIcon] ?: @"star";
    if ([name isEqualToString:_iconName]) return;
    [_icon removeFromSuperview];
    _iconName = [name copy];
    _icon = iconView(name);
    // Encore's views lay themselves out from constraints; this one is placed by frame.
    _icon.translatesAutoresizingMaskIntoConstraints = YES;
    [self addSubview:_icon];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _title.font = sg_tabFont ?: [UIFont systemFontOfSize:10];
    _title.frame = CGRectMake(0, CGRectGetMinY(sg_labelBox), width, CGRectGetHeight(sg_labelBox));
    _icon.frame = CGRectMake((width - CGRectGetWidth(sg_iconBox)) / 2, CGRectGetMinY(sg_iconBox),
                             CGRectGetWidth(sg_iconBox), CGRectGetHeight(sg_iconBox));
}

- (CGSize)intrinsicContentSize {
    return CGSizeMake(kIconSize * 2, kLabelTop + kLabelHeight);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}

// Through the app's own link dispatcher (Shared/Navigation/Links.h).
- (void)open {
    NSURL *url = self.uri.length ? [NSURL URLWithString:self.uri] : nil;
    if (!SGOpenSpotifyURI(url)) SGLog(@"navbar: cannot open %@, dispatcher %@", self.uri, SGLinkDispatcher());
}

@end

#pragma mark - composition

static NSString *stockID(UIView *item) {
    __block NSString *text = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!text && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) text = ((UILabel *)v).text;
    });
    return text ?: NSStringFromClass(item.class);
}

static void measureItem(UIView *item) {
    __block UIView *icon = nil, *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!icon && [NSStringFromClass(v.class) containsString:@"IconView"] && v.bounds.size.width > 1) icon = v;
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = v;
    });
    if (icon) sg_iconBox = SGFrameIn(icon, item);
    if (!label) return;
    sg_labelBox = SGFrameIn(label, item);
    if (!sg_tabFont) sg_tabFont = ((UILabel *)label).font;
}

static NSMutableDictionary<NSString *, SGTabItemView *> *customItems(UIStackView *stack) {
    NSMutableDictionary *items = objc_getAssociatedObject(stack, &kCustomKey);
    if (!items) {
        items = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(stack, &kCustomKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return items;
}

void SGComposeTabBar(UIView *tabBar) {
    UIStackView *stack = SGRowIn(tabBar);
    if (!stack) return;
    sg_navbarRoot = tabBar;

    NSMutableDictionary<NSString *, UIView *> *stockViews = [NSMutableDictionary dictionary];
    for (UIView *item in stack.arrangedSubviews) {
        if ([item isKindOfClass:SGTabItemView.class]) continue;
        NSString *ident = stockID(item);
        if (stockViews[ident]) continue;
        stockViews[ident] = item;
        measureItem(item);
        if (!sg_stockOrder) sg_stockOrder = [NSMutableArray array];
        if (![sg_stockOrder containsObject:ident]) [sg_stockOrder addObject:ident];
    }
    if (sg_stockOrder && ![sg_stockOrder isEqualToArray:SGNavbarStock()]) SGSetNavbarStock(sg_stockOrder);

    NSMutableDictionary<NSString *, SGTabItemView *> *custom = customItems(stack);
    NSMutableArray<UIView *> *wanted = [NSMutableArray array];
    NSMutableSet<NSString *> *placed = [NSMutableSet set];
    NSMutableSet<NSString *> *keep = [NSMutableSet set];

    if (SGEnabled(SGKeyNavbar)) {
        for (NSDictionary *entry in SGNavbarLayout()) {
            NSString *ident = entry[SGNavbarID];
            if (![ident isKindOfClass:NSString.class] || [placed containsObject:ident]) continue;
            [placed addObject:ident];
            BOOL hidden = [entry[SGNavbarHidden] boolValue];
            if (entry[SGNavbarURI]) {
                if (hidden) continue;
                SGTabItemView *item = custom[ident];
                if (item) [item applyEntry:entry];
                else custom[ident] = item = [[SGTabItemView alloc] initWithEntry:entry];
                [keep addObject:ident];
                [wanted addObject:item];
            } else if (stockViews[ident]) {
                stockViews[ident].hidden = hidden;
                [wanted addObject:stockViews[ident]];
            }
        }
    }
    for (NSString *ident in sg_stockOrder) {
        UIView *item = stockViews[ident];
        if (!item || [wanted containsObject:item]) continue;
        item.hidden = NO;
        [wanted addObject:item];
    }
    for (NSString *ident in custom.allKeys) {
        if ([keep containsObject:ident]) continue;
        [custom[ident] removeFromSuperview];
        [custom removeObjectForKey:ident];
    }

    // A bar with nothing on it would strand whoever emptied it, so the last word is Spotify's.
    BOOL empty = YES;
    for (UIView *item in wanted) if (!item.hidden) empty = NO;
    if (empty) for (UIView *item in wanted) item.hidden = NO;

    for (UIView *item in wanted) {
        if ([item isKindOfClass:SGTabItemView.class] && item.superview != stack) [stack addArrangedSubview:item];
    }
    NSMutableArray<UIView *> *order = [NSMutableArray array];
    for (UIView *item in wanted) if (!item.hidden && item.superview == stack) [order addObject:item];
    sg_row = stack;
    if (![order isEqualToArray:objc_getAssociatedObject(stack, &kOrderKey)]) {
        objc_setAssociatedObject(stack, &kOrderKey, order, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stack setNeedsLayout];
    }
}

static void centreContents(UIView *item) {
    SGForEachView(item, ^(UIView *v) {
        if ([v isKindOfClass:%c(SPTEncoreIconView)] || [v isKindOfClass:%c(SPTEncoreLabel)]) v.center = v.center;
    });
}

static void placeRow(UIStackView *stack) {
    NSArray<UIView *> *order = objc_getAssociatedObject(stack, &kOrderKey);
    UIView *bar = sg_navbarRoot;
    if (!order.count || !bar) return;
    CGFloat width = bar.bounds.size.width / order.count;
    CGFloat height = stack.bounds.size.height;
    [order enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
        CGFloat x = [bar convertPoint:CGPointMake(i * width, 0) toView:stack].x;
        CGRect frame = CGRectMake(x, 0, width, height);
        if (!CGAffineTransformIsIdentity(item.transform)) item.transform = CGAffineTransformIdentity;
        if (!CGRectEqualToRect(item.frame, frame)) item.frame = frame;
        centreContents(item);
    }];
}

%hook UIStackView
- (void)layoutSubviews {
    %orig;
    if ((UIStackView *)self == sg_row) placeRow((UIStackView *)self);
}
%end

static CGFloat slotCentreX(UIView *view) {
    UIStackView *row = sg_row;
    if (!row) return NAN;
    UIView *slot = nil;
    for (UIView *v = view; v.superview; v = v.superview) if (v.superview == row) { slot = v; break; }
    if (!slot) return NAN;
    return [slot convertPoint:CGPointMake(CGRectGetMidX(slot.bounds), 0) toView:view.superview].x;
}

%hook SPTEncoreIconView
- (void)setFrame:(CGRect)frame {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) frame.origin.x = centre - frame.size.width / 2;
    %orig(frame);
}
- (void)setCenter:(CGPoint)center {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) center.x = centre;
    %orig(center);
}
%end

%hook SPTEncoreLabel
- (void)setFrame:(CGRect)frame {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) frame.origin.x = centre - frame.size.width / 2;
    %orig(frame);
}
- (void)setCenter:(CGPoint)center {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) center.x = centre;
    %orig(center);
}
%end

void SGRefreshTabBar(void) {
    [sg_navbarRoot setNeedsLayout];
}

void SGLogTabBarRow(UIView *tabBar) {
    UIStackView *stack = SGRowIn(tabBar);
    if (!stack) return;
    NSMutableString *out = [NSMutableString stringWithFormat:@"row in %@ %@, icon %@ label %@, stack %@ axis %ld dist %ld align %ld spacing %.1f autolayout %d",
                            NSStringFromClass(tabBar.class), NSStringFromCGRect(tabBar.frame),
                            NSStringFromCGRect(sg_iconBox), NSStringFromCGRect(sg_labelBox), NSStringFromCGRect(stack.frame),
                            (long)stack.axis, (long)stack.distribution, (long)stack.alignment, stack.spacing,
                            !stack.translatesAutoresizingMaskIntoConstraints];
    NSUInteger index = 0;
    for (UIView *item in stack.arrangedSubviews) {
        [out appendFormat:@"\n  %lu %@ %@%@ autolayout %d", (unsigned long)index++, NSStringFromClass(item.class),
             NSStringFromCGRect(item.frame), item.hidden ? @" hidden" : @"",
             !item.translatesAutoresizingMaskIntoConstraints];
        for (NSLayoutConstraint *c in item.constraints) {
            if (c.firstAttribute == NSLayoutAttributeWidth || c.secondAttribute == NSLayoutAttributeWidth) [out appendFormat:@"\n    %@", c];
        }
    }
    for (NSLayoutConstraint *c in stack.constraints) [out appendFormat:@"\n  own %@", c];
    for (NSLayoutConstraint *c in stack.superview.constraints) {
        if (c.firstItem == stack || c.secondItem == stack) [out appendFormat:@"\n  held %@", c];
    }
    static NSString *last;
    if ([out isEqualToString:last]) return;
    last = [out copy];
    SGLogLong(@"navbar", out);
}

%hook _TtC28NavigationUI_TabBarItemsImpl29TabBarItemsNavigationListImpl
- (NSArray *)items {
    NSArray *items = %orig;
    NSMutableString *out = [NSMutableString stringWithFormat:@"list read, %lu items", (unsigned long)items.count];
    for (id item in items) [out appendFormat:@"\n  %@ · %@", [item valueForKey:@"title"], [item valueForKey:@"viewURI"]];
    static NSString *last;
    if (![out isEqualToString:last]) {
        last = [out copy];
        SGLogLong(@"navbar", out);
    }
    return items;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"SPTEncoreIcon",
        @"SPTEncoreIconView",
        @"SPTEncoreLabel",
        @"_TtC28NavigationUI_TabBarItemsImpl29TabBarItemsNavigationListImpl",
    ]);
}
