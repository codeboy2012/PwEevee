#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

static const CGFloat kHairline = 0.5;

static char kRowKey, kSubtitleKey, kLineKey, kAlbumHeaderKey, kAlbumParentKey, kAlbumArtistsKey;
static char kOriginalSubtitleKey, kAppliedSubtitleKey;
static char kExplicitStateKey;

static NSString *normalizedArtist(NSString *artist) {
    NSString *trimmed = [artist stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[trimmed lowercaseString] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:NSLocale.currentLocale];
}

static void addArtistNames(NSString *text, NSMutableSet<NSString *> *names) {
    for (NSString *part in [text componentsSeparatedByString:@","]) {
        NSString *name = normalizedArtist(part);
        if (name.length) [names addObject:name];
    }
}

static NSSet<NSString *> *albumArtists(UIView *page) {
    NSSet<NSString *> *cached = objc_getAssociatedObject(page, &kAlbumArtistsKey);
    if (cached) return cached;
    UIView *header = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader", &kAlbumHeaderKey);
    UIView *parent = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ParentRow", &kAlbumParentKey);
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    SGForEachView(parent, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class]) addArtistNames(((UILabel *)view).text, names);
    });
    addArtistNames(parent.accessibilityLabel, names);
    if (names.count) {
        cached = [names copy];
        objc_setAssociatedObject(page, &kAlbumArtistsKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return cached;
    }
    return names;
}

static void applyArtistFilter(UILabel *label, NSSet<NSString *> *albumArtistNames, BOOL hideAll) {
    NSString *current = label.text ?: @"";
    NSString *original = objc_getAssociatedObject(label, &kOriginalSubtitleKey);
    NSString *applied = objc_getAssociatedObject(label, &kAppliedSubtitleKey);
    if (!original || ![current isEqualToString:applied]) original = current;

    NSMutableArray<NSString *> *visible = [NSMutableArray array];
    if (!hideAll) {
        for (NSString *part in [original componentsSeparatedByString:@","]) {
            NSString *trimmed = [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length && ![albumArtistNames containsObject:normalizedArtist(trimmed)]) [visible addObject:trimmed];
        }
    }
    NSString *filtered = [visible componentsJoinedByString:@", "];
    if (![filtered isEqualToString:current]) label.text = filtered;
    if (![filtered isEqualToString:original]) {
        objc_setAssociatedObject(label, &kOriginalSubtitleKey, original, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(label, &kAppliedSubtitleKey, filtered, OBJC_ASSOCIATION_COPY_NONATOMIC);
    } else {
        objc_setAssociatedObject(label, &kOriginalSubtitleKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(label, &kAppliedSubtitleKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
}

static BOOL explicitMarker(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:NSStringFromClass(view.class) ?: @""];
    if (view.accessibilityIdentifier.length) [parts addObject:view.accessibilityIdentifier];
    if (view.accessibilityLabel.length) [parts addObject:view.accessibilityLabel];
    NSString *identity = [[parts componentsJoinedByString:@" "] lowercaseString];
    return [identity containsString:@"explicit"] || [identity containsString:@"contentrating"] || [identity containsString:@"content-rating"];
}

static void applyExplicitTagFilter(UIView *row, BOOL hide) {
    SGForEachView(row, ^(UIView *view) {
        if (!explicitMarker(view)) return;
        NSArray<NSNumber *> *original = objc_getAssociatedObject(view, &kExplicitStateKey);
        if (hide) {
            if (!original) {
                original = @[@(view.alpha), @(view.userInteractionEnabled), @(view.accessibilityElementsHidden)];
                objc_setAssociatedObject(view, &kExplicitStateKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            view.alpha = 0;
            view.userInteractionEnabled = NO;
            view.accessibilityElementsHidden = YES;
        } else if (original) {
            view.alpha = original[0].doubleValue;
            view.userInteractionEnabled = original[1].boolValue;
            view.accessibilityElementsHidden = original[2].boolValue;
            objc_setAssociatedObject(view, &kExplicitStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyHairline(UIView *row) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    line.backgroundColor = SGRHairline().CGColor;
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGRect frame = CGRectMake(SGRSideMargin, bounds.size.height - kHairline,
                              MAX(0, bounds.size.width - 2 * SGRSideMargin), kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

static void applyRow(UIView *cell, UIView *page, UIView *row) {
    clearSurface(cell);
    if (SGRRevealWaitsFor(page, SGRRevealList) && SGRRevealShowsText(row)) SGRRevealMark(page, SGRRevealList);
    // The row, and every box the element framework wraps it in on the way back up to the cell.
    for (UIView *v = row; v; v = v.superview) {
        clearSurface(v);
        if (v == cell) break;
    }
    applyExplicitTagFilter(row, SGHidden(SGRKeyHideExplicitAlbumTags));

    UIView *subtitle = SGRFindByIdentifier(row, @"EncoreConsumerMobile.View.Granular.Subtitle", &kSubtitleKey);
    BOOL hideAll = SGHidden(SGRKeyHideAllAlbumArtists);
    NSSet<NSString *> *artistsToHide = SGHidden(SGRKeyHideAlbumArtists) ? albumArtists(page) : [NSSet set];
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)v;
        applyArtistFilter(label, artistsToHide, hideAll);
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    applyHairline(row);
}

static UIView *trackRowInCell(UIView *cell) {
    return SGRFindByIdentifier(cell, @"Components.UI.RetrievalRow*", &kRowKey);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes {
    UICollectionViewLayoutAttributes *attributes = %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *row = trackRowInCell(cell);
    if (!row) return attributes;
    UIView *page = SGRAlbumPageOf(cell);
    if (!page) return attributes;
    applyRow(cell, page, row);
    [cell.contentView setNeedsLayout];
    [cell.contentView layoutIfNeeded];
    return %orig(attributes);
}

- (void)layoutSubviews {
    %orig;
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    UIView *row = trackRowInCell(cell);
    if (!row) return;
    UIView *page = SGRAlbumPageOf(cell);
    if (page) applyRow(cell, page, row);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC12Element_List18CollectionViewCell"]);
}
