// Home redesign: Top picks, the first shelf of cards drawn large the way the Music app draws its top shelf.
//
// A shelf is a Home_CarouselKit.TouchCancellingCollectionView in a cell of the page's list (HomeSections.x), a
// compositional layout of its own with cards 149 by 195 under a 40pt heading (trees: the 393x235 shelf, cards at
// {149, 195}: a square picture over 46pt of text). Its sizes are Spotify's, made by the layout's section provider each
// time the layout is asked for one. So every compositional layout's provider is wrapped, and while the large shelf's
// provider runs, a size kSmallest or more wide is made kScale as wide and taller by as much as it widened: the
// picture grows, the text under it does not. The page's cell is made taller by the same amount.
//
// The shelf drawn large is the one nearest the top of the page: the lowest index any shelf has been measured at.
// Cells are reused across shelves, so each measuring sets or clears the mark on the layout it holds.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

static const CGFloat kScale = 1.4, kSmallest = 120, kHeading = 40;
// Room added under a large card's text, so a long title or an author's name stays inside the glass card.
static const CGFloat kTextRoom = 24;
static char kAuraKey, kAuraShownKey, kAuraImageKey, kAuraTriesKey;
static char kLargeKey, kNaturalKey, kWrappedKey, kWidthKey, kAskedKey;
static _Thread_local BOOL sg_enlarging;
// The narrowest size kSmallest or more wide the running provider made, at Spotify's width: its cards.
static _Thread_local CGFloat sg_cardWidth;
static NSInteger sg_topIndex = NSIntegerMax;
// Where the shortcuts and the top shelf are in the page, to put the shelf first.
static NSIndexPath *sg_shortcutsPath, *sg_topPath;
static NSIndexPath *sg_headingPath;
static __weak UICollectionViewLayout *sg_pageLayout;
static _Thread_local BOOL sg_reordering;
static void stripBase(UIView *cell, NSUInteger depth);

// The layout a wrapped provider belongs to, set once the layout is made.
@interface SGRLayoutBox : NSObject
@property (nonatomic, weak) UICollectionViewCompositionalLayout *layout;
@end
@implementation SGRLayoutBox
@end

static UICollectionViewCompositionalLayoutSectionProvider wrapped(UICollectionViewCompositionalLayoutSectionProvider provider, SGRLayoutBox *box) {
    return ^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> environment) {
        UICollectionViewCompositionalLayout *layout = box.layout;
        if (!layout || !objc_getAssociatedObject(layout, &kLargeKey)) return provider(section, environment);
        BOOL was = sg_enlarging;
        CGFloat wasWidth = sg_cardWidth;
        sg_enlarging = YES;
        sg_cardWidth = 0;
        NSCollectionLayoutSection *made = provider(section, environment);
        if (layout && sg_cardWidth > 0) objc_setAssociatedObject(layout, &kWidthKey, @(sg_cardWidth), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sg_enlarging = was;
        sg_cardWidth = wasWidth;
        return made;
    };
}

static UICollectionViewCompositionalLayout *boxed(UICollectionViewCompositionalLayout *made, SGRLayoutBox *box) {
    box.layout = made;
    if (made) objc_setAssociatedObject(made, &kWrappedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return made;
}

%hook UICollectionViewCompositionalLayout
- (instancetype)initWithSectionProvider:(UICollectionViewCompositionalLayoutSectionProvider)provider
                          configuration:(UICollectionViewCompositionalLayoutConfiguration *)configuration {
    if (!provider || !SGFlag(SGRKeyHomeTopPicks, NO)) return %orig;
    SGRLayoutBox *box = [SGRLayoutBox new];
    return boxed(%orig(wrapped(provider, box), configuration), box);
}
- (instancetype)initWithSectionProvider:(UICollectionViewCompositionalLayoutSectionProvider)provider {
    if (!provider || !SGFlag(SGRKeyHomeTopPicks, NO)) return %orig;
    SGRLayoutBox *box = [SGRLayoutBox new];
    return boxed(%orig(wrapped(provider, box)), box);
}
%end

// How much a card of Spotify's `width` grows: its picture is as wide as it is, so it grows as much in height.
static CGFloat growth(CGFloat width) {
    return round(width * kScale) - width + kTextRoom;
}

%hook NSCollectionLayoutSize
+ (instancetype)sizeWithWidthDimension:(NSCollectionLayoutDimension *)width heightDimension:(NSCollectionLayoutDimension *)height {
    if (!sg_enlarging || !width.isAbsolute || width.dimension < kSmallest) return %orig;
    // The cards come first, then the row that holds them all (1634 by 195 on the phone): the row is as many cards
    // wide, so it widens by kScale too, but grows in height only as much as a card does.
    sg_cardWidth = sg_cardWidth > 0 ? MIN(sg_cardWidth, width.dimension) : width.dimension;
    if (!sg_enlarging || !(height.isAbsolute || height.isEstimated)) return %orig;
    CGFloat grow = growth(sg_cardWidth);
    NSCollectionLayoutDimension *wider = [NSCollectionLayoutDimension absoluteDimension:round(width.dimension * kScale)];
    NSCollectionLayoutDimension *taller = height.isAbsolute ? [NSCollectionLayoutDimension absoluteDimension:height.dimension + grow]
                                                            : [NSCollectionLayoutDimension estimatedDimension:height.dimension + grow];
    return %orig(wider, taller);
}
%end


// The page's layout, with the top shelf (and the heading just above it) laid out before the shortcuts: the two
// blocks trade places, so the page is as tall as it was. Only frames change; the cells are Spotify's.
static NSArray<NSIndexPath *> *pathsBetween(UICollectionView *list, NSIndexPath *from, NSIndexPath *to) {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSInteger sec = from.section; sec <= to.section; sec++) {
        NSInteger count = [list numberOfItemsInSection:sec];
        for (NSInteger item = (sec == from.section ? from.item : 0); item < count; item++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:item inSection:sec];
            if ([path compare:to] == NSOrderedDescending) return paths;
            [paths addObject:path];
        }
    }
    return paths;
}

