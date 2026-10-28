#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Artist.h"

static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
// A photo view narrower than this is a placeholder glyph, and a picture shorter than this one mid load.
static const CGFloat kMinCover = 80, kMinHero = 120;
// The collapsed ImageHeaderView, Spotify's navigation bar; the text fades out over the last kFade before it.
static const CGFloat kBar = 100, kFade = 150;

static char kInfoKey, kHeroKey, kHeroHeightKey, kContainerHeightKey, kRowWatchedKey;
static char kTitleKey, kMetaKey, kShuffleKey, kPlayKey, kFollowKey, kArtworkKey, kBarKey, kMoreKey, kMoreButtonKey;
static char kLogoNameKey;

#pragma mark - Spotify's views

static void blank(UIView *view) {
    if (!view) return;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void setFrame(UIView *view, CGRect frame) {
    if (view && !CGRectIsEmpty(frame) && !CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

static NSString *trimmed(NSString *text) {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : nil;
}

static void showLogo(SGRHeaderInfo *info, NSString *name) {
    if (!name.length || !SGEnabled(SGRKeyArtistLogo) ||
        [objc_getAssociatedObject(info, &kLogoNameKey) isEqualToString:name]) return;
    objc_setAssociatedObject(info, &kLogoNameKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    __weak SGRHeaderInfo *weakInfo = info;
    CGFloat pixels = UIScreen.mainScreen.bounds.size.width * UIScreen.mainScreen.scale;
    SGMotionArtistLogo(name, pixels, ^(UIImage *logo) {
        SGRHeaderInfo *shown = weakInfo;
        if (!shown || ![objc_getAssociatedObject(shown, &kLogoNameKey) isEqualToString:name]) return;
        [shown showTitleImage:logo];
        if (logo) SGLog(@"redesign artist: Apple Music's logo for %@", name);
    });
}

static NSString *firstText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class]) return;
        found = trimmed(((UILabel *)v).text);
    });
    return found;
}

// The TemplateKit container the header sits in, which scrolls with the page.
static UIView *containerOf(UIView *header) {
    for (UIView *v = header.superview; v; v = v.superview) {
        if ([NSStringFromClass(v.class) containsString:@"HeaderContainer"]) return v;
    }
    return nil;
}

#pragma mark - the photo, full bleed

@interface SGRArtistHero : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, copy) UIColor *fieldColor;
- (void)followArtwork:(UIImageView *)source;
@end

@implementation SGRArtistHero {
    CAGradientLayer *_scrim, *_dissolve;
    __weak UIImageView *_artwork;
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

    _scrim = [CAGradientLayer layer];
    _scrim.zPosition = 1;
    _scrim.colors = @[(id)[UIColor colorWithWhite:0 alpha:kTopScrimAlpha].CGColor, (id)UIColor.clearColor.CGColor];
    [self.layer addSublayer:_scrim];

    _dissolve = [CAGradientLayer layer];
    _dissolve.zPosition = 2;
    [self.layer addSublayer:_dissolve];
    self.fieldColor = SGRNeutralField();
    // The colour is read off the main thread, so it can land after the last layout pass of the page.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sgr_fieldColorDidChange)
                                               name:SGRFieldColorDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)sgr_fieldColorDidChange {
    if (self.superview) self.fieldColor = SGRArtistFieldColor(self);
}

- (void)setFieldColor:(UIColor *)color {
    if (!color || [_fieldColor isEqual:color]) return;
    _fieldColor = [color copy];
    // The clear end is the same colour with no alpha, so the fade keeps its hue instead of going through grey.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dissolve.colors = @[(id)[color colorWithAlphaComponent:0].CGColor,
                         (id)[color colorWithAlphaComponent:0.72].CGColor,
                         (id)color.CGColor];
    _dissolve.locations = @[@0, @0.62, @1];
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scrim.frame = CGRectMake(0, 0, bounds.size.width, MIN(kTopScrim, bounds.size.height));
    CGFloat fade = round(bounds.size.height * kDissolve);
    _dissolve.frame = CGRectMake(0, bounds.size.height - fade, bounds.size.width, fade);
    [CATransaction commit];
}

- (void)followArtwork:(UIImageView *)source {
    if (!source) return;
    [self takeArtwork:source late:NO];
    if (_artwork == source) return;
    _artwork = source;
    __weak SGRArtistHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeArtwork:view late:YES]; });
}

- (void)takeArtwork:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || _picture.image == image) return;
    _picture.image = image;
    // The page's field takes its colour from the same picture.
    SGRArtistSetArtwork(self, image);
    SGRRevealMark(SGRArtistPageOf(self), SGRRevealPicture);
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign artist: the photo landed after the header had laid out; the hero took it");
    }
}

@end

static UIImageView *photoIn(UIView *artwork) {
    __block UIImageView *found = nil, *empty = nil;
    SGForEachView(artwork, ^(UIView *v) {
        if (found || ![v isKindOfClass:UIImageView.class]) return;
        UIImageView *image = (UIImageView *)v;
        if (image.bounds.size.width < kMinCover) return;
        if (image.image) found = image;
        else if (!empty) empty = image;
    });
    return found ?: empty;
}

