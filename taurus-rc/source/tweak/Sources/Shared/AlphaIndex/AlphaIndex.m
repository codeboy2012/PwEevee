// The alphabet index: a Liquid Glass capsule against the trailing edge of a long playlist with A to Z and # in it.
// A finger on it lights the letter under it with a glass lens that glides from letter to letter, raises a glass
// bubble with the letter written large beside it, and scrolls the list to the first row under that letter. Letters
// no row starts with are dimmed and skipped. The capsule rests at half strength once the list stops moving.
//
// Spotify's lists are UICollectionViews that make their cells as they scroll into view, so the titles of rows
// far down are not there to read. The map is therefore built by walking the list once: the offset is moved a
// screen at a time, the list laid out, and the titles of the cells it made noted, then the offset put back;
// all within one pass of the main run loop, so none of it is ever drawn. Whatever the list is ordered by, a
// letter goes to the first row (in the list's order) under it, which for a list sorted by title is the Music
// app's behaviour and for any other order still lands somewhere useful.
//
// The map is rebuilt when the touch begins if the list's size changed or a cell was seen showing another
// letter than the map says (the list was re-sorted).
#import "Core/SGCore.h"
#import "AlphaIndex.h"

static const CGFloat kBarWidth = 22, kBarSide = 3, kPad = 8, kLetterStep = 14, kMinRows = 6, kLongList = 1.5;
static const CGFloat kBubble = 62;
static const NSTimeInterval kIdle = 1.8;
static const NSTimeInterval kRecheck = 0.6;
static const NSUInteger kMostSteps = 400;

static char kBarKey, kCheckedKey, kPendingKey;

#pragma mark - letters and titles

NSString *SGAlphaIndexLetter(NSString *title) {
    NSString *folded = [title stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch | NSWidthInsensitiveSearch locale:nil];
    for (NSUInteger i = 0; i < folded.length; i++) {
        unichar c = [folded characterAtIndex:i];
        if (c >= 'a' && c <= 'z') return [NSString stringWithFormat:@"%c", c - 'a' + 'A'];
        if (c >= 'A' && c <= 'Z') return [NSString stringWithFormat:@"%c", c];
        // The first letter or digit decides; quotes, brackets and ¿ before it do not.
        if ([NSCharacterSet.alphanumericCharacterSet characterIsMember:c]) return @"#";
    }
    return @"#";
}

static NSArray<NSString *> *allLetters(void) {
    static NSArray *letters;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        for (char c = 'A'; c <= 'Z'; c++) [list addObject:[NSString stringWithFormat:@"%c", c]];
        [list addObject:@"#"];
        letters = list;
    });
    return letters;
}

static UICollectionViewCell *cellOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionViewCell.class]) return (UICollectionViewCell *)v;
    }
    return nil;
}

static UICollectionView *listOf(UICollectionViewCell *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return (UICollectionView *)v;
    }
    return nil;
}

// The title of a row: the top label of a cell shaped like a row (a thumbnail and two lines of text), else nil.
static NSString *titleOf(UICollectionViewCell *cell) {
    CGSize size = cell.bounds.size;
    if (size.width < 280 || size.height < 44 || size.height > 120) return nil;
    __block UILabel *top = nil;
    __block CGFloat topY = CGFLOAT_MAX;
    __block NSInteger labels = 0;
    SGForEachView(cell.contentView, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || v.hidden || v.alpha < 0.01) return;
        UILabel *label = (UILabel *)v;
        NSString *text = [label.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) return;
        labels++;
        CGFloat y = SGFrameIn(label, cell).origin.y;
        if (y < topY - 0.5 || (fabs(y - topY) <= 0.5 && label.font.pointSize > top.font.pointSize)) {
            top = label;
            topY = y;
        }
    });
    if (!top || labels < 2) return nil;
    return [top.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

#pragma mark - the map

static UIVisualEffect *glassEffect(UIColor *tint, BOOL interactive) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if ([glass respondsToSelector:@selector(effectWithStyle:)]) {
        id effect = [glass effectWithStyle:0];
        if (tint && [effect respondsToSelector:NSSelectorFromString(@"setTintColor:")]) [effect setValue:tint forKey:@"tintColor"];
        if (interactive && [effect respondsToSelector:NSSelectorFromString(@"setInteractive:")]) [effect setValue:@YES forKey:@"interactive"];
        return effect;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
}

static UIVisualEffectView *glassView(UIColor *tint) {
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:glassEffect(tint, NO)];
    view.userInteractionEnabled = NO;
    view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    return view;
}

