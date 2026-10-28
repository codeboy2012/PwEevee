#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"
#import <objc/message.h>

static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
static const CGFloat kMinHero = 120, kMinCover = 80;

static char kCoverKey, kMetaKey, kPlayKey, kLayoutKey, kToolbarKey, kScrimKey, kBarScrimKey;
static char kIndependentActionsKey;
static char kShuffleKey, kAddKey, kDownloadKey, kInfoKey, kBlockHeightKey, kBlockWatchedKey;
static char kHeroKey, kHeroHeightKey, kRestPlaneKey, kRowKey, kRowWatchedKey, kMoreKey, kCreatorKey, kPinnedMoreKey, kSortKey;

#pragma mark - finding things

@interface SGRWeakView : NSObject
@property (nonatomic, weak) UIView *view;
@end
@implementation SGRWeakView
@end

UIView *SGRPlaylistPageOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        if ([NSStringFromClass(r.class) containsString:@"FTPViewController"]) return ((UIViewController *)r).viewIfLoaded;
    }
    return nil;
}

UIViewController *SGRPlaylistHeaderOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        return [NSStringFromClass(r.class) containsString:@"FreeTierPlaylist"] ? (UIViewController *)r : nil;
    }
    return nil;
}

static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *firstOfClass(UIView *root, Class wanted) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v isKindOfClass:wanted]) found = v;
    });
    return found;
}

#pragma mark - the cover, full bleed

@interface SGRPlaylistHero : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic) CGFloat coverPixels;   // the widest copy of the artwork it has been shown
- (void)followCover:(UIImageView *)source;
@end

@implementation SGRPlaylistHero {
    CAGradientLayer *_scrim, *_dissolve;   // the dissolve is the layer's mask
    __weak UIImageView *_cover;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.clipsToBounds = YES;

    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_picture];

    // Above the picture's own layer whatever else is added to the view later.
    _scrim = [CAGradientLayer layer];
    _scrim.zPosition = 1;
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [self.layer addSublayer:_scrim];

    _dissolve = [CAGradientLayer layer];
    _dissolve.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.28].CGColor, (id)UIColor.clearColor.CGColor];
    self.layer.mask = _dissolve;
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, 0, bounds.size.width, MIN(kTopScrim, bounds.size.height));
    CGFloat height = MAX(1, bounds.size.height), fade = round(height * kDissolve);
    _dissolve.frame = bounds;
    _dissolve.locations = @[@0, @((height - fade) / height), @((height - fade * 0.38) / height), @1];
    [CATransaction commit];
}

- (void)followCover:(UIImageView *)source {
    if (!source) return;
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRPlaylistHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinHero || _picture.image == image) return;

    self.coverPixels = image.size.width;
    _picture.image = image;
    // The page's field takes its colour from the same picture.
    SGRPlaylistSetArtwork(self, image);
    SGRRevealMark(SGRPlaylistPageOf(self), SGRRevealPicture);
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign playlist: the cover landed after the header had laid out; the hero took it");
    }
}

@end

static UIImageView *coverImageIn(UIView *cover) {
    __block UIImageView *found = nil, *empty = nil;
    SGForEachView(cover, ^(UIView *v) {
        if (found || ![v isKindOfClass:UIImageView.class]) return;
        UIImageView *image = (UIImageView *)v;
        if (image.bounds.size.width < kMinCover) return;
        if (image.image) found = image;
        else if (!empty) empty = image;
    });
    return found ?: empty;
}