static void applyHero(UIView *container, UIView *artwork, CGFloat bottom) {
    SGRArtistHero *hero = objc_getAssociatedObject(container, &kHeroKey);
    if (!hero) {
        hero = [[SGRArtistHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(container, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != container) [container insertSubview:hero atIndex:0];
    else if (container.subviews.firstObject != hero) [container sendSubviewToBack:hero];

    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    if (bottom > height + 0.5) {
        height = round(bottom);
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign artist: hero %.0fpt across the top of the page", height);
    }
    if (height < kMinHero) return;
    setFrame(hero, CGRectMake(0, 0, container.bounds.size.width, height));
    hero.fieldColor = SGRArtistFieldColor(container);
    [hero followArtwork:photoIn(artwork)];
}

#pragma mark - the header's pass

static void applyHeader(UIView *header);

static UIView *keepBar(UIView *header) {
    UIView *foreground = nil;
    for (UIView *sub in header.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"HeaderForegroundView"]) foreground = sub;
    }
    if (foreground && !objc_getAssociatedObject(header, &kBarKey)) {
        SGForEachView(foreground, ^(UIView *v) {
            if ([NSStringFromClass(v.class) containsString:@"GradientView"] && !v.layer.mask) v.layer.mask = [CALayer layer];
        });
        objc_setAssociatedObject(header, &kBarKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return foreground;
}

static void applyHeader(UIView *header) {
    UIView *container = containerOf(header);
    UIView *artwork = SGRFindByIdentifier(header, @"Components.Header.UI.ArtworkImage", &kArtworkKey);
    UIView *page = SGRArtistPageOf(container);
    if (!container || !artwork || !page) return;
    // The photo header the redesign lays out: the page's curtain waits for all of it (ArtistField.x put it up).
    SGRRevealHold(page, SGRRevealPage);

    UIView *bar = keepBar(header);
    for (UIView *sub in header.subviews) {
        if (sub != bar) blank(sub);
    }

    SGRHeaderInfo *info = objc_getAssociatedObject(container, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        // Follow's only state is its title in the app's language, so the glyph takes it from the collection.
        __weak UIView *weakPage = page;
        __weak SGRHeaderInfo *weakInfo = info;
        __weak UIView *weakHeader = header;
        info.trailingState = ^BOOL(BOOL *on) {
            UIView *more = SGRFindByIdentifier(weakHeader, @"Components.UI.ContextMenuButton*", &kMoreKey);
            return SGRArtistFollowing(weakPage, more.accessibilityIdentifier, on, ^{ [weakInfo trailingStateChanged]; });
        };
        info.trailingOffSymbol = @"person.badge.plus";
        info.trailingOnSymbol = @"person.fill.checkmark";
        objc_setAssociatedObject(container, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != container) [container addSubview:info];
    setFrame(info, container.bounds);

    UIView *title = SGRFindByIdentifier(header, @"Encore.AdaptiveTitle", &kTitleKey);
    UIView *listeners = SGRFindByIdentifier(header, @"Components.Header.UI.Metadata", &kMetaKey);
    NSString *name = firstText(title) ?: firstText(bar), *listening = firstText(listeners);
    [info showTitle:name creator:nil length:listening about:nil];
    showLogo(info, name);

    __weak UIView *concertsHeader = header;
    SGRArtistConcerts(info, page, name, ^{
        if (concertsHeader) applyHeader(concertsHeader);
    });

    UIView *shuffle = SGRFindByIdentifier(header, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *play = SGRFindByIdentifier(header, @"header-play-button", &kPlayKey);
    UIView *follow = SGRFindByIdentifier(header, @"Curation.FollowButtonElementKit.FollowButton", &kFollowKey);
    [info showShuffle:shuffle play:play trailing:follow trailingFallback:nil playColor:SGRArtistFieldColor(container)];
    // The listeners are waited for with the name and Play: arriving late they pushed the name up by a line.
    if (name && play && listening) SGRRevealMark(page, SGRRevealHeader);

    UIView *more = SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey);
    SGRMirrorButton *pinnedMore = SGRPinnedMore(page, &kMoreButtonKey, more);
    pinnedMore.layer.zPosition = 10001;

    CGFloat alpha = MAX(0, MIN(1, (header.bounds.size.height - kBar) / kFade));
    if (fabs(info.alpha - alpha) > 0.01) info.alpha = alpha;

    CGFloat rest = MAX([objc_getAssociatedObject(container, &kContainerHeightKey) doubleValue], container.bounds.size.height);
    objc_setAssociatedObject(container, &kContainerHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat bottom = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:container.bounds.size.width] + SGRHeaderInfoTitleRise;
    applyHero(container, artwork, bottom);

    UIView *row = shuffle ?: play ?: follow;
    while (row && row.superview != header) row = row.superview;
    if (row && [row class] == UIStackView.class && !objc_getAssociatedObject(row, &kRowWatchedKey)) {
        objc_setAssociatedObject(row, &kRowWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHeader = header;
        SGRObserveLayout(row, ^(UIView *view) {
            if (weakHeader) applyHeader(weakHeader);
        });
    }

    static BOOL logged;
    if (!logged && header.window && name) {
        logged = YES;
        SGLog(@"redesign artist: own block \"%@\", \"%@\"; shuffle %@, play %@, follow %@, more %@", name,
              firstText(listeners) ?: @"no listeners", shuffle ? @"found" : @"missing", play ? @"found" : @"missing",
              follow ? @"found" : @"missing", more ? @"found" : @"missing");
    }
}

%hook _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView
- (void)layoutSubviews {
    %orig;
    applyHeader((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView"]);
}
