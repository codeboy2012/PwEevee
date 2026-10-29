#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "SGRPlayerMenu.h"

const CGFloat SGRPlayerMenuWidth = 272;

static const CGFloat kCorner = 26;
static const CGFloat kLead = 18, kGlyphBox = 22, kTextX = 54, kTrail = 18, kChevronBox = 20;
static const CGFloat kRowPadding = 9, kRowMin = 40, kSectionPadding = 6;
static const CGFloat kTileTop = 14, kTileGlyph = 24, kTileGap = 6, kTileBottom = 12, kTileSide = 6;
static const CGFloat kSeparatorInset = 20;
static const CGFloat kLoadingHeight = 72;

static UIColor *rowColor(SGRPlayerMenuItem *item) {
    return item.destructive ? UIColor.systemRedColor : SGRPrimary();
}

static UIFont *titleFont(void) {
    return SGRFont(UIFontTextStyleBody, UIFontWeightRegular, UIContentSizeCategoryExtraExtraLarge);
}

static UIFont *subtitleFont(void) {
    return SGRFont(UIFontTextStyleSubheadline, UIFontWeightRegular, UIContentSizeCategoryExtraExtraLarge);
}

static UIFont *tileFont(void) {
    return SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryExtraLarge);
}

static CGFloat hairline(UIView *view) {
    return 1 / MAX(view.traitCollection.displayScale, 1);
}

// A symbol keeps the size it was made at; a picture of Spotify's is fitted to the box.
static void placeGlyph(UIImageView *glyph, CGRect box) {
    glyph.contentMode = glyph.image.isSymbolImage ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit;
    glyph.frame = glyph.image.isSymbolImage ? box : CGRectInset(box, 1, 1);
}

@interface SGRPlayerMenuItem ()
// Opens in place rather than doing something.
@property (nonatomic, readonly) BOOL opens;
@end

@implementation SGRPlayerMenuItem
+ (instancetype)itemWithTitle:(NSString *)title image:(UIImage *)image action:(void (^)(void))action {
    SGRPlayerMenuItem *item = [self new];
    item.title = title;
    item.image = image;
    item.action = action;
    return item;
}

- (BOOL)opens {
    return self.children.count || self.makeExpansion;
}
@end

@implementation SGRPlayerMenuSection
+ (instancetype)sectionWithItems:(NSArray<SGRPlayerMenuItem *> *)items tiles:(BOOL)tiles {
    SGRPlayerMenuSection *section = [self new];
    section.items = items;
    section.tiles = tiles;
    return section;
}
@end

#pragma mark - a row

@interface SGRPlayerMenuRow : UIControl
@property (nonatomic, readonly) SGRPlayerMenuItem *item;
@property (nonatomic) BOOL expanded;
- (instancetype)initWithItem:(SGRPlayerMenuItem *)item;
- (CGFloat)heightForWidth:(CGFloat)width;
- (void)showSubtitle:(NSString *)subtitle;
@end

@implementation SGRPlayerMenuRow {
    UIView *_highlight;
    UIImageView *_glyph, *_chevron;
    UILabel *_title, *_subtitle;
}

