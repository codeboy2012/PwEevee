#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Player.h"
#import "SGRPlayerMenu.h"

// A sheet this soon after the ⋯'s tap is the player's.
static const NSTimeInterval kMenuAfterTap = 3;
static const NSTimeInterval kRowsWait = 4;
// The black behind the card; Spotify's dimming is 0.7, which is a sheet's and not a menu's.
static const CGFloat kDimming = 0.2;
// A sheet hidden as its presentation begins and still without a menu taken over by then is shown again.
static const NSTimeInterval kClaimWait = 1;
// How often the table is looked at while the card waits for Spotify's rows.
static const NSTimeInterval kRowsPoll = 0.05;
// The rows of the last menu, for the next one to open on.
static NSString *const kLastRowsKey = @"spotifyglass.redesign.player.menuRows";

// Whether the hooks are in, so the ⋯ is watched only when a menu can be taken over.
static BOOL sgr_menuOn;
static __weak UIView *sgr_moreButton;
static NSTimeInterval sgr_moreTappedAt;
static char kTakeoverKey, kWatchedKey, kDimmingKey, kMaskKey, kSavedMaskKey, kClaimKey, kTakenKey, kHiddenDimmingsKey;

#pragma mark - where each of Spotify's rows goes

typedef NS_ENUM(NSInteger, SGRPlayerMenuPlace) {
    SGRPlaceMore,          // under More, the default for a number not known here
    SGRPlaceTile,          // the row of three across the top
    SGRPlaceMain,          // the first group of rows
    SGRPlaceFeedback,      // with More
    SGRPlaceDestructive,   // last, in red
};

typedef struct {
    const char *identifier;
    SGRPlayerMenuPlace place;
    const char *symbol;
} SGRPlayerMenuKnownRow;

static const SGRPlayerMenuKnownRow kKnown[] = {
    {"19", SGRPlaceTile, "text.badge.plus"},                              // Add to playlist
    {"11", SGRPlaceTile, "text.line.last.and.arrowtriangle.forward"},     // Add to Queue
    {"9", SGRPlaceTile, "square.and.arrow.up"},                           // Share
    {"59", SGRPlaceFeedback, "hand.thumbsdown"},                          // Exclude track from your taste profile
    {"27", SGRPlaceDestructive, "minus.circle"},                          // Remove from this playlist
    {"28", SGRPlaceMore, "quote.bubble"},                                 // Lyrics • On/Off: the redesign shows its own
    {"34", SGRPlaceMore, "list.bullet"},                                  // Go to Queue: the footer has the queue glyph
};

static const SGRPlayerMenuKnownRow *knownRow(NSString *identifier) {
    for (size_t i = 0; i < sizeof(kKnown) / sizeof(kKnown[0]); i++) {
        if ([identifier isEqualToString:@(kKnown[i].identifier)]) return &kKnown[i];
    }
    return NULL;
}

static UIImage *symbol(NSString *name) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    return name ? [UIImage systemImageNamed:name withConfiguration:config] : nil;
}

#pragma mark - the player's ⋯

@interface SGRPlayerMoreTapWatcher : NSObject <UIGestureRecognizerDelegate>
@end