@interface SGAlphaIndexBar : UIView
- (instancetype)initWithList:(UICollectionView *)list;
@property (nonatomic, weak) UICollectionView *list;
- (void)refresh;
- (void)noteCell:(UICollectionViewCell *)cell;
@end

@implementation SGAlphaIndexBar {
    NSMutableDictionary<NSIndexPath *, NSString *> *_letters;
    NSArray<UILabel *> *_labels;
    NSMutableArray<NSNumber *> *_has;
    UIVisualEffectView *_capsule, *_lens, *_bubble;
    UILabel *_bubbleLabel;
    NSInteger _active;
    NSUInteger _dimToken;
    BOOL _dirty, _scanned, _scanning, _dimmed;
    CGSize _scannedSize;
    UISelectionFeedbackGenerator *_feedback;
}

- (instancetype)initWithList:(UICollectionView *)list {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _list = list;
    _letters = [NSMutableDictionary dictionary];
    _active = -1;
    _dimmed = YES;
    self.alpha = 0;
    self.backgroundColor = UIColor.clearColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.isAccessibilityElement = NO;

    _capsule = glassView(nil);
    [self addSubview:_capsule];

    _lens = glassView([SGAlphaIndexColor() colorWithAlphaComponent:0.78]);
    _lens.alpha = 0;
    [self addSubview:_lens];

    _has = [NSMutableArray array];
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (NSString *letter in allLetters()) {
        UILabel *label = [UILabel new];
        label.text = letter;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = SGAlphaIndexColor();
        label.isAccessibilityElement = NO;
        [self addSubview:label];
        [labels addObject:label];
        [_has addObject:@YES];
    }
    _labels = labels;

    _bubble = glassView(nil);
    _bubble.alpha = 0;
    _bubbleLabel = [UILabel new];
    _bubbleLabel.textAlignment = NSTextAlignmentCenter;
    _bubbleLabel.textColor = UIColor.whiteColor;
    _bubbleLabel.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [_bubble.contentView addSubview:_bubbleLabel];
    [self addSubview:_bubble];
    return self;
}

- (CGFloat)step {
    return MAX(1, (self.bounds.size.height - 2 * kPad) / _labels.count);
}

- (CGFloat)centerYOf:(NSInteger)index {
    return kPad + ([self step] * (index + 0.5));
}

- (void)placeLens:(NSInteger)index {
    _lens.center = CGPointMake(self.bounds.size.width / 2, [self centerYOf:index]);
    _bubble.center = CGPointMake(-(kBubble / 2) - 12, [self centerYOf:index]);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat step = [self step];
    CGFloat font = MAX(8, MIN(11, floor(step * 0.8)));
    _capsule.frame = self.bounds;
    SGShapeGlass(_capsule, self.bounds.size.width / 2, YES);
    for (NSUInteger i = 0; i < _labels.count; i++) {
        UILabel *label = _labels[i];
        label.font = [UIFont systemFontOfSize:font weight:UIFontWeightBold];
        label.frame = CGRectMake(0, kPad + i * step, self.bounds.size.width, step);
    }
    _lens.bounds = CGRectMake(0, 0, self.bounds.size.width + 6, step + 6);
    SGShapeGlass(_lens, 0, YES);
    _bubble.bounds = CGRectMake(0, 0, kBubble, kBubble);
    SGShapeGlass(_bubble, kBubble / 2, YES);
    _bubbleLabel.frame = _bubble.contentView.bounds;
    if (_active >= 0) [self placeLens:_active];
}

// Takes touches only on the strip itself, a little wider than it is drawn so a thumb finds it.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) return nil;
    return CGRectContainsPoint(CGRectInset(self.bounds, -10, 0), point) ? self : nil;
}

