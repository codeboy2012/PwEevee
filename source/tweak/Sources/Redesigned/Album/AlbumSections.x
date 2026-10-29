#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

// Over the album's own line, and between it and the copyright: the spacers they sat between are gone.
static const CGFloat kLead = 16;

static char kSettledKey, kMeasuredWidthKey;

static BOOL isFooterContent(UIView *content) {
    static NSMutableDictionary<id, NSNumber *> *answers;
    if (!answers) answers = [NSMutableDictionary dictionary];
    Class cls = object_getClass(content);
    if (!cls) return NO;
    NSNumber *answer = answers[(id<NSCopying>)cls];
    if (!answer) {
        answer = @([NSStringFromClass(cls) containsString:@"Album_PageImpl20FooterStructuredData"]);
        answers[(id<NSCopying>)cls] = answer;
    }
    return answer.boolValue;
}

static BOOL isKept(UIView *content) {
    UIView *kept = nil;
    for (NSString *identifier in @[@"Album.ConsumptionExperience", @"Album.Copyright"]) {
        kept = kept ?: SGRFindByIdentifier(content, identifier, NULL);
    }
    if (!kept) return NO;
    SGForEachView(kept, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRTertiary()]) label.textColor = SGRTertiary();
    });
    return YES;
}

static void settle(UICollectionViewCell *cell, CGFloat natural, CGFloat lead) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, @[@(natural), @(lead)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (content.autoresizingMask & UIViewAutoresizingFlexibleHeight) content.autoresizingMask &= ~UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, lead, cell.bounds.size.width, natural);
    if (!CGRectEqualToRect(content.frame, frame)) content.frame = frame;
    BOOL dropped = lead == 0;
    if (content.hidden != dropped) content.hidden = dropped;
    if (!cell.clipsToBounds) cell.clipsToBounds = YES;
    cell.accessibilityElementsHidden = dropped;
}

static void unsettle(UICollectionViewCell *cell) {
    UIView *content = cell.contentView;
    objc_setAssociatedObject(cell, &kSettledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kMeasuredWidthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    content.autoresizingMask |= UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    content.frame = cell.bounds;
    content.hidden = NO;
    cell.clipsToBounds = NO;
    cell.accessibilityElementsHidden = NO;
}

static void logOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign album: %@", what);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *content = cell.contentView.subviews.firstObject;
    // Cells are reused across kinds, and one settled before can hold a track row now.
    if (!isFooterContent(content) || !SGRAlbumPageOf(cell)) {
        if (objc_getAssociatedObject(cell, &kSettledKey)) unsettle(cell);
        return %orig;
    }
    // Measured once per width. Asking Spotify again after settle() has pinned the content gives another answer,
    // and the collection view keeps re-asking until the answer holds still (the watchdog got there first).
    NSArray<NSNumber *> *settled = objc_getAssociatedObject(cell, &kSettledKey);
    NSNumber *measuredWidth = objc_getAssociatedObject(cell, &kMeasuredWidthKey);
    if (settled && measuredWidth && fabs(measuredWidth.doubleValue - attributes.size.width) < 0.5) {
        UICollectionViewLayoutAttributes *again = [attributes copy];
        CGFloat lead = settled[1].doubleValue;
        again.size = CGSizeMake(attributes.size.width, lead > 0 ? settled[0].doubleValue + lead : 0);
        return again;
    }
    UICollectionViewLayoutAttributes *result = %orig;
    CGFloat natural = MAX(1, result.size.height);
    if (isKept(content)) {
        settle(cell, natural, kLead);
        result.size = CGSizeMake(result.size.width, natural + kLead);
        logOnce(@"the album's own line and its copyright kept under the tracks");
    } else {
        settle(cell, natural, 0);
        result.size = CGSizeMake(result.size.width, 0);
        logOnce(@"the sections under the tracks dropped");
    }
    objc_setAssociatedObject(cell, &kMeasuredWidthKey, @(attributes.size.width), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

// The cell's own passes size the content to the cell again.
- (void)layoutSubviews {
    %orig;
    NSArray<NSNumber *> *settled = objc_getAssociatedObject(self, &kSettledKey);
    if (settled) settle((UICollectionViewCell *)self, settled[0].doubleValue, settled[1].doubleValue);
}

- (void)prepareForReuse {
    %orig;
    if (objc_getAssociatedObject(self, &kSettledKey)) unsettle((UICollectionViewCell *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