static NSDictionary<NSIndexPath *, NSValue *> *swappedFrames(UICollectionViewLayout *layout) {
    if (!SGRHomeGlassStyle() || !SGFlag(SGRKeyHomeTopPicks, NO)) return nil;
    UICollectionView *list = layout.collectionView;
    if (!list || !sg_shortcutsPath || !sg_topPath || [sg_shortcutsPath compare:sg_topPath] != NSOrderedAscending) return nil;
    if (sg_pageLayout != layout) return nil;
    NSArray<NSIndexPath *> *paths = pathsBetween(list, sg_shortcutsPath, sg_topPath);
    if (paths.count < 2) return nil;
    sg_reordering = YES;
    NSMutableArray<UICollectionViewLayoutAttributes *> *items = [NSMutableArray array];
    for (NSIndexPath *path in paths) {
        UICollectionViewLayoutAttributes *a = [layout layoutAttributesForItemAtIndexPath:path];
        if (!a) { sg_reordering = NO; return nil; }
        [items addObject:a];
    }
    sg_reordering = NO;
    UICollectionViewLayoutAttributes *shortcuts = items.firstObject, *top = items.lastObject;
    NSMutableArray<UICollectionViewLayoutAttributes *> *order = [NSMutableArray array];
    NSMutableArray<UICollectionViewLayoutAttributes *> *rest = [NSMutableArray array];
    UICollectionViewLayoutAttributes *heading = nil;
    for (NSUInteger i = 1; i + 1 < items.count; i++) {
        // A short cell right before the shelf is its heading.
        if (i + 2 == items.count && items[i].frame.size.height < 80) heading = items[i];
        else [rest addObject:items[i]];
    }
    sg_headingPath = heading.indexPath;
    [order addObject:top];
    [order addObject:shortcuts];
    [order addObjectsFromArray:rest];
    CGFloat gap = MAX(0, CGRectGetMinY(items[1].frame) - CGRectGetMaxY(shortcuts.frame));
    // The top shelf's heading is gone; the room it had goes between the shelf and the shortcuts.
    CGFloat spare = heading ? heading.frame.size.height + gap : 0;
    CGFloat y = CGRectGetMinY(shortcuts.frame);
    NSMutableDictionary *frames = [NSMutableDictionary dictionary];
    for (UICollectionViewLayoutAttributes *a in order) {
        CGRect frame = a.frame;
        frame.origin.y = y;
        frames[a.indexPath] = [NSValue valueWithCGRect:frame];
        y += frame.size.height + gap + (a == top ? spare : 0);
    }
    if (heading) {
        CGRect gone = heading.frame;
        gone.size.height = 0;
        gone.origin.y = CGRectGetMinY(shortcuts.frame);
        frames[heading.indexPath] = [NSValue valueWithCGRect:gone];
    }
    return frames;
}