- (void)refresh {
    UICollectionView *list = self.list;
    UIView *host = list.superview;
    if (!list || !host || !list.window) {
        self.hidden = YES;
        return;
    }
    UIEdgeInsets inset = list.adjustedContentInset;
    BOOL vertical = list.contentSize.width <= list.bounds.size.width + 1;
    BOOL long_ = list.contentSize.height >= list.bounds.size.height * kLongList;
    BOOL show = vertical && long_ && list.bounds.size.height > 240 && !list.hidden && list.alpha > 0.01;
    CGFloat top = list.frame.origin.y + inset.top + 8;
    CGFloat bottom = CGRectGetMaxY(list.frame) - MAX(inset.bottom, list.safeAreaInsets.bottom) - 8;
    CGFloat free = MAX(0, bottom - top), height = MIN(kLetterStep * allLetters().count + 2 * kPad, free);
    if (height < 220) show = NO;
    CGRect frame = CGRectMake(CGRectGetMaxX(list.frame) - kBarWidth - kBarSide, round(top + (free - height) / 2), kBarWidth, round(height));
    if (self.hidden == show) self.hidden = !show;
    if (self.superview != host) [host addSubview:self];
    else if (host.subviews.lastObject != self) [host bringSubviewToFront:self];
    if (!CGRectEqualToRect(self.frame, frame)) self.frame = frame;
    if (show && !_scanning) [self wake];
}

#pragma mark resting and waking

- (void)wake {
    if (_active >= 0) return;
    if (_dimmed) {
        _dimmed = NO;
        [UIView animateWithDuration:0.28 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            self.alpha = 1;
        } completion:nil];
    }
    [self scheduleDim];
}

- (void)scheduleDim {
    NSUInteger token = ++_dimToken;
    __weak SGAlphaIndexBar *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kIdle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGAlphaIndexBar *bar = weak;
        if (!bar || bar->_dimToken != token || bar->_active >= 0 || bar->_dimmed) return;
        bar->_dimmed = YES;
        [UIView animateWithDuration:0.6 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            bar.alpha = 0.5;
        } completion:nil];
    });
}

#pragma mark the map

- (void)noteCell:(UICollectionViewCell *)cell {
    if (_scanning) return;
    UICollectionView *list = self.list;
    NSIndexPath *path = [list indexPathForCell:cell];
    NSString *title = titleOf(cell);
    if (!path || !title) return;
    NSString *letter = SGAlphaIndexLetter(title), *known = _letters[path];
    if (known && ![known isEqualToString:letter]) _dirty = YES;
    _letters[path] = letter;
}

- (NSUInteger)itemCount {
    UICollectionView *list = self.list;
    NSUInteger total = 0;
    for (NSInteger section = 0; section < list.numberOfSections; section++) total += [list numberOfItemsInSection:section];
    return total;
}

// Walks the list a screen at a time, noting the letter under each cell that comes up, and puts the offset back.
- (void)scan {
    UICollectionView *list = self.list;
    if (!list) return;
    _scanning = YES;
    CGPoint original = list.contentOffset;
    UIEdgeInsets inset = list.adjustedContentInset;
    CGFloat viewport = list.bounds.size.height - inset.top - inset.bottom;
    NSMutableDictionary<NSIndexPath *, NSString *> *found = [NSMutableDictionary dictionary];
    if (viewport > 100) {
        CGFloat y = -inset.top;
        for (NSUInteger step = 0; step < kMostSteps; step++) {
            CGFloat last = MAX(-inset.top, list.contentSize.height + inset.bottom - list.bounds.size.height);
            CGFloat target = MIN(y, last);
            [list setContentOffset:CGPointMake(original.x, target) animated:NO];
            [list layoutIfNeeded];
            for (UICollectionViewCell *cell in list.visibleCells) {
                NSIndexPath *path = [list indexPathForCell:cell];
                NSString *title = titleOf(cell);
                if (path && title) found[path] = SGAlphaIndexLetter(title);
            }
            if (target >= last - 0.5) break;
            y = target + viewport * 0.85;
        }
        [list setContentOffset:original animated:NO];
        [list layoutIfNeeded];
    }
    _scanning = NO;
    if (found.count) _letters = found;
    _scanned = YES;
    _dirty = NO;
    _scannedSize = list.contentSize;
    [self showAvailability];
    SGLog(@"alpha index: %lu rows read of %lu", (unsigned long)found.count, (unsigned long)[self itemCount]);
}