@implementation SGRPlayerMoreTapWatcher
- (void)tapped:(id)sender {
    UIView *button = [sender isKindOfClass:UIGestureRecognizer.class] ? ((UIGestureRecognizer *)sender).view : sender;
    sgr_moreButton = button;
    sgr_moreTappedAt = CACurrentMediaTime();
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end

void SGRPlayerMenuWatchMoreButton(UIView *button) {
    if (!sgr_menuOn || !button || objc_getAssociatedObject(button, &kWatchedKey)) return;
    static SGRPlayerMoreTapWatcher *watcher;
    if (!watcher) watcher = [SGRPlayerMoreTapWatcher new];
    objc_setAssociatedObject(button, &kWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([button isKindOfClass:UIControl.class]) {
        [(UIControl *)button addTarget:watcher action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside | UIControlEventPrimaryActionTriggered];
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:watcher action:@selector(tapped:)];
    tap.cancelsTouchesInView = NO;
    tap.delaysTouchesEnded = NO;
    tap.delegate = watcher;
    [button addGestureRecognizer:tap];
}

#pragma mark - Spotify's rows, read

@interface SGRPlayerMenuSpotifyRow : NSObject
@property (nonatomic, strong) NSIndexPath *indexPath;
@property (nonatomic, copy) NSString *identifier, *title, *subtitle;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL disabled;
@end

@implementation SGRPlayerMenuSpotifyRow
@end

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (!root || depth > 6) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static NSInteger rowCount(UITableView *table) {
    NSInteger rows = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) rows += [table numberOfRowsInSection:section];
    return rows;
}

// The ListRow of a cell: the control that carries the item's number.
static UIControl *listRowIn(UITableViewCell *cell) {
    __block UIControl *found = nil;
    SGForEachView(cell.contentView, ^(UIView *v) {
        if (!found && [v isKindOfClass:UIControl.class] && v.accessibilityIdentifier.length) found = (UIControl *)v;
    });
    return found;
}

static BOOL shown(UIView *view, UIView *within) {
    for (UIView *v = view; v && v != within; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

static SGRPlayerMenuSpotifyRow *readRow(UITableViewCell *cell, NSIndexPath *indexPath) {
    UIControl *control = listRowIn(cell);
    if (!control) return nil;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    __block UIImageView *glyph = nil;
    SGForEachView(control, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length && shown(v, control)) [labels addObject:(UILabel *)v];
        if (!glyph && [v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image && v.bounds.size.width <= 40 && shown(v, control)) glyph = (UIImageView *)v;
    });
    if (!labels.count) return nil;
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGPoint pa = [a convertPoint:CGPointZero toView:control], pb = [b convertPoint:CGPointZero toView:control];
        if (fabs(pa.y - pb.y) > 1) return pa.y < pb.y ? NSOrderedAscending : NSOrderedDescending;
        return pa.x < pb.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    SGRPlayerMenuSpotifyRow *row = [SGRPlayerMenuSpotifyRow new];
    row.indexPath = indexPath;
    row.identifier = control.accessibilityIdentifier;
    row.title = labels[0].text;
    if (labels.count > 1) row.subtitle = labels[1].text;
    // "Lyrics • Off" is one label of Spotify's: its state goes under the words, the way the Music app puts it.
    NSRange dot = [row.title rangeOfString:@" • "];
    if (!row.subtitle && dot.location != NSNotFound && dot.location > 0) {
        row.subtitle = [row.title substringFromIndex:NSMaxRange(dot)];
        row.title = [row.title substringToIndex:dot.location];
    }
    row.image = glyph.image;
    row.disabled = !control.enabled || !shown(control, cell);
    return row;
}

static void withEveryCell(UITableView *table, void (^block)(void)) {
    CGRect saved = table.bounds;
    [table layoutIfNeeded];
    UIEdgeInsets insets = table.adjustedContentInset;
    BOOL grown = NO;
    for (int round = 0; round < 3; round++) {
        NSInteger sections = table.numberOfSections;
        CGFloat content = table.contentSize.height;
        if (sections) content = MAX(content, CGRectGetMaxY([table rectForSection:sections - 1]));
        CGRect wanted = CGRectMake(saved.origin.x, -insets.top, saved.size.width, MAX(content + insets.top + insets.bottom, saved.size.height));
        if (CGRectEqualToRect(table.bounds, wanted)) break;
        table.bounds = wanted;
        grown = YES;
        [table layoutIfNeeded];
    }
    block();
    if (grown) {
        table.bounds = saved;
        [table layoutIfNeeded];
    }
}

static NSArray<SGRPlayerMenuSpotifyRow *> *readRows(UITableView *table, BOOL *complete) {
    NSInteger count = rowCount(table);
    *complete = NO;
    if (!count) return @[];
    NSMutableArray<SGRPlayerMenuSpotifyRow *> *rows = [NSMutableArray array];
    __block NSInteger cells = 0;
    withEveryCell(table, ^{
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            for (NSInteger item = 0; item < [table numberOfRowsInSection:section]; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:item inSection:section];
                UITableViewCell *cell = [table cellForRowAtIndexPath:indexPath];
                if (cell) cells++;
                SGRPlayerMenuSpotifyRow *row = cell ? readRow(cell, indexPath) : nil;
                if (row) [rows addObject:row];
            }
        }
    });
    *complete = cells == count;
    if (!*complete) {
        static int logged;
        if (logged++ < 3) SGLog(@"redesign player menu: %ld of the table's %ld rows had a cell to read", (long)cells, (long)count);
    }
    return rows;
}

static NSString *signatureOf(NSArray<SGRPlayerMenuSpotifyRow *> *rows) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) [parts addObject:[NSString stringWithFormat:@"%@=%@|%@|%d", row.identifier, row.title, row.subtitle ?: @"", row.disabled]];
    return [parts componentsJoinedByString:@", "];
}

// Every number once, with its words and where it went, so kKnown can grow from the log.
static void logNumbers(NSArray<SGRPlayerMenuSpotifyRow *> *rows) {
    static NSMutableSet<NSString *> *seen;
    if (!seen) seen = [NSMutableSet set];
    NSMutableArray<NSString *> *fresh = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) {
        if ([seen containsObject:row.identifier]) continue;
        [seen addObject:row.identifier];
        [fresh addObject:[NSString stringWithFormat:@"%@ \"%@\"%@", row.identifier, row.title, knownRow(row.identifier) ? @"" : @" (under More)"]];
    }
    if (fresh.count) SGLog(@"redesign player menu: Spotify's rows %@", [fresh componentsJoinedByString:@", "]);
}

#pragma mark - the rows of the last menu

static NSArray<SGRPlayerMenuSpotifyRow *> *sgr_lastRows;
static NSString *sgr_lastSignature;

static NSArray<SGRPlayerMenuSpotifyRow *> *lastRows(void) {
    if (sgr_lastRows) return sgr_lastRows;
    NSData *data = [NSUserDefaults.standardUserDefaults dataForKey:kLastRowsKey];
    if (!data) return nil;
    NSSet *classes = [NSSet setWithObjects:NSArray.class, NSDictionary.class, NSString.class, NSNumber.class, UIImage.class, nil];
    id stored = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
    NSMutableArray<SGRPlayerMenuSpotifyRow *> *rows = [NSMutableArray array];
    for (NSDictionary *entry in [stored isKindOfClass:NSArray.class] ? stored : @[]) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"id"] isKindOfClass:NSString.class] || ![entry[@"title"] isKindOfClass:NSString.class]) continue;
        SGRPlayerMenuSpotifyRow *row = [SGRPlayerMenuSpotifyRow new];
        row.identifier = entry[@"id"];
        row.title = entry[@"title"];
        row.subtitle = [entry[@"subtitle"] isKindOfClass:NSString.class] ? entry[@"subtitle"] : nil;
        row.image = [entry[@"image"] isKindOfClass:UIImage.class] ? entry[@"image"] : nil;
        row.disabled = [entry[@"disabled"] boolValue];
        [rows addObject:row];
    }
    sgr_lastRows = rows.count ? rows : nil;
    sgr_lastSignature = sgr_lastRows ? signatureOf(sgr_lastRows) : nil;
    return sgr_lastRows;
}

