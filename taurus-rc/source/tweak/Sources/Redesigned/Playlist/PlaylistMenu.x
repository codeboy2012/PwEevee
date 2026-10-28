#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

NSString *const SGRPlaylistCurationIdentifier = @"PlaylistCuration.Row.CurationActionsToolbar";

static NSString *const kMixIdentifier = @"ListPlatform.ToolbarActions.MixButton";

static const CGFloat kRowHeight = 56, kSideMargin = 16, kGlyphSide = 24, kGlyphGap = 16;

static char kToolbarKey, kSortKey, kBlockKey, kDecidedKey;

#pragma mark - Spotify's pills

static NSString *glyphName(UIView *iconView) {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(iconView.class, &count);
    NSString *found = nil;
    for (unsigned int i = 0; i < count && !found; i++) {
        const char *type = ivar_getTypeEncoding(ivars[i]);
        if (!type || type[0] != '@') continue;
        id value = object_getIvar(iconView, ivars[i]);
        if (![value respondsToSelector:@selector(name)]) continue;
        NSString *name = [value name];
        if ([name isKindOfClass:NSString.class] && name.length) found = name;
    }
    free(ivars);
    return found;
}

static NSString *pillGlyph(UIView *pill) {
    static Class iconClass;
    if (!iconClass) iconClass = NSClassFromString(@"SPTEncoreIconView");
    __block NSString *name = nil;
    SGForEachView(pill, ^(UIView *v) {
        if (!name && iconClass && [v isKindOfClass:iconClass]) name = glyphName(v);
    });
    return name;
}

static NSString *pillWord(UIView *pill) {
    __block NSString *word = nil;
    SGForEachView(pill, ^(UIView *v) {
        if (word || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length) word = text;
    });
    return word ?: pill.accessibilityLabel;
}

static BOOL isSortGlyph(NSString *glyph) {
    NSString *name = glyph.lowercaseString;
    return [name containsString:@"sort"] || [name containsString:@"arrowupdown"] || [name containsString:@"filter"];
}

static void pillsIn(UIView *toolbar, UIView **sort, UIView **mix) {
    __block UIView *foundSort = nil, *foundMix = nil;
    __block NSMutableArray<NSString *> *seen = [NSMutableArray array];
    SGForEachView(toolbar, ^(UIView *v) {
        NSString *identifier = v.accessibilityIdentifier;
        if (!identifier.length || [identifier isEqualToString:SGRPlaylistCurationIdentifier]) return;
        if (!foundMix && [identifier containsString:kMixIdentifier]) {
            foundMix = v;
            return;
        }
        NSString *glyph = pillGlyph(v);
        if (glyph) [seen addObject:[NSString stringWithFormat:@"%@=%@", pillWord(v) ?: identifier, glyph]];
        if (!foundSort && isSortGlyph(glyph)) foundSort = v;
    });
    // Said once, so a build that renames the sort glyph says what it calls it instead of going quiet.
    static BOOL logged;
    if (!logged && seen.count) {
        logged = YES;
        SGLog(@"redesign playlist: the curation pills draw %@; sort %@", [seen componentsJoinedByString:@", "],
              foundSort ? @"found" : @"NOT FOUND");
    }
    *sort = foundSort;
    *mix = foundMix;
}

void SGRPlaylistTakeSort(UIView *page, UIView *button) {
    if (page && button && objc_getAssociatedObject(page, &kSortKey) != button) {
        objc_setAssociatedObject(page, &kSortKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

void SGRPlaylistTakeCuration(UIView *cell) {
    UIView *toolbar = SGRFindByIdentifier(cell, SGRPlaylistCurationIdentifier, &kToolbarKey);
    UIView *page = toolbar ? SGRPlaylistPageOf(cell) : nil;
    if (!page || objc_getAssociatedObject(page, &kToolbarKey) == toolbar) return;
    objc_setAssociatedObject(page, &kToolbarKey, toolbar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *sort = nil, *mix = nil;
    pillsIn(toolbar, &sort, &mix);
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign playlist: the curation row is the page's, sort %@, mix %@",
              sort ? pillWord(sort) : @"not found", mix ? pillWord(mix) : @"not found");
    }
}

#pragma mark - the block on the sheet

@interface SGRMenuRow : UIControl
@property (nonatomic, weak) UIView *pill;
@end

@implementation SGRMenuRow {
    UIImageView *_glyph;
    UILabel *_word;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.tintColor = UIColor.whiteColor;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];

    _word = [UILabel new];
    _word.textColor = UIColor.whiteColor;
    _word.font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize
                                   weight:UIFontWeightRegular];
    _word.userInteractionEnabled = NO;
    [self addSubview:_word];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(sgr_up)
   forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return self;
}

- (void)showWord:(NSString *)word symbol:(NSString *)symbol {
    if (![_word.text isEqualToString:word]) {
        _word.text = word;
        self.accessibilityLabel = word;
    }
    if (!_glyph.image) _glyph.image = [UIImage systemImageNamed:symbol];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _glyph.frame = CGRectMake(kSideMargin, round((bounds.size.height - kGlyphSide) / 2), kGlyphSide, kGlyphSide);
    CGFloat lead = kSideMargin + kGlyphSide + kGlyphGap;
    [_word sizeToFit];
    _word.frame = CGRectMake(lead, round((bounds.size.height - _word.bounds.size.height) / 2),
                             MAX(0, bounds.size.width - lead - kSideMargin), _word.bounds.size.height);
}