%hook UICollectionViewCompositionalLayout
- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    if (sg_reordering || !SGFlag(SGRKeyHomeTopPicks, NO) || sg_pageLayout != (UICollectionViewLayout *)self) return %orig;
    NSDictionary *frames = swappedFrames((UICollectionViewLayout *)self);
    if (!frames) return %orig;

    sg_reordering = YES;
    NSArray *visible = %orig(rect);
    sg_reordering = NO;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:visible.count + frames.count];
    NSMutableSet<NSIndexPath *> *included = [NSMutableSet setWithCapacity:visible.count];
    for (UICollectionViewLayoutAttributes *item in visible) {
        UICollectionViewLayoutAttributes *a = item;
        NSValue *moved = a.representedElementCategory == UICollectionElementCategoryCell ? frames[a.indexPath] : nil;
        if (moved) {
            [included addObject:a.indexPath];
            a = [item copy];
            a.frame = moved.CGRectValue;
            if ([a.indexPath isEqual:sg_headingPath]) { a.hidden = YES; a.alpha = 0; }
            if (CGRectIntersectsRect(a.frame, rect)) [out addObject:a];
        } else {
            [out addObject:a];
        }
    }

    // Add only moved cells that entered the requested rect; avoid enumerating the entire Home feed.
    for (NSIndexPath *path in frames) {
        NSValue *frameValue = [frames objectForKey:path];
        if ([included containsObject:path] || !CGRectIntersectsRect(frameValue.CGRectValue, rect)) continue;
        sg_reordering = YES;
        UICollectionViewLayoutAttributes *item = [self layoutAttributesForItemAtIndexPath:path];
        sg_reordering = NO;
        if (!item) continue;
        [included addObject:path];
        UICollectionViewLayoutAttributes *a = [item copy];
        a.frame = frameValue.CGRectValue;
        if ([path isEqual:sg_headingPath]) { a.hidden = YES; a.alpha = 0; }
        [out addObject:a];
    }
    return out;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewLayoutAttributes *a = %orig;
    if (sg_reordering || !SGFlag(SGRKeyHomeTopPicks, NO) || sg_pageLayout != (UICollectionViewLayout *)self || !a) return a;
    NSValue *moved = swappedFrames((UICollectionViewLayout *)self)[path];
    if (!moved) return a;
    a = [a copy];
    a.frame = moved.CGRectValue;
    if ([path isEqual:sg_headingPath]) { a.hidden = YES; a.alpha = 0; }
    return a;
}
%end

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UICollectionView *page = sg_pageLayout.collectionView;
    if (page && cell.superview == page && objc_getAssociatedObject(page, &kAuraKey)) stripBase(cell, 3);
}

- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    static Class shelf;
    if (!shelf) shelf = NSClassFromString(@"_TtC16Home_CarouselKit29TouchCancellingCollectionView");
    UIView *content = ((UICollectionViewCell *)self).contentView.subviews.firstObject;
    // Home's sections only, as HomeSections.x tells them: a shelf on another page is not Home's top.
    if (![NSStringFromClass(object_getClass(content)) containsString:@"Home_EvoPageImpl13HomeStructure"]) return result;
    UIView *root = content.subviews.firstObject;
    UICollectionView *pageList = nil;
    for (UIView *v = ((UIView *)self).superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) { pageList = (UICollectionView *)v; break; }
    }
    if (pageList && pageList.collectionViewLayout != sg_pageLayout) {
        sg_pageLayout = pageList.collectionViewLayout;
        sg_shortcutsPath = sg_topPath = nil;
        sg_headingPath = nil;
        sg_topIndex = NSIntegerMax;
    }
    if (!SGFlag(SGRKeyHomeTopPicks, NO)) return result;
    if (root && ![root isKindOfClass:shelf ?: NSObject.class] && [root isKindOfClass:UICollectionView.class]) {
        UIView *first = ((UICollectionView *)root).visibleCells.firstObject;
        if ([NSStringFromClass(object_getClass(first.subviews.firstObject)) containsString:@"Home_AnchorsAndShortcutsKit"]
            && ![attributes.indexPath isEqual:sg_shortcutsPath]) {
            sg_shortcutsPath = attributes.indexPath;
            [sg_pageLayout invalidateLayout];
        }
    }
    NSInteger index = attributes.indexPath.section * 10000 + attributes.indexPath.item;
    if (!shelf || ![root isKindOfClass:shelf] || result.size.height <= kHeading) {
        // The top's place holds something else now (the feed came again): the next shelf measured takes it.
        if (index == sg_topIndex) sg_topIndex = NSIntegerMax;
        return result;
    }
    UICollectionViewLayout *layout = ((UICollectionView *)root).collectionViewLayout;
    if (index < sg_topIndex) sg_topIndex = index;
    if (index == sg_topIndex && ![attributes.indexPath isEqual:sg_topPath]) {
        sg_topPath = attributes.indexPath;
        [sg_pageLayout invalidateLayout];
    }
    BOOL large = SGFlag(SGRKeyHomeTopPicks, NO) && index == sg_topIndex;
    BOOL was = objc_getAssociatedObject(layout, &kLargeKey) != nil;
    // The shelf's height as Spotify sizes it, from a measuring before it was large.
    if (!was) objc_setAssociatedObject(layout, &kNaturalKey, @(result.size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (large != was) {
        objc_setAssociatedObject(layout, &kLargeKey, large ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [layout invalidateLayout];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            SGLog(@"redesign home: top picks at %ld, its layout %@ (%@)", (long)index, NSStringFromClass(layout.class),
                  objc_getAssociatedObject(layout, &kWrappedKey) ? @"sized by a provider" : @"not made by a provider: left as it is");
        });
    }
    NSNumber *natural = objc_getAssociatedObject(layout, &kNaturalKey);
    // Spotify's height for the shelf: its first measuring can be an estimate (244 for 235), so a lower one replaces
    // it. Measured with its cards drawn large it comes out taller, and is not taken: grown again, it would grow on
    // every pass.
    if (large && natural && result.size.height < natural.doubleValue) {
        natural = @(result.size.height);
        objc_setAssociatedObject(layout, &kNaturalKey, natural, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *card = objc_getAssociatedObject(layout, &kWidthKey);
    // Never shorter than what the shelf lays out: Spotify's height can be taken before its tallest card sized
    // itself (a title on 4 lines), and the shelf then scrolls inside its cell. The shelf's height comes from its
    // cards, not from the cell, so taking it does not feed back.
    if (natural && large && card) result.size = CGSizeMake(result.size.width, MAX(natural.doubleValue + growth(card.doubleValue),
                                                                              ceil(layout.collectionViewContentSize.height)));
    else if (natural && was) result.size = CGSizeMake(result.size.width, natural.doubleValue);
    return result;
}
%end


BOOL SGRHomeShelfIsLarge(UIView *view) {
    static Class shelf;
    if (!shelf) shelf = NSClassFromString(@"_TtC16Home_CarouselKit29TouchCancellingCollectionView");
    for (UIView *v = view.superview; v; v = v.superview) {
        if (shelf && [v isKindOfClass:shelf]) return objc_getAssociatedObject(((UICollectionView *)v).collectionViewLayout, &kLargeKey) != nil;
    }
    return NO;
}

SGModRow *SGRHomeTopPicksRow(void) {
    return SGWithSymbol(SGSwitchRow(@"Top picks", @"Draw Home's first shelf large", SGRKeyHomeTopPicks), @"rectangle.stack");
}

// The cards style themselves as they lay out, which can be before the shelf is large: ask each once more.
static void pokeCards(UICollectionView *shelf) {
    static char kPokedKey;
    NSHashTable *poked = objc_getAssociatedObject(shelf, &kPokedKey);
    if (!poked) {
        poked = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(shelf, &kPokedKey, poked, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UICollectionViewCell *cell in shelf.visibleCells) {
        if ([poked containsObject:cell]) continue;
        [poked addObject:cell];
        void (^poke)(void) = ^{
            SGForEachView(cell, ^(UIView *v) {
                if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.HomeCard"]) [v setNeedsLayout];
            });
        };
        poke();
        __weak UICollectionViewCell *weak = cell;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (weak) poke(); });
    }
}

// The page's gradient: behind the list, in the colour of the cover at the shelf's leading edge, so it changes as the
// large shelf is scrolled. Cells lose their base-surface backgrounds so it shows through.
static UICollectionView *pageListOf(UIView *shelf) {
    for (UIView *v = shelf.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class] && v != shelf) return (UICollectionView *)v;
    }
    return nil;
}

static BOOL isHomeShelf(UICollectionView *shelf) {
    for (UIView *view = shelf; view; view = view.superview) {
        if ([NSStringFromClass(object_getClass(view)) containsString:@"Home_EvoPageImpl13HomeStructure"]) return YES;
    }
    return NO;
}

static UIImage *coverOf(UIView *card) {
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kAuraImageKey);
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class] && ((UIImageView *)sub).image) return ((UIImageView *)sub).image;
    }
    return nil;
}

// Cells made or reused after the gradient came carry Spotify's black again: cleared as they lay out.
static void stripBase(UIView *cell, NSUInteger depth) {
    if (SGIsBaseSurface(cell.layer.backgroundColor)) cell.layer.backgroundColor = NULL;
    if (depth == 0) return;
    for (UIView *sub in cell.subviews) stripBase(sub, depth - 1);
}