- (instancetype)initWithItem:(SGRPlayerMenuItem *)item {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _item = item;
    UIColor *color = rowColor(item);

    _highlight = [UIView new];
    _highlight.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _highlight.alpha = 0;
    _highlight.userInteractionEnabled = NO;
    [self addSubview:_highlight];

    _glyph = [[UIImageView alloc] initWithImage:[item.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _glyph.tintColor = color;
    _title = [UILabel new];
    _title.font = titleFont();
    _title.textColor = color;
    _title.numberOfLines = 2;
    _title.text = item.title;
    _subtitle = [UILabel new];
    _subtitle.font = subtitleFont();
    _subtitle.textColor = item.destructive ? [color colorWithAlphaComponent:0.7] : SGRSecondary();
    _subtitle.text = item.subtitle;
    for (UIView *view in @[_glyph, _title, _subtitle]) {
        view.userInteractionEnabled = NO;
        [self addSubview:view];
    }
    if (item.opens) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.down" withConfiguration:config]];
        _chevron.tintColor = SGRSecondary();
        _chevron.contentMode = UIViewContentModeCenter;
        _chevron.userInteractionEnabled = NO;
        [self addSubview:_chevron];
    }

    self.enabled = !item.disabled;
    self.alpha = item.disabled ? 0.4 : 1;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton | (item.disabled ? UIAccessibilityTraitNotEnabled : 0);
    [self describe];
    return self;
}

- (void)describe {
    self.accessibilityLabel = self.item.title;
    NSMutableArray<NSString *> *value = [NSMutableArray array];
    if (_subtitle.text.length) [value addObject:_subtitle.text];
    if (self.item.opens) [value addObject:self.expanded ? @"Expanded" : @"Collapsed"];
    self.accessibilityValue = value.count ? [value componentsJoinedByString:@", "] : nil;
}

- (void)setExpanded:(BOOL)expanded {
    _expanded = expanded;
    _chevron.transform = expanded ? CGAffineTransformMakeRotation(M_PI - 0.0001) : CGAffineTransformIdentity;
    [self describe];
}

- (void)showSubtitle:(NSString *)subtitle {
    if ([_subtitle.text isEqualToString:subtitle] || (!_subtitle.text.length && !subtitle.length)) return;
    _subtitle.text = subtitle;
    [self describe];
    [self setNeedsLayout];
}

- (CGFloat)textWidth:(CGFloat)width {
    return MAX(0, width - kTextX - kTrail - (_chevron ? kChevronBox + 4 : 0));
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat text = [self textWidth:width];
    CGFloat height = ceil([_title sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
    if (_subtitle.text.length) height += 1 + ceil([_subtitle sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
    return MAX(kRowMin, height + 2 * kRowPadding);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _highlight.frame = bounds;
    placeGlyph(_glyph, CGRectMake(kLead, round((bounds.size.height - kGlyphBox) / 2), kGlyphBox, kGlyphBox));
    CGFloat text = [self textWidth:bounds.size.width];
    CGFloat titleHeight = ceil([_title sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height);
    CGFloat subtitleHeight = _subtitle.text.length ? ceil([_subtitle sizeThatFits:CGSizeMake(text, CGFLOAT_MAX)].height) : 0;
    CGFloat y = round((bounds.size.height - titleHeight - (subtitleHeight ? subtitleHeight + 1 : 0)) / 2);
    _title.frame = CGRectMake(kTextX, y, text, titleHeight);
    _subtitle.frame = CGRectMake(kTextX, y + titleHeight + 1, text, subtitleHeight);
    _subtitle.hidden = subtitleHeight == 0;
    _chevron.frame = CGRectMake(bounds.size.width - kTrail - kChevronBox, round((bounds.size.height - kChevronBox) / 2), kChevronBox, kChevronBox);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (highlighted) _highlight.alpha = 1;
    else [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self->_highlight.alpha = 0; } completion:nil];
}

@end

#pragma mark - a tile

@interface SGRPlayerMenuTile : UIControl
@property (nonatomic, readonly) SGRPlayerMenuItem *item;
- (instancetype)initWithItem:(SGRPlayerMenuItem *)item;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation SGRPlayerMenuTile {
    UIView *_highlight;
    UIImageView *_glyph;
    UILabel *_title;
}

- (instancetype)initWithItem:(SGRPlayerMenuItem *)item {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _item = item;
    UIColor *color = rowColor(item);
    _highlight = [UIView new];
    _highlight.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    _highlight.layer.cornerRadius = 14;
    _highlight.layer.cornerCurve = kCACornerCurveContinuous;
    _highlight.alpha = 0;
    [self addSubview:_highlight];
    UIImage *image = item.image;
    if (image.isSymbolImage) {
        image = [image imageByApplyingSymbolConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
    }
    _glyph = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    _glyph.tintColor = color;
    _title = [UILabel new];
    _title.font = tileFont();
    _title.textColor = color;
    _title.textAlignment = NSTextAlignmentCenter;
    _title.numberOfLines = 2;
    _title.text = item.title;
    for (UIView *view in @[_highlight, _glyph, _title]) view.userInteractionEnabled = NO;
    [self addSubview:_glyph];
    [self addSubview:_title];
    self.enabled = !item.disabled;
    self.alpha = item.disabled ? 0.4 : 1;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton | (item.disabled ? UIAccessibilityTraitNotEnabled : 0);
    self.accessibilityLabel = item.title;
    return self;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat text = ceil([_title sizeThatFits:CGSizeMake(MAX(0, width - 2 * kTileSide), CGFLOAT_MAX)].height);
    return kTileTop + kTileGlyph + kTileGap + text + kTileBottom;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _highlight.frame = CGRectInset(bounds, 4, 4);
    placeGlyph(_glyph, CGRectMake(round((bounds.size.width - kTileGlyph) / 2), kTileTop, kTileGlyph, kTileGlyph));
    CGFloat width = MAX(0, bounds.size.width - 2 * kTileSide);
    CGFloat text = ceil([_title sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    _title.frame = CGRectMake(kTileSide, kTileTop + kTileGlyph + kTileGap, width, text);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    if (highlighted) _highlight.alpha = 1;
    else [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self->_highlight.alpha = 0; } completion:nil];
}

@end

// Up to three tiles side by side.
@interface SGRPlayerMenuTiles : UIView
@end

@implementation SGRPlayerMenuTiles
@end

#pragma mark - what a row opens onto

// Clips what it holds to the height it is given, so it can open from nothing.
@interface SGRPlayerMenuExpansion : UIView
@property (nonatomic, weak) SGRPlayerMenuRow *row;
@property (nonatomic, strong) UIView *content;   // the caller's view, or nil for rows
@property (nonatomic, copy) NSArray<SGRPlayerMenuRow *> *rows;
@end

@implementation SGRPlayerMenuExpansion

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    return self;
}

- (CGFloat)fullHeightForWidth:(CGFloat)width {
    if (self.content || self.row.item.makeExpansion) return self.row.item.expansionHeight;
    CGFloat height = 0;
    for (SGRPlayerMenuRow *row in self.rows) height += [row heightForWidth:width];
    return height;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    // Laid out at their full height whatever the clip shows, so they slide into view rather than squash.
    if (self.content) self.content.frame = CGRectMake(0, 0, width, self.row.item.expansionHeight);
    CGFloat y = 0;
    for (SGRPlayerMenuRow *row in self.rows) {
        CGFloat height = [row heightForWidth:width];
        row.frame = CGRectMake(0, y, width, height);
        y += height;
    }
}

@end

#pragma mark - the card

@implementation SGRPlayerMenuCard {
    UIView *_backdrop;
    UIScrollView *_scroll;
    NSMutableArray *_plan;
    NSMutableSet<NSString *> *_expanded;
    UIActivityIndicatorView *_spinner;
    CGPoint _anchor;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    // Glass takes the appearance it inherits, and this is not in a navigation stack Spotify made dark.
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tintColor = SGRPrimary();
    self.accessibilityViewIsModal = YES;
    _plan = [NSMutableArray array];
    _expanded = [NSMutableSet set];

    if (SGRReduceTransparency()) {
        _backdrop = [UIView new];
        _backdrop.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
        _backdrop.layer.cornerRadius = kCorner;
        _backdrop.layer.cornerCurve = kCACornerCurveContinuous;
    } else {
        UIVisualEffect *effect = SGGlassEffect();
        // A dark film in the glass, so white words read over the brightest cover behind it.
        if ([effect respondsToSelector:@selector(setTintColor:)]) [(id)effect setTintColor:[UIColor colorWithWhite:0 alpha:0.28]];
        UIVisualEffectView *glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        _backdrop = glass;
    }
    _backdrop.userInteractionEnabled = NO;
    [self addSubview:_backdrop];

    _scroll = [UIScrollView new];
    _scroll.backgroundColor = UIColor.clearColor;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.alwaysBounceVertical = NO;
    _scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scroll.layer.cornerRadius = kCorner;
    _scroll.layer.cornerCurve = kCACornerCurveContinuous;
    _scroll.clipsToBounds = YES;
    [self addSubview:_scroll];
    return self;
}

- (BOOL)accessibilityPerformEscape {
    if (self.onEscape) self.onEscape();
    return self.onEscape != nil;
}

#pragma mark building

- (void)clear {
    for (id entry in _plan) {
        if ([entry isKindOfClass:UIView.class]) [(UIView *)entry removeFromSuperview];
    }
    [_plan removeAllObjects];
    [_spinner removeFromSuperview];
    _spinner = nil;
}

- (UIView *)separator {
    UIView *line = [UIView new];
    line.backgroundColor = SGRHairline();
    line.userInteractionEnabled = NO;
    line.isAccessibilityElement = NO;
    return line;
}

- (SGRPlayerMenuRow *)rowFor:(SGRPlayerMenuItem *)item {
    SGRPlayerMenuRow *row = [[SGRPlayerMenuRow alloc] initWithItem:item];
    [row addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}

- (void)showSections:(NSArray<SGRPlayerMenuSection *> *)sections {
    [self clear];
    BOOL first = YES;
    for (SGRPlayerMenuSection *section in sections) {
        if (!section.items.count) continue;
        if (!first) [_plan addObject:[self separator]];
        first = NO;
        if (section.tiles) {
            SGRPlayerMenuTiles *tiles = [SGRPlayerMenuTiles new];
            for (SGRPlayerMenuItem *item in [section.items subarrayWithRange:NSMakeRange(0, MIN(3, section.items.count))]) {
                SGRPlayerMenuTile *tile = [[SGRPlayerMenuTile alloc] initWithItem:item];
                [tile addTarget:self action:@selector(tileTapped:) forControlEvents:UIControlEventTouchUpInside];
                [tiles addSubview:tile];
            }
            [_plan addObject:tiles];
            continue;
        }
        [_plan addObject:NSNull.null];
        for (SGRPlayerMenuItem *item in section.items) {
            SGRPlayerMenuRow *row = [self rowFor:item];
            [_plan addObject:row];
            if (!item.opens) continue;
            SGRPlayerMenuExpansion *expansion = [SGRPlayerMenuExpansion new];
            expansion.row = row;
            if (item.children.count) {
                // A shade darker than the pane, so the rows it opens onto read as its own.
                expansion.backgroundColor = [UIColor colorWithWhite:0 alpha:0.14];
                NSMutableArray *rows = [NSMutableArray array];
                for (SGRPlayerMenuItem *child in item.children) {
                    SGRPlayerMenuRow *childRow = [self rowFor:child];
                    [expansion addSubview:childRow];
                    [rows addObject:childRow];
                }
                expansion.rows = rows;
            }
            BOOL open = item.key && [_expanded containsObject:item.key];
            row.expanded = open;
            if (open) [self fill:expansion];
            expansion.alpha = open ? 1 : 0;
            expansion.accessibilityElementsHidden = !open;
            [_plan addObject:expansion];
        }
        [_plan addObject:NSNull.null];
    }
    for (id entry in _plan) {
        if ([entry isKindOfClass:UIView.class]) [_scroll addSubview:entry];
    }
    [self setNeedsLayout];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
}

- (void)showLoading {
    [self clear];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = SGRSecondary();
    [_spinner startAnimating];
    [_scroll addSubview:_spinner];
    [self setNeedsLayout];
}

// The caller's view, made the first time its row opens.
- (void)fill:(SGRPlayerMenuExpansion *)expansion {
    SGRPlayerMenuItem *item = expansion.row.item;
    if (expansion.content || !item.makeExpansion) return;
    expansion.content = item.makeExpansion();
    if (expansion.content) [expansion addSubview:expansion.content];
}

- (void)setSubtitle:(NSString *)subtitle forKey:(NSString *)key {
    for (id entry in _plan) {
        if (![entry isKindOfClass:SGRPlayerMenuRow.class] || ![((SGRPlayerMenuRow *)entry).item.key isEqualToString:key]) continue;
        SGRPlayerMenuRow *row = entry;
        CGFloat before = [row heightForWidth:SGRPlayerMenuWidth];
        row.item.subtitle = subtitle;
        [row showSubtitle:subtitle];
        if (fabs([row heightForWidth:SGRPlayerMenuWidth] - before) > 0.5) {
            [self setNeedsLayout];
            [self layoutIfNeeded];
            if (self.sizeChanged) self.sizeChanged(self);
        }
    }
}

- (void)setExpansionHeight:(CGFloat)height forKey:(NSString *)key {
    for (id entry in _plan) {
        if (![entry isKindOfClass:SGRPlayerMenuRow.class] || ![((SGRPlayerMenuRow *)entry).item.key isEqualToString:key]) continue;
        SGRPlayerMenuRow *row = entry;
        if (fabs(row.item.expansionHeight - height) < 0.5) continue;
        if (!row.expanded) {
            row.item.expansionHeight = height;
            continue;
        }
        [self layoutIfNeeded];
        SGRAnimate(SGRMotionLayout, ^{
            row.item.expansionHeight = height;
            [self setNeedsLayout];
            [self layoutIfNeeded];
            if (self.sizeChanged) self.sizeChanged(self);
            [self layoutIfNeeded];
        }, nil);
    }
}

#pragma mark taps

- (void)tileTapped:(SGRPlayerMenuTile *)tile {
    if (tile.item.action) tile.item.action();
}

- (void)rowTapped:(SGRPlayerMenuRow *)row {
    if (!row.item.opens) {
        if (row.item.action) row.item.action();
        return;
    }
    SGRPlayerMenuExpansion *expansion = nil;
    for (id entry in _plan) {
        if ([entry isKindOfClass:SGRPlayerMenuExpansion.class] && ((SGRPlayerMenuExpansion *)entry).row == row) expansion = entry;
    }
    if (!expansion) return;
    BOOL open = !row.expanded;
    if (row.item.key) {
        if (open) [_expanded addObject:row.item.key];
        else [_expanded removeObject:row.item.key];
    }
    if (open) [self fill:expansion];
    [self layoutIfNeeded];
    SGRAnimate(SGRMotionLayout, ^{
        row.expanded = open;
        expansion.alpha = open ? 1 : 0;
        [self setNeedsLayout];
        [self layoutIfNeeded];
        if (self.sizeChanged) self.sizeChanged(self);
        [self layoutIfNeeded];
    }, ^(BOOL finished) {
        if (open) [self->_scroll scrollRectToVisible:[self->_scroll convertRect:expansion.bounds fromView:expansion] animated:YES];
    });
    expansion.accessibilityElementsHidden = !open;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, open ? expansion : nil);
}

#pragma mark layout

// One pass over the plan: the content's height, and the frames when `apply`.
- (CGFloat)pass:(BOOL)apply width:(CGFloat)width {
    if (_spinner) {
        if (apply) _spinner.center = CGPointMake(width / 2, kLoadingHeight / 2);
        return kLoadingHeight;
    }
    CGFloat y = 0;
    for (id entry in _plan) {
        if (entry == NSNull.null) {
            y += kSectionPadding;
        } else if ([entry isKindOfClass:SGRPlayerMenuRow.class]) {
            CGFloat height = [(SGRPlayerMenuRow *)entry heightForWidth:width];
            if (apply) ((UIView *)entry).frame = CGRectMake(0, y, width, height);
            y += height;
        } else if ([entry isKindOfClass:SGRPlayerMenuExpansion.class]) {
            SGRPlayerMenuExpansion *expansion = entry;
            CGFloat height = expansion.row.expanded ? [expansion fullHeightForWidth:width] : 0;
            if (apply) expansion.frame = CGRectMake(0, y, width, height);
            y += height;
        } else if ([entry isKindOfClass:SGRPlayerMenuTiles.class]) {
            UIView *tiles = entry;
            NSUInteger count = tiles.subviews.count;
            CGFloat tileWidth = (width - 2 * kTileSide) / count, height = 0;
            for (SGRPlayerMenuTile *tile in tiles.subviews) height = MAX(height, [tile heightForWidth:tileWidth]);
            if (apply) {
                tiles.frame = CGRectMake(0, y, width, height);
                [tiles.subviews enumerateObjectsUsingBlock:^(UIView *tile, NSUInteger i, BOOL *stop) {
                    tile.frame = CGRectMake(kTileSide + i * tileWidth, 0, tileWidth, height);
                }];
            }
            y += height;
        } else {
            // A hairline between two groups.
            if (apply) ((UIView *)entry).frame = CGRectMake(kSeparatorInset, y, width - 2 * kSeparatorInset, hairline(self));
            y += hairline(self);
        }
    }
    return ceil(y);
}

- (CGFloat)preferredHeight {
    return [self pass:NO width:SGRPlayerMenuWidth];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _backdrop.frame = bounds;
    if ([_backdrop isKindOfClass:UIVisualEffectView.class]) SGShapeGlass(_backdrop, kCorner, NO);
    _scroll.frame = bounds;
    CGFloat height = [self pass:YES width:bounds.size.width];
    _scroll.contentSize = CGSizeMake(bounds.size.width, height);
    _scroll.scrollEnabled = height > bounds.size.height + 0.5;
    _scroll.showsVerticalScrollIndicator = _scroll.scrollEnabled;
}

#pragma mark coming and going

// A scale of `scale` about `anchor`, a point in the card's own coordinates.
- (CGAffineTransform)scale:(CGFloat)scale about:(CGPoint)anchor {
    CGSize size = self.bounds.size;
    CGFloat dx = anchor.x - size.width / 2, dy = anchor.y - size.height / 2;
    return CGAffineTransformTranslate(CGAffineTransformScale(CGAffineTransformMakeTranslation(dx, dy), scale, scale), -dx, -dy);
}

- (void)growFrom:(CGPoint)anchor {
    _anchor = anchor;
    self.alpha = 0;
    if (SGRReduceMotion()) {
        [UIView animateWithDuration:0.2 animations:^{ self.alpha = 1; }];
        return;
    }
    self.transform = [self scale:0.35 about:anchor];
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
                     animations:^{ self.alpha = 1; } completion:nil];
}

- (void)shrinkAway:(void (^)(void))completion {
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.alpha = 0;
        if (!SGRReduceMotion()) self.transform = [self scale:0.6 about:self->_anchor];
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
}

@end