// Kept only when they differ from what is kept. A row the card draws with a glyph of its own keeps no picture.
static void keepRows(NSArray<SGRPlayerMenuSpotifyRow *> *rows, NSString *signature) {
    if ([signature isEqualToString:sgr_lastSignature]) return;
    sgr_lastRows = rows;
    sgr_lastSignature = signature;
    NSMutableArray *stored = [NSMutableArray array], *bare = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) {
        NSMutableDictionary *entry = [@{@"id": row.identifier, @"title": row.title, @"disabled": @(row.disabled)} mutableCopy];
        if (row.subtitle) entry[@"subtitle"] = row.subtitle;
        [bare addObject:[entry copy]];
        if (row.image && !knownRow(row.identifier)) entry[@"image"] = row.image;
        [stored addObject:entry];
    }
    // A picture that does not archive costs the pictures, not the rows.
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:stored requiringSecureCoding:YES error:nil]
        ?: [NSKeyedArchiver archivedDataWithRootObject:bare requiringSecureCoding:YES error:nil];
    if (data) [NSUserDefaults.standardUserDefaults setObject:data forKey:kLastRowsKey];
}

#pragma mark - the takeover of one sheet

@interface SGRPlayerMenuTakeover : NSObject
@property (nonatomic, weak) UIViewController *menu;
@property (nonatomic, weak) UIViewController *sheet;   // the presented container the menu is in
@property (nonatomic, strong) SGRPlayerMenuCard *card;
@property (nonatomic, strong) UIControl *catcher;      // under the card: the dimming, and a tap outside
@property (nonatomic, weak) UIView *button;
@property (nonatomic, copy) NSString *signature;
@property (nonatomic) BOOL hasRows, complete, revealed, closing, grown;
// Showing the last menu's rows until Spotify's are in; a row tapped meanwhile, fired once they are.
@property (nonatomic) BOOL provisional;
@property (nonatomic, copy) NSString *pendingIdentifier;
@property (nonatomic) NSTimeInterval pendingAt;
// Spotify's rows as last read, by number, for a row of the card made from the last menu's to fire.
@property (nonatomic, copy) NSDictionary<NSString *, SGRPlayerMenuSpotifyRow *> *rowsByIdentifier;
@property (nonatomic) NSTimeInterval tappedAt;
@property (nonatomic, strong) NSTimer *poll;
@property (nonatomic, strong) id speedObserver;
@end

@implementation SGRPlayerMenuTakeover
- (void)dealloc {
    if (_speedObserver) [NSNotificationCenter.defaultCenter removeObserver:_speedObserver];
    [_poll invalidate];
}

- (void)catcherTapped {
    UIViewController *sheet = self.sheet;
    SGLog(@"redesign player menu: a tap outside the card closes it");
    [sheet dismissViewControllerAnimated:YES completion:nil];
}
@end

static void fire(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row);

static UIViewController *presentedSheet(UIViewController *menu) {
    UIViewController *top = menu;
    while (top.parentViewController) top = top.parentViewController;
    return top.presentingViewController ? top : nil;
}

static UIView *sheetViewOf(UIViewController *sheet) {
    return sheet.presentationController.presentedView ?: sheet.viewIfLoaded;
}

static UIView *dimmingIn(UIView *container) {
    return SGRFindByIdentifier(container, @"Components.UI.SheetPresentation.Dimming", &kDimmingKey);
}