- (void)sgr_down {
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
}

- (void)sgr_up {
    self.backgroundColor = UIColor.clearColor;
}

@end

@interface SGRMenuBlock : UIView
@property (nonatomic, weak) UIViewController *menu;
- (void)showSort:(UIView *)sort mix:(UIView *)mix;
- (CGFloat)wantedHeight;
@end

@implementation SGRMenuBlock {
    SGRMenuRow *_sort, *_mix;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _sort = [[SGRMenuRow alloc] initWithFrame:CGRectZero];
    _mix = [[SGRMenuRow alloc] initWithFrame:CGRectZero];
    for (SGRMenuRow *row in @[_sort, _mix]) {
        row.hidden = YES;
        [row addTarget:self action:@selector(sgr_rowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:row];
    }
    return self;
}

- (void)showSort:(UIView *)sort mix:(UIView *)mix {
    _sort.pill = sort;
    _mix.pill = mix;
    if (sort) [_sort showWord:pillWord(sort) symbol:@"arrow.up.arrow.down"];
    if (mix) [_mix showWord:pillWord(mix) symbol:@"slider.horizontal.3"];
    _sort.hidden = sort == nil;
    _mix.hidden = mix == nil;
    [self setNeedsLayout];
}

- (CGFloat)wantedHeight {
    CGFloat height = 0;
    for (SGRMenuRow *row in @[_sort, _mix]) height += row.hidden ? 0 : kRowHeight;
    return height;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat y = 0;
    for (SGRMenuRow *row in @[_sort, _mix]) {
        if (row.hidden) continue;
        row.frame = CGRectMake(0, y, self.bounds.size.width, kRowHeight);
        y += kRowHeight;
    }
}

- (void)sgr_rowTapped:(SGRMenuRow *)row {
    UIView *pill = row.pill;
    UIViewController *menu = self.menu;
    void (^fire)(void) = ^{
        SGRActivate(pill);
        static BOOL logged;
        if (!logged) {
            logged = YES;
            SGLog(@"redesign playlist: the sheet fired %@, still on screen: %@", row.accessibilityLabel,
                  pill.window ? @"yes" : @"no");
        }
    };
    UIViewController *presented = menu.navigationController ?: menu;
    if (presented.presentingViewController) [presented dismissViewControllerAnimated:YES completion:fire];
    else fire();
}

@end

#pragma mark - the sheet's pass

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static UIView *curationIn(UIView *page) {
    UIView *found = SGRFindByIdentifier(page, SGRPlaylistCurationIdentifier, NULL);
    if (found) {
        if (found != objc_getAssociatedObject(page, &kToolbarKey)) {
            objc_setAssociatedObject(page, &kToolbarKey, found, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return found;
    }
    return objc_getAssociatedObject(page, &kToolbarKey);
}

static UIView *pageFor(UIViewController *menu) {
    id decided = objc_getAssociatedObject(menu, &kDecidedKey);
    if (decided) return decided == NSNull.null ? nil : decided;
    UIView *page = SGRPinnedMoreRecentPage();
    if (page) curationIn(page);
    objc_setAssociatedObject(menu, &kDecidedKey, page ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return page;
}

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    UIView *page = root ? pageFor(menu) : nil;
    if (!page) return;
    UITableView *table = tableIn(root, 0);
    CGFloat width = table.bounds.size.width;
    if (!table || width <= 0) return;
    // Spotify already uses the header on some sheets; there the rows go under its own instead.
    SGRMenuBlock *block = objc_getAssociatedObject(menu, &kBlockKey);
    BOOL inFooter = block ? [objc_getAssociatedObject(block, &kBlockKey) boolValue] : NO;
    if (!block) {
        BOOL headerFree = !table.tableHeaderView || table.tableHeaderView.bounds.size.height < 1;
        inFooter = !headerFree;
        if (inFooter && table.tableFooterView && table.tableFooterView.bounds.size.height >= 1) {
            SGLog(@"redesign playlist: the sheet's header and footer are both Spotify's, sort and mix left out");
            objc_setAssociatedObject(menu, &kDecidedKey, NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        block = [[SGRMenuBlock alloc] initWithFrame:CGRectZero];
        block.menu = menu;
        objc_setAssociatedObject(block, &kBlockKey, @(inFooter), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(menu, &kBlockKey, block, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIView *sort = nil, *mix = nil;
    pillsIn(objc_getAssociatedObject(page, &kToolbarKey), &sort, &mix);
    sort = objc_getAssociatedObject(page, &kSortKey) ?: sort;
    [block showSort:sort mix:mix];
    CGFloat height = [block wantedHeight];
    if (height < 1) return;

    CGRect frame = CGRectMake(0, 0, width, height);
    UIView *placed = inFooter ? table.tableFooterView : table.tableHeaderView;
    if (placed == block && CGRectEqualToRect(block.frame, frame)) return;
    block.frame = frame;
    if (inFooter) table.tableFooterView = block;
    else table.tableHeaderView = block;
    [table invalidateIntrinsicContentSize];
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign playlist: the ⋯ sheet took %.0fpt of sort and mix in its %@", height,
              inFooter ? @"footer" : @"header");
    }
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
