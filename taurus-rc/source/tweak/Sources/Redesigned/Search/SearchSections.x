#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

NSString *const SGRSearchListIdentifier = @"BrowsePage.ContentScrollView";

typedef NS_ENUM(NSInteger, SGRSearchKind) {
    SGRSearchKindPending,   // the cell's root is not in yet: left as it is
    SGRSearchKindKeep,
    SGRSearchKindDrop,
};

// The items looked at from the top of the list for the first card before the gap is taken as none.
static const NSInteger kGapItems = 24;

static char kCollapsedKey;

static CGFloat sg_gap;
// Collapses and expansions so far, so a layout pass of the page measures again after one.
static NSUInteger sg_changes;
static __weak UICollectionView *sg_list;
static BOOL sg_measureQueued;

static void logOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign search: %@", what);
}

static BOOL isBrowseCell(UIView *content) {
    if (!content) return NO;
    static NSMutableDictionary *answers;
    if (!answers) answers = [NSMutableDictionary dictionary];
    Class cls = object_getClass(content);
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:@"Browse_BrowsePageImpl15BrowseStructure"]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

static SGRSearchKind kindOf(UIView *root) {
    if (!root) return SGRSearchKindPending;
    return [root.accessibilityIdentifier isEqualToString:@"Components.UI.CategoryCardBrowse"] ? SGRSearchKindKeep : SGRSearchKindDrop;
}

// What a dropped cell holds, for the log: the first identifier in it, else its root's class.
static NSString *describe(UIView *root) {
    __block NSString *identifier = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!identifier && v.accessibilityIdentifier.length) identifier = v.accessibilityIdentifier;
    });
    return identifier ?: NSStringFromClass(root.class);
}

static void shift(UICollectionViewCell *cell) {
    CGAffineTransform moved = CGAffineTransformMakeTranslation(0, -sg_gap);
    if (!CGAffineTransformEqualToTransform(cell.transform, moved)) cell.transform = moved;
}

static void collapse(UICollectionViewCell *cell, CGFloat natural) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kCollapsedKey, @(natural), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    if (!content.hidden) content.hidden = YES;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
    cell.accessibilityElementsHidden = YES;
}

static void expand(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kCollapsedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    content.hidden = NO;
    cell.clipsToBounds = NO;
    cell.accessibilityElementsHidden = NO;
}

// The top of the first item with a height, when every item above it has none; 0 when the list starts with one.
static CGFloat measure(UICollectionView *list) {
    BOOL collapsedAbove = NO;
    NSInteger seen = 0;
    NSInteger sections = list.numberOfSections;
    for (NSInteger section = 0; section < sections; section++) {
        NSInteger items = [list numberOfItemsInSection:section];
        for (NSInteger item = 0; item < items; item++) {
            if (++seen > kGapItems) return 0;
            UICollectionViewLayoutAttributes *attributes = [list layoutAttributesForItemAtIndexPath:[NSIndexPath indexPathForItem:item inSection:section]];
            if (!attributes) return 0;
            if (attributes.frame.size.height < 1) {
                collapsedAbove = YES;
                continue;
            }
            return collapsedAbove ? MAX(0, CGRectGetMinY(attributes.frame)) : 0;
        }
    }
    return 0;
}

void SGRSearchCloseGap(UICollectionView *list) {
    if (!list) return;
    static CGSize lastSize;
    static NSUInteger lastChanges = NSUIntegerMax;
    static __weak UICollectionView *lastList;
    CGSize size = list.contentSize;
    if (list == lastList && sg_changes == lastChanges && CGSizeEqualToSize(size, lastSize)) return;
    sg_list = lastList = list;
    lastChanges = sg_changes;
    lastSize = size;

    CGFloat gap = measure(list);
    if (gap == sg_gap) return;
    sg_gap = gap;
    SGLog(@"redesign search: cards moved up %.0fpt, the spacing the collapsed sections above them leave", gap);
    for (UIView *sub in list.subviews) {
        if ([sub isKindOfClass:UICollectionViewCell.class] && isBrowseCell(((UICollectionViewCell *)sub).contentView)) {
            shift((UICollectionViewCell *)sub);
        }
    }
}

// After the pass that sized the cell: the list's attributes take the new height when that pass ends.
static void measureSoon(void) {
    if (sg_measureQueued) return;
    sg_measureQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_measureQueued = NO;
        SGRSearchCloseGap(sg_list);
    });
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView;
    if (!isBrowseCell(content)) return %orig;
    UICollectionViewLayoutAttributes *result = %orig;

    UIView *root = content.subviews.firstObject.subviews.firstObject;
    SGRSearchKind kind = kindOf(root);
    BOOL collapsed = objc_getAssociatedObject(cell, &kCollapsedKey) != nil;
    if (kind == SGRSearchKindDrop) {
        collapse(cell, MAX(1, result.size.height));
        result.size = CGSizeMake(result.size.width, 0);
        if (!collapsed) {
            sg_changes++;
            measureSoon();
        }
        logOnce([@"dropped " stringByAppendingString:describe(root)]);
    } else if (kind == SGRSearchKindKeep && collapsed) {
        // Cells are reused across kinds: one collapsed before holds a card now.
        expand(cell);
        sg_changes++;
        measureSoon();
    }
    return result;
}

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)attributes {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    if (isBrowseCell(cell.contentView)) shift(cell);
}

// The cell's own passes may size the content to the cell again, and a cell laid out before the gap was known takes it here.
- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    NSNumber *natural = objc_getAssociatedObject(cell, &kCollapsedKey);
    if (natural) collapse(cell, natural.doubleValue);
    if (sg_gap > 0 && isBrowseCell(cell.contentView)) shift(cell);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kCollapsedKey)) expand((UICollectionViewCell *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