static void hideSystemDimming(UIView *container) {
    static Class dimmingClass;
    if (!dimmingClass) dimmingClass = NSClassFromString(@"UIDimmingView");
    UIWindow *window = container.window;
    if (!dimmingClass || !window) return;
    NSHashTable *hidden = objc_getAssociatedObject(container, &kHiddenDimmingsKey);
    NSMutableArray<UIView *> *level = [window.subviews mutableCopy];
    for (int depth = 0; depth < 3 && level.count; depth++) {
        NSMutableArray<UIView *> *next = [NSMutableArray array];
        for (UIView *view in level) {
            if ([view isKindOfClass:dimmingClass]) {
                if (view.hidden) continue;
                view.hidden = YES;
                if (view.superview != container) {
                    if (!hidden) {
                        hidden = [NSHashTable weakObjectsHashTable];
                        objc_setAssociatedObject(container, &kHiddenDimmingsKey, hidden, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    }
                    [hidden addObject:view];
                }
            } else {
                [next addObjectsFromArray:view.subviews];
            }
        }
        level = next;
    }
}

static void showSystemDimming(UIView *container) {
    NSHashTable *hidden = objc_getAssociatedObject(container, &kHiddenDimmingsKey);
    for (UIView *view in hidden) view.hidden = NO;
    objc_setAssociatedObject(container, &kHiddenDimmingsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void hidePresentation(UIView *sheet, UIView *container) {
    CALayer *mask = objc_getAssociatedObject(sheet, &kMaskKey);
    if (sheet && !mask) {
        mask = [CALayer layer];
        mask.frame = CGRectMake(0, 0, 1, 1);
        mask.backgroundColor = UIColor.clearColor.CGColor;
        objc_setAssociatedObject(sheet, &kMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(sheet, &kSavedMaskKey, sheet.layer.mask ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (sheet.layer.mask != mask) sheet.layer.mask = mask;
    if (!sheet.hidden) sheet.hidden = YES;
    if (sheet.userInteractionEnabled) sheet.userInteractionEnabled = NO;
    sheet.accessibilityElementsHidden = YES;
    UIView *dimming = dimmingIn(container);
    if (dimming && !dimming.hidden) dimming.hidden = YES;
    hideSystemDimming(container);
}

static void showPresentation(UIView *sheet, UIView *container) {
    dimmingIn(container).hidden = NO;
    showSystemDimming(container);
    id saved = objc_getAssociatedObject(sheet, &kSavedMaskKey);
    sheet.alpha = 0;
    sheet.hidden = NO;
    sheet.layer.mask = saved == NSNull.null ? nil : saved;
    objc_setAssociatedObject(sheet, &kMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(sheet, &kSavedMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sheet.userInteractionEnabled = YES;
    sheet.accessibilityElementsHidden = NO;
    [UIView animateWithDuration:0.25 animations:^{ sheet.alpha = 1; }];
}

static void hideSheet(SGRPlayerMenuTakeover *t, UIView *container) {
    hidePresentation(sheetViewOf(t.sheet), container);
}

static void placeCard(SGRPlayerMenuTakeover *t, UIView *container) {
    if (!t.revealed) hideSheet(t, container);
    UIView *button = t.button;
    CGRect anchor = button.window && button.window == container.window ? [button convertRect:button.bounds toView:container] : CGRectNull;
    CGFloat width = SGRPlayerMenuWidth, right, top;
    if (!CGRectIsNull(anchor)) {
        right = CGRectGetMaxX(anchor) - 2;
        top = CGRectGetMinY(anchor) + 2;
    } else {
        right = container.bounds.size.width - SGRSideMargin;
        top = container.safeAreaInsets.top + SGRGrid;
    }
    CGFloat x = MAX(SGRSideMargin, right - width);
    CGFloat bottom = container.bounds.size.height - MAX(container.safeAreaInsets.bottom, SGRSideMargin) - SGRGrid;
    t.card.maxHeight = MAX(120, bottom - top);
    CGFloat height = MIN(t.card.preferredHeight, t.card.maxHeight);
    // Bounds and centre, not the frame: the card may be mid-growth, under a transform.
    t.card.bounds = CGRectMake(0, 0, width, height);
    t.card.center = CGPointMake(x + width / 2, top + height / 2);
    t.catcher.frame = container.bounds;
}

static CGPoint anchorInCard(SGRPlayerMenuTakeover *t) {
    UIView *button = t.button;
    if (!button.window) return CGPointMake(t.card.bounds.size.width - SGRGlassCircleSize / 2, SGRGlassCircleSize / 2);
    return [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:t.card];
}

static void closeCard(SGRPlayerMenuTakeover *t) {
    if (t.closing) return;
    t.closing = YES;
    SGRPlayerMenuCard *card = t.card;
    UIControl *catcher = t.catcher;
    catcher.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.22 animations:^{ catcher.alpha = 0; } completion:^(BOOL finished) { [catcher removeFromSuperview]; }];
    [card shrinkAway:^{ [card removeFromSuperview]; }];
}

// Spotify's sheet as Spotify draws it, and the card gone.
static void reveal(SGRPlayerMenuTakeover *t, NSString *why) {
    if (t.revealed || t.closing) return;
    t.revealed = YES;
    SGLog(@"redesign player menu: Spotify's sheet shown, %@", why);
    objc_setAssociatedObject(t.sheet, &kClaimKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    showPresentation(sheetViewOf(t.sheet), t.sheet.presentationController.containerView);
    closeCard(t);
    t.closing = NO;
}

static void hold(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row) {
    NSTimeInterval at = CACurrentMediaTime();
    t.pendingIdentifier = row.identifier;
    t.pendingAt = at;
    SGLog(@"redesign player menu: \"%@\" (%@) tapped %.2f s after the ⋯, before Spotify's rows are in, held", row.title, row.identifier, at - t.tappedAt);
    __weak SGRPlayerMenuTakeover *weak = t;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRowsWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPlayerMenuTakeover *strong = weak;
        if (!strong || !strong.pendingIdentifier || strong.pendingAt != at) return;
        reveal(strong, [NSString stringWithFormat:@"a row was tapped and Spotify's rows are still not in %.0f s later", kRowsWait]);
    });
}

#pragma mark building the card

static SGRPlayerMenuItem *itemFor(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row, const SGRPlayerMenuKnownRow *known) {
    __weak SGRPlayerMenuTakeover *weak = t;
    UIImage *image = (known ? symbol(@(known->symbol)) : nil) ?: row.image;
    NSString *identifier = row.identifier;
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:row.title image:image action:^{
        SGRPlayerMenuTakeover *strong = weak;
        if (!strong) return;
        if (strong.provisional) {
            hold(strong, row);
            return;
        }
        fire(strong, strong.rowsByIdentifier[identifier] ?: row);
    }];
    item.subtitle = row.subtitle;
    item.disabled = row.disabled;
    item.key = row.identifier;
    item.destructive = known && known->place == SGRPlaceDestructive;
    return item;
}

static SGRPlayerMenuItem *speedAndPitchItem(void) {
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"Speed, pitch and reverb" image:symbol(@"slider.horizontal.3") action:nil];
    item.key = @"spotifyglass.speedPitch";
    item.subtitle = SGSpeedPitchSummary();
    item.makeExpansion = ^UIView *{ return SGSpeedPitchPanelMake(); };
    item.expansionHeight = SGSpeedPitchPanelHeight();
    return item;
}

static SGRPlayerMenuItem *lockScreenStyleItem(SGRPlayerMenuTakeover *takeover) {
    __weak SGRPlayerMenuTakeover *weak = takeover;
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"Lock Screen Style" image:symbol(@"star") action:nil];
    item.key = @"spotifyglass.lockScreenStyle";
    NSString *current = SGLockScreenCurrentStarView() ?: @"default";
    item.subtitle = SGLockScreenStarViewName(current);
    NSMutableArray<SGRPlayerMenuItem *> *choices = [NSMutableArray array];
    for (NSString *view in SGLockScreenAvailableStarViews()) {
        SGRPlayerMenuItem *choice = [SGRPlayerMenuItem itemWithTitle:SGLockScreenStarViewName(view) image:nil action:^{
            SGLockScreenStarSelectView(view);
            [weak.card setSubtitle:SGLockScreenStarViewName(view) forKey:@"spotifyglass.lockScreenStyle"];
        }];
        choice.key = [@"spotifyglass.lockScreenStyle." stringByAppendingString:view];
        [choices addObject:choice];
    }
    item.children = choices;
    return item;
}

static SGRPlayerMenuItem *backgroundStyleItem(SGRPlayerMenuTakeover *takeover) {
    NSArray<NSString *> *names = SGRPlayerBackgroundNames();
    SGRPlayerBackgroundKind current = SGRPlayerBackground();
    __weak SGRPlayerMenuTakeover *weak = takeover;
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"Background Style"
                                                         image:symbol(@"circle.lefthalf.filled") action:nil];
    item.key = @"spotifyglass.playerBackground";
    item.subtitle = names[(NSUInteger)current];
    NSMutableArray<SGRPlayerMenuItem *> *choices = [NSMutableArray arrayWithCapacity:names.count];
    for (NSUInteger index = 0; index < names.count; index++) {
        SGRPlayerBackgroundKind kind = (SGRPlayerBackgroundKind)index;
        SGRPlayerMenuItem *choice = [SGRPlayerMenuItem itemWithTitle:names[index] image:nil action:^{
            SGRPlayerMenuSetBackground(kind);
            [weak.card setSubtitle:SGRPlayerBackgroundNames()[(NSUInteger)kind] forKey:@"spotifyglass.playerBackground"];
        }];
        choice.key = [NSString stringWithFormat:@"spotifyglass.playerBackground.%lu", (unsigned long)index];
        [choices addObject:choice];
    }
    item.children = choices;
    return item;
}

static SGRPlayerMenuItem *lyricsBlurItem(SGRPlayerMenuTakeover *takeover) {
    __weak SGRPlayerMenuTakeover *weak = takeover;
    BOOL enabled = SGRPlayerMotionLyricsBlurEnabled();
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"Lyrics Background Blur"
                                                         image:symbol(@"drop.halffull") action:nil];
    item.key = @"spotifyglass.playerLyricsBlur";
    item.subtitle = enabled ? @"On" : @"Off";
    item.disabled = !SGKaraokePlayingTrack().length;

    NSMutableArray<SGRPlayerMenuItem *> *choices = [NSMutableArray arrayWithCapacity:2];
    for (NSNumber *value in @[@YES, @NO]) {
        BOOL choiceEnabled = value.boolValue;
        NSString *title = choiceEnabled ? @"On" : @"Off";
        SGRPlayerMenuItem *choice = [SGRPlayerMenuItem itemWithTitle:title image:nil action:^{
            if (!SGKaraokePlayingTrack().length) {
                SGLog(@"redesign player menu: cannot change lyrics blur without a playing track");
                return;
            }
            SGRPlayerMotionSetLyricsBlurEnabled(choiceEnabled);
            [weak.card setSubtitle:title forKey:@"spotifyglass.playerLyricsBlur"];
        }];
        choice.key = [@"spotifyglass.playerLyricsBlur." stringByAppendingString:title.lowercaseString];
        [choices addObject:choice];
    }
    item.children = choices;
    return item;
}

static SGRPlayerMenuItem *lyricsSourceItem(SGRPlayerMenuTakeover *takeover) {
    __weak SGRPlayerMenuTakeover *weak = takeover;
    NSArray<SGLyricsProvider *> *providers = SGLyricsAllProviders();
    NSString *track = SGKaraokePlayingTrack();
    NSString *selectedKey = SGLyricsProviderForTrack(track);
    SGLyricsProvider *selectedProvider = SGLyricsProviderFor(selectedKey);
    SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"Lyrics Source"
                                                         image:symbol(@"text.quote") action:nil];
    item.key = @"spotifyglass.playerLyricsSource";
    item.subtitle = selectedProvider.name ?: @"Automatic";
    item.disabled = !track.length;

    NSMutableArray<SGRPlayerMenuItem *> *choices = [NSMutableArray arrayWithCapacity:providers.count + 1];
    SGRPlayerMenuItem *automatic = [SGRPlayerMenuItem itemWithTitle:@"Automatic" image:nil action:^{
        NSString *currentTrack = SGKaraokePlayingTrack();
        if (!currentTrack.length) {
            SGLog(@"redesign player menu: cannot change lyrics source without a playing track");
            return;
        }
        SGKaraokeSetProviderForTrack(currentTrack, nil);
        SGRPlayerLyricsChanged();
        [weak.card setSubtitle:@"Automatic" forKey:@"spotifyglass.playerLyricsSource"];
    }];
    automatic.key = @"spotifyglass.playerLyricsSource.automatic";
    [choices addObject:automatic];

    for (SGLyricsProvider *provider in providers) {
        NSString *providerKey = provider.key;
        NSString *providerName = provider.name;
        SGRPlayerMenuItem *choice = [SGRPlayerMenuItem itemWithTitle:providerName image:nil action:^{
            NSString *currentTrack = SGKaraokePlayingTrack();
            if (!currentTrack.length) {
                SGLog(@"redesign player menu: cannot change lyrics source without a playing track");
                return;
            }
            SGKaraokeSetProviderForTrack(currentTrack, providerKey);
            SGRPlayerLyricsChanged();
            [weak.card setSubtitle:providerName forKey:@"spotifyglass.playerLyricsSource"];
        }];
        choice.key = [@"spotifyglass.playerLyricsSource." stringByAppendingString:providerKey];
        [choices addObject:choice];
    }
    item.children = choices;
    return item;
}