static void applyHero(UIView *layout, UIView *cover, UIView *plane, UIView *block, CGFloat reach, CGFloat stretch) {
    if (!plane || !block) return;
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    if (!hero) {
        hero = [[SGRPlaylistHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(plane, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != plane) [plane insertSubview:hero atIndex:0];
    else if (plane.subviews.firstObject != hero) [plane sendSubviewToBack:hero];

    // Grow-only: a header still loading puts the block higher than it ends up.
    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    CGFloat top = CGRectGetMinY(block.frame);
    if (stretch < 0.5 && top > height + 0.5) {
        height = top;
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign playlist: hero %.0fpt across the top of the plane", height);
    }
    if (height < kMinHero) return;
    CGFloat bottom = MAX(kMinHero, round(height + reach)) + stretch;
    // Flexible height as well, for a plane resized after this pass in the same frame.
    hero.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0, 0, plane.bounds.size.width, bottom);
    if (!CGRectEqualToRect(hero.frame, frame)) hero.frame = frame;

    [hero followCover:coverImageIn(cover)];
    conceal(cover);
}

#pragma mark - the block, the redesign's own

static id viewModelOf(UIViewController *headerVC) {
    SEL controllerSel = NSSelectorFromString(@"headerController"), modelSel = NSSelectorFromString(@"defaultHeaderViewModel");
    if (![headerVC respondsToSelector:controllerSel]) return nil;
    id controller = ((id (*)(id, SEL))objc_msgSend)(headerVC, controllerSel);
    if (![controller respondsToSelector:modelSel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(controller, modelSel);
}

static NSString *modelString(id model, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (![model respondsToSelector:sel]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(model, sel);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BOOL modelFlag(id model, NSString *name, BOOL fallback) {
    SEL sel = NSSelectorFromString(name);
    if (![model respondsToSelector:sel]) return fallback;
    return ((BOOL (*)(id, SEL))objc_msgSend)(model, sel);
}

// A description is HTML: links to other playlists as <a> and entities for quotes and ampersands.
static NSString *plainText(NSString *html) {
    if (!html.length) return nil;
    static NSRegularExpression *tags;
    if (!tags) tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:NULL];
    NSMutableString *text = [[tags stringByReplacingMatchesInString:html options:0 range:NSMakeRange(0, html.length)
                                                       withTemplate:@""] mutableCopy];
    NSDictionary<NSString *, NSString *> *entities = @{@"&amp;": @"&", @"&quot;": @"\"", @"&#x27;": @"'", @"&#39;": @"'",
                                                       @"&lt;": @"<", @"&gt;": @">", @"&nbsp;": @" "};
    for (NSString *entity in entities) {
        [text replaceOccurrencesOfString:entity withString:entities[entity] options:0 range:NSMakeRange(0, text.length)];
    }
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length ? trimmed : nil;
}

static NSString *firstText(UIView *root, UIView *skip) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class] || (skip && [v isDescendantOfView:skip])) return;
        NSString *text = [((UILabel *)v).text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length > 1) found = text;
    });
    return found;
}

static NSString *creatorIn(UIView *block) {
    __block UIView *facepile = nil;
    SGForEachView(block, ^(UIView *v) {
        if (!facepile && [NSStringFromClass(v.class) containsString:@"FacepileView"]) facepile = v;
    });
    UIView *row = facepile.superview;
    for (NSUInteger level = 0; row && row != block && level < 3; level++, row = row.superview) {
        NSString *name = firstText(row, facepile);
        if (name) return name;
    }
    return nil;
}

// The length line, as Spotify words it in the app's language: "8 saves • 41h 14m", "1 038 songs".
static NSString *lengthIn(UIView *block) {
    return firstText(SGRFindByIdentifier(block, @"Components.Header.UI.Metadata", &kMetaKey), nil);
}