// Letters with no row under them are dimmed, so the eye goes where the list does.
- (void)showAvailability {
    NSSet<NSString *> *present = [NSSet setWithArray:_letters.allValues];
    NSArray<NSString *> *letters = allLetters();
    for (NSUInteger i = 0; i < letters.count; i++) {
        _has[i] = @(!_letters.count || [present containsObject:letters[i]]);
    }
    for (NSUInteger i = 0; i < _labels.count; i++) [self paintLabel:i];
}

- (void)paintLabel:(NSUInteger)i {
    UILabel *label = _labels[i];
    BOOL on = (NSInteger)i == _active, has = [_has[i] boolValue];
    label.textColor = on ? UIColor.whiteColor : SGAlphaIndexColor();
    label.alpha = on || has ? 1 : 0.32;
}

// The first row, in the list's order, filed under `letter`; nil when there is none.
- (NSIndexPath *)firstRowUnder:(NSString *)letter {
    NSIndexPath *first = nil;
    for (NSIndexPath *path in _letters) {
        if (![_letters[path] isEqualToString:letter]) continue;
        if (!first || [path compare:first] == NSOrderedAscending) first = path;
    }
    return first;
}

// Brings the first row under the letter at `index` to the top, or under the next letter that has rows. Past
// the last letter that has any, the list stays at the last one. The finger's own letter stays lit either way.
- (void)jumpTo:(NSInteger)index {
    UICollectionView *list = self.list;
    NSArray<NSString *> *letters = allLetters();
    NSIndexPath *target = nil;
    NSInteger landed = index;
    for (NSInteger i = index; i < (NSInteger)letters.count && !target; i++) {
        target = [self firstRowUnder:letters[i]];
        if (target) landed = i;
    }
    for (NSInteger i = index - 1; i >= 0 && !target; i--) {
        target = [self firstRowUnder:letters[i]];
        if (target) landed = i;
    }
    [self highlight:index landed:landed];
    UICollectionViewLayoutAttributes *attributes = target ? [list layoutAttributesForItemAtIndexPath:target] : nil;
    if (!attributes) return;
    UIEdgeInsets inset = list.adjustedContentInset;
    CGFloat last = MAX(-inset.top, list.contentSize.height + inset.bottom - list.bounds.size.height);
    CGFloat offset = MAX(-inset.top, MIN(last, attributes.frame.origin.y - inset.top));
    if (fabs(list.contentOffset.y - offset) > 0.5) [list setContentOffset:CGPointMake(list.contentOffset.x, offset) animated:NO];
}

#pragma mark the finger

// Lights the letter under the finger: the lens glides to it, the bubble beside it shows the letter the list
// went to. -1 puts the lens and bubble away.
- (void)highlight:(NSInteger)index landed:(NSInteger)landed {
    if (_active == index) return;
    BOOL appearing = _active < 0 && index >= 0;
    NSInteger previous = _active;
    _active = index;
    for (NSUInteger i = 0; i < _labels.count; i++) {
        if ((NSInteger)i == index || (NSInteger)i == previous) [self paintLabel:i];
    }
    if (index < 0) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self->_lens.alpha = 0;
            self->_lens.transform = CGAffineTransformMakeScale(0.6, 0.6);
            self->_bubble.alpha = 0;
            self->_bubble.transform = CGAffineTransformMakeScale(0.4, 0.4);
        } completion:nil];
        [self scheduleDim];
        return;
    }
    _bubbleLabel.text = allLetters()[MAX(0, MIN(landed, (NSInteger)_labels.count - 1))];
    [_feedback selectionChanged];
    if (appearing) {
        [self placeLens:index];
        _lens.transform = CGAffineTransformMakeScale(0.6, 0.6);
        _bubble.transform = CGAffineTransformMakeScale(0.4, 0.4);
        [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            self->_lens.alpha = 1;
            self->_lens.transform = CGAffineTransformIdentity;
            self->_bubble.alpha = 1;
            self->_bubble.transform = CGAffineTransformIdentity;
        } completion:nil];
        return;
    }
    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.3 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        [self placeLens:index];
    } completion:nil];
}