static NSArray<SGRPlayerMenuSection *> *sectionsFor(SGRPlayerMenuTakeover *t, NSArray<SGRPlayerMenuSpotifyRow *> *rows) {
    NSMutableArray<SGRPlayerMenuItem *> *tiles = [NSMutableArray array], *main = [NSMutableArray array],
                                  *feedback = [NSMutableArray array], *more = [NSMutableArray array],
                                  *destructive = [NSMutableArray array];
    for (SGRPlayerMenuSpotifyRow *row in rows) {
        const SGRPlayerMenuKnownRow *known = knownRow(row.identifier);
        SGRPlayerMenuItem *item = itemFor(t, row, known);
        switch (known ? known->place : SGRPlaceMore) {
            case SGRPlaceTile: [tiles addObject:item]; break;
            case SGRPlaceMain: [main addObject:item]; break;
            case SGRPlaceFeedback: [feedback addObject:item]; break;
            case SGRPlaceDestructive: [destructive addObject:item]; break;
            case SGRPlaceMore: [more addObject:item]; break;
        }
    }
    // Tiles in the Music app's order, Share last.
    [tiles sortUsingComparator:^NSComparisonResult(SGRPlayerMenuItem *a, SGRPlayerMenuItem *b) {
        return knownRow(a.key) < knownRow(b.key) ? NSOrderedAscending : NSOrderedDescending;
    }];
    // More than three tiles never happens with kKnown as it is; the rest would be rows.
    while (tiles.count > 3) {
        [main insertObject:tiles.lastObject atIndex:0];
        [tiles removeLastObject];
    }
    [main addObject:speedAndPitchItem()];
    [main addObject:lockScreenStyleItem(t)];
    [main addObject:backgroundStyleItem(t)];
    [main addObject:lyricsBlurItem(t)];
    [main addObject:lyricsSourceItem(t)];
    if (more.count == 1) {
        [feedback addObject:more.firstObject];
    } else if (more.count) {
        SGRPlayerMenuItem *item = [SGRPlayerMenuItem itemWithTitle:@"More" image:symbol(@"ellipsis.circle") action:nil];
        item.key = @"spotifyglass.more";
        item.children = more;
        [feedback addObject:item];
    }
    return @[[SGRPlayerMenuSection sectionWithItems:tiles tiles:YES], [SGRPlayerMenuSection sectionWithItems:main tiles:NO],
             [SGRPlayerMenuSection sectionWithItems:feedback tiles:NO], [SGRPlayerMenuSection sectionWithItems:destructive tiles:NO]];
}