static void showPlaylist(SGRHeaderInfo *info, UIView *block, UIView *root, id model) {
    NSString *title = modelString(model, @"playlistName") ?: firstText(block, nil);
    [info showTitle:title creator:creatorIn(block) length:lengthIn(block)
              about:plainText(modelString(model, @"playlistDescription"))];

    BOOL liked = [modelString(model, @"formatListType") isEqualToString:@"liked-songs"];
    BOOL own = modelFlag(model, @"isOwnedBySelf", YES) || liked;
    UIView *shuffle = SGRFindByIdentifier(block, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *play = SGRFindByIdentifier(root, @"header-play-button", &kPlayKey);
    UIView *save = own ? nil : SGRFindByIdentifier(block, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = SGRFindByIdentifier(block, @"DownloadButton.Granular*", &kDownloadKey);
    BOOL independent = [objc_getAssociatedObject(info, &kIndependentActionsKey) boolValue];
    if (!independent && save && download) {
        independent = YES;
        objc_setAssociatedObject(info, &kIndependentActionsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (independent) {
        [info showAlbumShuffle:shuffle play:play download:download add:save playColor:SGRPlaylistFieldColor(info)];
    } else {
        [info showShuffle:shuffle play:play trailing:save ?: download
         trailingFallback:[UIImage systemImageNamed:save ? @"plus" : @"arrow.down"] playColor:SGRPlaylistFieldColor(info)];
    }
    // Only what the button draws goes: a concealed layer still sends the actions the capsule fires.
    conceal(play);

    [info showCreatorLink:SGRFindByIdentifier(block, @"Components.PlaylistHeader.collaboratorsButton", &kCreatorKey)];

    UIView *page = SGRPlaylistPageOf(root);
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(block, @"Components.UI.ContextMenuButton*", &kMoreKey));
    SGRPlaylistTakeSort(page, SGRFindByIdentifier(root, @"Components.Header.UI.Toolbar.Button", &kSortKey));
    // The name and Play are what the header waits for; the row's other buttons fade in on their own when late.
    if (title && play) SGRRevealMark(page, SGRRevealHeader);

    static BOOL logged;
    if (!logged && info.window && (title || play)) {
        logged = YES;
        SGLog(@"redesign playlist: own block \"%@\" by %@, \"%@\"; shuffle %@, play %@, %@; model %@",
              title, creatorIn(block) ?: @"nobody", lengthIn(block) ?: @"no length", shuffle ? @"found" : @"missing",
              play ? @"found" : @"missing", save ? @"save" : (download ? @"download" : @"nothing on the right"),
              model ? NSStringFromClass([model class]) : @"missing");
    }
}

static SGRHeaderInfo *applyInfo(UIView *block, UIView *headerRoot, UIViewController *headerVC);

// `view`'s own pass puts the block together again, installed once under `key`.
static void reapplyOnPass(UIView *view, const void *key, UIView *block, UIView *headerRoot, UIViewController *headerVC) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakBlock = block, *weakRoot = headerRoot;
    __weak UIViewController *weakVC = headerVC;
    SGRObserveLayout(view, ^(UIView *laidOut) {
        // A block the view has since left is Spotify's to lay out alone.
        if (!weakBlock || !weakRoot || !weakVC || [objc_getAssociatedObject(weakRoot, &kInfoKey) superview] != weakBlock) return;
        applyInfo(weakBlock, weakRoot, weakVC);
    });
}

static SGRHeaderInfo *applyInfo(UIView *block, UIView *headerRoot, UIViewController *headerVC) {
    SGRHeaderInfo *info = objc_getAssociatedObject(headerRoot, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(headerRoot, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != block) {
        if (info.superview) SGLog(@"redesign playlist: the block moved, %@ -> %@", NSStringFromCGRect(info.superview.frame), NSStringFromCGRect(block.frame));
        [block addSubview:info];
    }
    else if (block.subviews.lastObject != info) [block bringSubviewToFront:info];
    for (UIView *sub in block.subviews) {
        if (sub != info) conceal(sub);
    }
    // The page's width, centred on the screen: Spotify's block is 16pt narrower than the page (386 of 402).
    CGFloat x = -[block convertPoint:CGPointZero toView:headerRoot].x;
    CGRect frame = CGRectMake(round(x), 0, headerRoot.bounds.size.width, block.bounds.size.height);
    if (!CGRectEqualToRect(info.frame, frame)) info.frame = frame;
    showPlaylist(info, block, headerRoot, viewModelOf(headerVC));

    reapplyOnPass(block, &kBlockWatchedKey, block, headerRoot, headerVC);
    reapplyOnPass(SGRFindByIdentifier(block, @"HeaderActionsRow", &kRowKey), &kRowWatchedKey, block, headerRoot, headerVC);
    return info;
}

#pragma mark - the header's pass

static void glassUp(UIView *box, const void *key) {
    CGSize size = box.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    if (box.backgroundColor != UIColor.clearColor) box.backgroundColor = UIColor.clearColor;
    if (box.layer.cornerRadius != size.height / 2) box.layer.cornerRadius = size.height / 2;
    SGRGlassCapsuleInside(box, key, size, NO);
}

static void applyToolbar(UIView *headerRoot) {
    static char kFieldKey, kSortBoxKey, kFieldGlassKey, kSortGlassKey;
    UIView *toolbar = SGRFindByIdentifier(headerRoot, @"Components.Header.UI.Toolbar.Content", &kToolbarKey);
    if (!toolbar) return;
    UIView *field = SGRFindByIdentifier(toolbar, @"Components.Header.UI.Toolbar.SearchField", &kFieldKey);
    glassUp(field, &kFieldGlassKey);
    glassUp(SGRFindByIdentifier(toolbar, @"Components.Header.UI.Toolbar.ButtonContainer", &kSortBoxKey), &kSortGlassKey);
    static BOOL logged;
    if (!logged && field.window) {
        logged = YES;
        SGLog(@"redesign playlist: find field %@ in glass, %.0fx%.0f", field.accessibilityLabel,
              field.bounds.size.width, field.bounds.size.height);
    }
}

static void applyScrims(UIView *headerRoot) {
    conceal(SGRFindByIdentifier(headerRoot, @"LiquidGlass.gradientContainer", &kScrimKey));
    if (objc_getAssociatedObject(headerRoot, &kBarScrimKey)) return;
    static Class bar;
    if (!bar) bar = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderNavigationBar");
    UIView *navigation = firstOfClass(headerRoot, bar);
    for (UIView *sub in navigation.subviews) {
        if (![NSStringFromClass(sub.class) containsString:@"GradientView"]) continue;
        conceal(sub);
        objc_setAssociatedObject(headerRoot, &kBarScrimKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIView *applyBackground(UIView *layout) {
    UIView *container = nil;
    for (UIView *v = layout.superview; v && !container; v = v.superview) {
        for (UIView *sub in v.subviews) {
            if ([sub.accessibilityIdentifier isEqualToString:@"_backgroundViewContainer"]) container = sub;
        }
    }
    UIView *plane = container.subviews.firstObject;
    SGRPlaylistHero *hero = objc_getAssociatedObject(plane, &kHeroKey);
    SGForEachView(container, ^(UIView *v) {
        if (hero && (v == hero || [v isDescendantOfView:hero])) return;
        if ([NSStringFromClass(v.class) containsString:@"GradientView"]) {
            conceal(v);
            return;
        }
        CGColorRef color = v.layer.backgroundColor;
        if (color && SGIsBaseSurface(color)) v.backgroundColor = UIColor.clearColor;
    });
    return plane;
}

static UIView *fullbleedIn(UIView *layout) {
    static Class fullbleed;
    if (!fullbleed) fullbleed = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit26HeaderFullbleedCentralView");
    for (UIView *sub in layout.subviews) {
        if ([sub isKindOfClass:fullbleed]) return sub;
    }
    return nil;
}

static UIView *blockIn(UIView *layout, UIView *cover, UIView *fullbleed) {
    UIView *block = nil;
    CGFloat wide = layout.bounds.size.width * 0.6;
    for (UIView *sub in layout.subviews) {
        if (sub == cover || sub == fullbleed || [sub isKindOfClass:SGRPlaylistHero.class] || sub.bounds.size.width < wide) continue;
        if (!block || CGRectGetMinY(sub.frame) > CGRectGetMinY(block.frame)) block = sub;
    }
    return block;
}

static void applyHeader(UIView *layout) {
    UIViewController *headerVC = SGRPlaylistHeaderOf(layout);
    UIView *headerRoot = headerVC.viewIfLoaded;
    if (!headerRoot) return;

    UIView *fullbleed = fullbleedIn(layout);
    UIView *cover = SGRFindByIdentifier(layout, @"Components.Header.UI.ArtworkImage", &kCoverKey) ?: fullbleed;
    UIView *block = blockIn(layout, cover, fullbleed);
    if (!block) return;

    UIView *plane = applyBackground(layout);
    applyToolbar(headerRoot);
    applyScrims(headerRoot);
    SGRHeaderInfo *info = applyInfo(block, headerRoot, headerVC);

    CGFloat planeHeight = plane.bounds.size.height;
    CGFloat restPlane = [objc_getAssociatedObject(plane, &kRestPlaneKey) doubleValue];
    if (planeHeight > 0 && (restPlane <= 0 || planeHeight < restPlane - 0.5)) {
        restPlane = planeHeight;
        objc_setAssociatedObject(plane, &kRestPlaneKey, @(restPlane), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(objc_getAssociatedObject(plane, &kHeroKey), &kHeroHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(block, &kBlockHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat stretch = MAX(0, planeHeight - restPlane);

    CGFloat rest = [objc_getAssociatedObject(block, &kBlockHeightKey) doubleValue];
    if (stretch < 0.5 && block.bounds.size.height > rest) {
        rest = block.bounds.size.height;
        objc_setAssociatedObject(block, &kBlockHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat reach = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:info.bounds.size.width] + SGRHeaderInfoTitleRise;
    if (cover) applyHero(layout, cover, plane, block, reach, stretch);
}

static UIView *layoutIn(UIView *root) {
    if (!root) return nil;
    SGRWeakView *box = objc_getAssociatedObject(root, &kLayoutKey);
    UIView *layout = box.view;
    if (layout && [layout isDescendantOfView:root]) return layout;
    static Class content;
    if (!content) content = NSClassFromString(@"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout");
    layout = firstOfClass(root, content);
    if (!layout) return nil;
    if (!box) {
        box = [SGRWeakView new];
        objc_setAssociatedObject(root, &kLayoutKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    box.view = layout;
    return layout;
}

%hook _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout
- (void)layoutSubviews {
    %orig;
    if (SGRPlaylistHeaderOf((UIView *)self)) applyHeader((UIView *)self);
}
%end

%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    if (SGRPlaylistHeaderOf(button)) conceal(button);
}
%end

%hook SPTFreeTierPlaylistEncoreHeaderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *layout = layoutIn(((UIViewController *)self).viewIfLoaded);
    if (layout) applyHeader(layout);
}

- (void)update {
    %orig;
    UIView *layout = layoutIn(((UIViewController *)self).viewIfLoaded);
    if (layout) applyHeader(layout);
}

%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout",
        @"SPTFreeTierPlaylistEncoreHeaderViewController",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