- (NSInteger)indexAt:(CGPoint)point {
    return MAX(0, MIN((NSInteger)_labels.count - 1, (NSInteger)floor((point.y - kPad) / [self step])));
}

- (void)begin {
    UICollectionView *list = self.list;
    if (!list) return;
    BOOL stale = !_scanned || _dirty || !CGSizeEqualToSize(_scannedSize, list.contentSize);
    if (stale) [self scan];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _dimToken++;
    _dimmed = NO;
    self.alpha = 1;
    _feedback = [UISelectionFeedbackGenerator new];
    [_feedback prepare];
    [self begin];
    [self jumpTo:[self indexAt:[touches.anyObject locationInView:self]]];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self jumpTo:[self indexAt:[touches.anyObject locationInView:self]]];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _feedback = nil;
    [self highlight:-1 landed:-1];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

@end

#pragma mark - noticing lists

// Whether a list belongs to the playlist page: its view controller is the free tier playlist's.
static BOOL inPlaylistPage(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        if ([NSStringFromClass(r.class) containsString:@"FreeTierPlaylist"]) return YES;
    }
    return NO;
}

// Whether the cells showing now are rows: enough of them, each with a title. The playlist page's own list opens
// on a tall header that leaves room for only a few rows, so one row is enough there.
static BOOL looksLikeTitledRows(UICollectionView *list) {
    NSUInteger rows = 0;
    for (UICollectionViewCell *cell in list.visibleCells) {
        if (titleOf(cell)) rows++;
    }
    return rows >= (inPlaylistPage(list) ? 1 : kMinRows);
}

// Puts the bar on the list when it is a long list of titled rows. The list is often still filling when its
// first rows lay out, so a list that is not there yet is looked at again a few times rather than once.
static BOOL attach(UICollectionView *list) {
    if (!list.window) return NO;
    if (objc_getAssociatedObject(list, &kBarKey)) return YES;
    if (list.contentSize.height < list.bounds.size.height * kLongList || !looksLikeTitledRows(list)) return NO;
    SGAlphaIndexBar *bar = [[SGAlphaIndexBar alloc] initWithList:list];
    objc_setAssociatedObject(list, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UICollectionViewCell *cell in list.visibleCells) [bar noteCell:cell];
    [bar refresh];
    SGLog(@"alpha index: bar added to a list of %@ at %@", NSStringFromCGSize(list.contentSize), NSStringFromCGRect(list.frame));
    return YES;
}

static void recheck(UICollectionView *list, NSInteger attempt) {
    __weak UICollectionView *weak = list;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UICollectionView *strong = weak;
        if (!strong) return;
        if (attach(strong) || attempt >= 5) {
            objc_setAssociatedObject(strong, &kPendingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        recheck(strong, attempt + 1);
    });
}

void SGAlphaIndexNoteRow(UIView *row) {
    if (!SGEnabled(SGKeyAlphaIndex)) return;
    UICollectionViewCell *cell = cellOf(row);
    UICollectionView *list = cell ? listOf(cell) : nil;
    if (!list) return;
    SGAlphaIndexBar *bar = objc_getAssociatedObject(list, &kBarKey);
    if (bar) {
        [bar noteCell:cell];
        [bar refresh];
        return;
    }
    // A list not yet known to be rows is looked at again a moment later, not on every cell's pass.
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - [objc_getAssociatedObject(list, &kCheckedKey) doubleValue] < kRecheck) return;
    objc_setAssociatedObject(list, &kCheckedKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (attach(list)) return;
    if (objc_getAssociatedObject(list, &kPendingKey)) return;
    objc_setAssociatedObject(list, &kPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    recheck(list, 0);
}

SGModRow *SGAlphaIndexRow(void) {
    return SGSwitchRow(@"Alphabet index",
                       @"A to Z on a Liquid Glass strip along the edge of long playlists and mixes, with a lens and a letter bubble as you scrub",
                       SGKeyAlphaIndex);
}