#pragma mark firing a row

static void fire(SGRPlayerMenuTakeover *t, SGRPlayerMenuSpotifyRow *row) {
    UITableView *table = tableIn(t.menu.viewIfLoaded, 0);
    __block BOOL fired = NO;
    if (table) {
        withEveryCell(table, ^{
            UITableViewCell *cell = row.indexPath ? [table cellForRowAtIndexPath:row.indexPath] : nil;
            UIControl *control = cell ? listRowIn(cell) : nil;
            // The rows may have moved since they were read: the number is what the row is.
            if (![control.accessibilityIdentifier isEqualToString:row.identifier]) {
                control = nil;
                for (UITableViewCell *visible in table.visibleCells) {
                    UIControl *candidate = listRowIn(visible);
                    if ([candidate.accessibilityIdentifier isEqualToString:row.identifier]) control = candidate;
                }
            }
            if (!control) return;
            SGLog(@"redesign player menu: \"%@\" (%@) fired", row.title, row.identifier);
            SGRActivate(control);
            fired = YES;
        });
    }
    if (!fired) {
        SGLog(@"redesign player menu: \"%@\" (%@) is not in the sheet any more", row.title, row.identifier);
        reveal(t, @"a row could not be fired");
    }
}

#pragma mark the pass

static void pass(SGRPlayerMenuTakeover *t) {
    if (t.revealed || t.closing) return;
    UIViewController *menu = t.menu;
    if (!t.sheet) t.sheet = presentedSheet(menu);
    UIView *container = t.sheet.presentationController.containerView;
    if (!container) return;
    hideSheet(t, container);

    if (!t.card) {
        t.catcher = [UIControl new];
        t.catcher.backgroundColor = [UIColor colorWithWhite:0 alpha:kDimming];
        t.catcher.alpha = 0;
        t.catcher.isAccessibilityElement = NO;
        [t.catcher addTarget:t action:@selector(catcherTapped) forControlEvents:UIControlEventTouchDown];
        t.card = [[SGRPlayerMenuCard alloc] initWithFrame:CGRectZero];
        __weak SGRPlayerMenuTakeover *weak = t;
        t.card.sizeChanged = ^(SGRPlayerMenuCard *card) {
            SGRPlayerMenuTakeover *strong = weak;
            UIView *host = card.superview;
            if (strong && host) placeCard(strong, host);
        };
        t.card.onEscape = ^{ [weak catcherTapped]; };
        NSArray<SGRPlayerMenuSpotifyRow *> *last = lastRows();
        if (last.count) {
            t.provisional = YES;
            t.signature = signatureOf(last);
            [t.card showSections:sectionsFor(t, last)];
        } else {
            [t.card showLoading];
        }
    }
    if (t.catcher.superview != container) [container addSubview:t.catcher];
    if (t.card.superview != container) [container addSubview:t.card];
    if (container.subviews.lastObject != t.card) {
        [container bringSubviewToFront:t.catcher];
        [container bringSubviewToFront:t.card];
    }

    UITableView *table = tableIn(menu.viewIfLoaded, 0);
    BOOL complete = NO;
    NSArray<SGRPlayerMenuSpotifyRow *> *rows = table ? readRows(table, &complete) : @[];
    BOOL changed = NO;
    if (rows.count) {
        BOOL first = !t.hasRows;
        t.hasRows = YES;
        t.provisional = NO;
        NSMutableDictionary<NSString *, SGRPlayerMenuSpotifyRow *> *byIdentifier = [NSMutableDictionary dictionary];
        for (SGRPlayerMenuSpotifyRow *row in rows) byIdentifier[row.identifier] = row;
        t.rowsByIdentifier = byIdentifier;
        NSString *signature = signatureOf(rows);
        t.complete = complete;
        if (first) {
            SGLog(@"redesign player menu: Spotify's rows in %.2f s after the tap, %@%@", CACurrentMediaTime() - t.tappedAt,
                  [signature isEqualToString:t.signature] ? @"the last menu's" : t.signature ? @"not the last menu's" : @"none shown before",
                  complete ? @"" : @" (not all of them read yet)");
        }
        if (complete) {
            [t.poll invalidate];
            keepRows(rows, signature);
        }
        SGRPlayerMenuSpotifyRow *pending = t.pendingIdentifier ? byIdentifier[t.pendingIdentifier] : nil;
        if (pending || complete) t.pendingIdentifier = nil;
        if (pending) {
            fire(t, pending);
            if (t.closing || t.revealed) return;
        }
        changed = ![signature isEqualToString:t.signature];
        if (changed) {
            t.signature = signature;
            logNumbers(rows);
            [t.card showSections:sectionsFor(t, rows)];
        }
    }

    if (!t.grown) {
        t.grown = YES;
        placeCard(t, container);
        [t.card layoutIfNeeded];
        [UIView animateWithDuration:0.2 animations:^{ t.catcher.alpha = 1; }];
        [t.card growFrom:anchorInCard(t)];
    } else if (changed) {
        [t.card layoutIfNeeded];
        SGRAnimate(SGRMotionLayout, ^{
            placeCard(t, container);
            [t.card layoutIfNeeded];
        }, nil);
    } else {
        placeCard(t, container);
    }
}