static void paintAura(UICollectionView *list, UIColor *color) {
    CAGradientLayer *gradient = objc_getAssociatedObject(list, &kAuraKey);
    if (!gradient) {
        gradient = [CAGradientLayer layer];
        gradient.zPosition = -1;
        gradient.locations = @[@0, @0.35, @1];
        objc_setAssociatedObject(list, &kAuraKey, gradient, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [list.layer insertSublayer:gradient atIndex:0];
        for (UIView *cell in list.subviews) {
            SGForEachView(cell, ^(UIView *v) {
                if (SGIsBaseSurface(v.layer.backgroundColor)) v.layer.backgroundColor = NULL;
            });
        }
    }
    CGFloat over = 600, span = 620;
    CGRect frame = CGRectMake(0, -over - list.adjustedContentInset.top, list.bounds.size.width, over + span);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(gradient.frame, frame)) gradient.frame = frame;
    [CATransaction commit];
    NSArray *to = @[(id)color.CGColor, (id)color.CGColor, (id)[color colorWithAlphaComponent:0].CGColor];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"colors"];
    fade.fromValue = gradient.presentationLayer.colors ?: gradient.colors;
    fade.toValue = to;
    fade.duration = SGRCrossfade;
    [gradient addAnimation:fade forKey:@"colors"];
    gradient.colors = to;
}

static void followAlbum(UICollectionView *shelf) {
    if (!isHomeShelf(shelf)) return;
    if (SGFlag(SGRKeyHomeTopPicks, NO)) pokeCards(shelf);
    if (!SGRHomeGlassStyle()) return;
    UICollectionView *list = pageListOf(shelf);
    if (!list) return;
    UIView *lead = nil;
    CGFloat best = CGFLOAT_MAX, edge = shelf.contentOffset.x + SGRSideMargin;
    for (UICollectionViewCell *cell in shelf.visibleCells) {
        CGFloat d = fabs(CGRectGetMinX(cell.frame) - edge);
        if (d < best) { best = d; lead = cell; }
    }
    UIImage *image = lead ? coverOf(lead) : nil;
    if (!image) {
        // The covers arrive after the first layout: look again until one has.
        NSNumber *tries = objc_getAssociatedObject(shelf, &kAuraTriesKey);
        if (tries.integerValue < 20) {
            objc_setAssociatedObject(shelf, &kAuraTriesKey, @(tries.integerValue + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak UICollectionView *again = shelf;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [again setNeedsLayout];
            });
        }
        return;
    }
    if (objc_getAssociatedObject(shelf, &kAuraShownKey) == image) return;
    objc_setAssociatedObject(shelf, &kAuraShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UICollectionView *weakShelf = shelf;
    SGRPaletteRequest request = {0};
    [SGRPalette paletteForImage:image request:request completion:^(SGRPalette *palette) {
        UICollectionView *s = weakShelf;
        if (!s || !palette || objc_getAssociatedObject(s, &kAuraShownKey) != image) return;
        UICollectionView *page = pageListOf(s);
        // The field colour is dark by design: lift it so the gradient reads like the cover's colour.
        CGFloat h, sat, b, a;
        UIColor *c = palette.fieldColor;
        if ([c getHue:&h saturation:&sat brightness:&b alpha:&a]) c = [UIColor colorWithHue:h saturation:MIN(1, sat * 1.1) brightness:MIN(0.6, MAX(b, 0.1) * 1.9) alpha:1];
        if (page) paintAura(page, c);
    }];
}

// The large shelf's cards sized themselves after its cell was measured and no longer fit: measure the cell again.
%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    if (SGRHomeGlassStyle() || objc_getAssociatedObject(((UICollectionView *)self).collectionViewLayout, &kLargeKey))
        followAlbum((UICollectionView *)self);
}

- (void)setContentSize:(CGSize)size {
    %orig;
    UICollectionView *shelf = (UICollectionView *)self;
    UICollectionViewLayout *layout = shelf.collectionViewLayout;
    if (!objc_getAssociatedObject(layout, &kLargeKey) || size.height <= shelf.bounds.size.height + 0.5) return;
    NSNumber *asked = objc_getAssociatedObject(layout, &kAskedKey);
    if (asked && asked.doubleValue == size.height) return;
    objc_setAssociatedObject(layout, &kAskedKey, @(size.height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *cell = shelf.superview;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell = cell.superview;
    dispatch_async(dispatch_get_main_queue(), ^{ [cell invalidateIntrinsicContentSize]; });
}
%end

%ctor {
    if (!SGRedesignedUI() || (!SGRHomeGlassStyle() && !SGFlag(SGRKeyHomeTopPicks, NO))) return;
    %init;
}