static BOOL moreTappedRecently(void) {
    return sgr_moreTappedAt && CACurrentMediaTime() - sgr_moreTappedAt < kMenuAfterTap;
}

// Whether `controller` or one of its children is Spotify's context menu.
static BOOL holdsContextMenu(UIViewController *controller, int depth) {
    if ([NSStringFromClass(controller.class) containsString:@"ContextMenu"]) return YES;
    if (depth > 5) return NO;
    for (UIViewController *child in controller.childViewControllers) {
        if (holdsContextMenu(child, depth + 1)) return YES;
    }
    return NO;
}

static SGRPlayerMenuTakeover *takeoverFor(UIViewController *menu) {
    id existing = objc_getAssociatedObject(menu, &kTakeoverKey);
    if (existing) return existing == NSNull.null ? nil : existing;
    BOOL claimed = [objc_getAssociatedObject(presentedSheet(menu), &kClaimKey) boolValue];
    if (!moreTappedRecently() && !claimed) {
        objc_setAssociatedObject(menu, &kTakeoverKey, NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    SGRPlayerMenuTakeover *t = [SGRPlayerMenuTakeover new];
    t.tappedAt = sgr_moreTappedAt ?: CACurrentMediaTime();
    sgr_moreTappedAt = 0;
    t.menu = menu;
    t.button = sgr_moreButton;
    UIViewController *sheet = presentedSheet(menu);
    if (sheet) objc_setAssociatedObject(sheet, &kTakenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(menu, &kTakeoverKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak SGRPlayerMenuTakeover *weak = t;
    t.speedObserver = [NSNotificationCenter.defaultCenter addObserverForName:SGSpeedPitchChangedNotification object:nil
                                                                      queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weak.card setSubtitle:note.userInfo[@"summary"] forKey:@"spotifyglass.speedPitch"];
        // Pitch following speed folds its slider away, and the panel with it.
        [weak.card setExpansionHeight:SGSpeedPitchPanelHeight() forKey:@"spotifyglass.speedPitch"];
    }];
    t.poll = [NSTimer timerWithTimeInterval:kRowsPoll repeats:YES block:^(NSTimer *timer) {
        SGRPlayerMenuTakeover *strong = weak;
        if (!strong || strong.complete || strong.closing || strong.revealed) {
            [timer invalidate];
            return;
        }
        UITableView *table = tableIn(strong.menu.viewIfLoaded, 0);
        if (table && rowCount(table) > 0) pass(strong);
    }];
    [NSRunLoop.mainRunLoop addTimer:t.poll forMode:NSRunLoopCommonModes];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRowsWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRPlayerMenuTakeover *strong = weak;
        if (!strong || strong.hasRows || strong.closing || strong.revealed) return;
        UITableView *table = tableIn(strong.menu.viewIfLoaded, 0);
        if (table && rowCount(table) > 0) {
            reveal(strong, [NSString stringWithFormat:@"the table has %ld rows and none could be read", (long)rowCount(table)]);
            return;
        }
        SGLog(@"redesign player menu: no rows of Spotify's %.0f s after the tap, still waiting with %@", kRowsWait,
              strong.provisional ? @"the last menu's rows" : @"a spinner");
    });
    SGLog(@"redesign player menu: the ⋯'s sheet taken over");
    return t;
}

#pragma mark - what darkens the screen as the menu opens

static NSString *darkness(UIColor *color) {
    CGFloat white = 1, alpha = 0;
    if (!color || ![color getWhite:&white alpha:&alpha]) {
        CGFloat r, g, b;
        if (![color getRed:&r green:&g blue:&b alpha:&alpha]) return nil;
        white = (r + g + b) / 3;
    }
    return alpha >= 0.3 && white < 0.15 ? [NSString stringWithFormat:@"%.2f@%.2f", white, alpha] : nil;
}

static void findDark(UIView *view, UIView *window, CGFloat alpha, int depth, NSMutableArray<NSString *> *out) {
    if (view.hidden || view.alpha < 0.01 || depth > 40 || out.count > 20) return;
    alpha *= view.alpha;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGRect screen = CGRectIntersection(frame, window.bounds);
    BOOL covers = !CGRectIsNull(screen) && screen.size.width * screen.size.height > 0.6 * window.bounds.size.width * window.bounds.size.height;
    if (!covers) return;
    NSString *dark = darkness(view.backgroundColor) ?: (view.layer.backgroundColor ? darkness([UIColor colorWithCGColor:view.layer.backgroundColor]) : nil);
    if (dark && alpha > 0.05) {
        [out addObject:[NSString stringWithFormat:@"%@%@ bg %@ alpha %.2f", NSStringFromClass(view.class),
                        view.accessibilityIdentifier.length ? [@" id=" stringByAppendingString:view.accessibilityIdentifier] : @"", dark, alpha]];
    }
    for (UIView *child in view.subviews) findDark(child, window, alpha, depth + 1, out);
}

static void logDarkness(UIView *anyView) {
    static int menus;
    if (menus++ >= 2) return;
    for (NSNumber *after in @[@0, @0.02, @0.05, @0.1, @0.2, @0.4]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(after.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindowScene *scene = anyView.window.windowScene;
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            for (UIWindow *window in scene.windows) {
                if (window.hidden) continue;
                NSMutableArray<NSString *> *dark = [NSMutableArray array];
                findDark(window, window, 1, 0, dark);
                [lines addObject:[NSString stringWithFormat:@"%@ level %.0f: %@", NSStringFromClass(window.class), window.windowLevel,
                                  dark.count ? [dark componentsJoinedByString:@"; "] : @"nothing dark over it"]];
            }
            SGLog(@"redesign player menu: %.2f s after the sheet began: %@", after.doubleValue, [lines componentsJoinedByString:@" | "]);
        });
    }
}

%hook _TtC22NavigationUI_SheetImpl27SheetPresentationController

- (void)presentationTransitionWillBegin {
    %orig;
    UIPresentationController *presentation = (UIPresentationController *)self;
    UIViewController *sheet = presentation.presentedViewController;
    if (!moreTappedRecently() || !holdsContextMenu(sheet, 0)) return;
    objc_setAssociatedObject(sheet, &kClaimKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    hidePresentation(presentation.presentedView, presentation.containerView);
    logDarkness(presentation.containerView ?: presentation.presentingViewController.view);
    // A claimed sheet whose menu is never taken over would stay out of sight with nothing in its place.
    __weak UIPresentationController *weak = presentation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kClaimWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIPresentationController *strong = weak;
        UIViewController *presented = strong.presentedViewController;
        if (!presented || objc_getAssociatedObject(presented, &kTakenKey) || ![objc_getAssociatedObject(presented, &kClaimKey) boolValue]) return;
        SGLog(@"redesign player menu: no menu taken over in the ⋯'s sheet within %.0f s, the sheet shown", kClaimWait);
        objc_setAssociatedObject(presented, &kClaimKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        showPresentation(strong.presentedView, strong.containerView);
    });
}

- (void)containerViewDidLayoutSubviews {
    %orig;
    UIPresentationController *presentation = (UIPresentationController *)self;
    if ([objc_getAssociatedObject(presentation.presentedViewController, &kClaimKey) boolValue]) {
        hidePresentation(presentation.presentedView, presentation.containerView);
    }
}

%end

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRPlayerMenuTakeover *t = takeoverFor((UIViewController *)self);
    if (t) pass(t);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SGRPlayerMenuTakeover *t = takeoverFor((UIViewController *)self);
    if (t) pass(t);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SGRPlayerMenuTakeover *t = objc_getAssociatedObject(self, &kTakeoverKey);
    if ([t isKindOfClass:SGRPlayerMenuTakeover.class]) pass(t);
}

// The sheet going away takes the card with it; a page of Spotify's pushed over the menu shows the sheet.
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    SGRPlayerMenuTakeover *t = objc_getAssociatedObject(self, &kTakeoverKey);
    if (![t isKindOfClass:SGRPlayerMenuTakeover.class]) return;
    UINavigationController *navigation = ((UIViewController *)self).navigationController;
    UIViewController *sheet = t.sheet;
    BOOL leaving = !sheet.presentingViewController || sheet.isBeingDismissed || sheet.presentingViewController.isBeingDismissed;
    if (!leaving && navigation.viewControllers.count > 1) reveal(t, @"Spotify opened a page of its own on it");
    else closeCard(t);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    sgr_menuOn = YES;
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController", @"_TtC22NavigationUI_SheetImpl27SheetPresentationController"]);
}
