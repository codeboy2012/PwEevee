#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/LockScreenArtwork/SGAppleArtwork.h"
#import "Shared/LockScreenArtwork/SGArtworkFile.h"
#import "Shared/LockScreenArtwork/SGCanvas.h"
#import "Album.h"

static const CGFloat kDissolve = 0.46, kTopScrim = 140, kTopScrimAlpha = 0.28;
static const CGFloat kMinHero = 120, kMinCover = 80;

static char kHeaderKey, kCoverKey, kTitleKey, kParentKey, kMetaKey, kAddKey, kDownloadKey, kPlayKey, kShuffleKey;
static char kHeroKey, kHeroHeightKey, kHeaderHeightKey, kInfoKey, kHeaderWatchedKey, kRetryKey;
static char kExploreKey, kRowWatchedKey, kMoreKey, kPinnedMoreKey;

#pragma mark - moving Spotify's views

static void conceal(UIView *view) {
    if (!view) return;
    if (!view.layer.hidden) view.layer.hidden = YES;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static void blank(UIView *view) {
    if (!view) return;
    if (!view.layer.mask) view.layer.mask = [CALayer layer];
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *wrapperFor(UIView *control, UIView *stop) {
    UIView *wrapper = control;
    for (UIView *v = control.superview; v && v != stop; v = v.superview) {
        if (fabs(v.bounds.size.width - control.bounds.size.width) > 4) break;
        if (fabs(v.bounds.size.height - control.bounds.size.height) > 4) break;
        wrapper = v;
    }
    return wrapper;
}

static UIView *floatingIn(UIView *page, NSString *identifier, const void *cacheKey) {
    for (UIView *sub in page.subviews) {
        if (sub.bounds.size.width > 120) continue;
        UIView *found = SGRFindByIdentifier(sub, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}

static void setFrame(UIView *view, CGRect frame) {
    if (view && !CGRectIsEmpty(frame) && !CGRectEqualToRect(view.frame, frame)) view.frame = frame;
}

// The stack Spotify arranges the header's buttons in: the first one above `button`.
static UIView *rowOf(UIView *button, UIView *header) {
    for (UIView *v = button.superview; v && v != header; v = v.superview) {
        if ([v isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Installs `laidOut` on the view's own pass once, under `key`.
static void watch(UIView *view, const void *key, void (^laidOut)(UIView *view)) {
    if (!view || objc_getAssociatedObject(view, key)) return;
    objc_setAssociatedObject(view, key, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRObserveLayout(view, laidOut);
}

#pragma mark - the cover, full bleed

@interface SGRAlbumHero : UIView
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, copy) UIColor *fieldColor;
- (void)followCover:(UIImageView *)source;
// Apple Music's square animated cover over the picture, where it has one. The same album again is a no-op.
- (void)findMotionOf:(NSString *)album by:(NSString *)artist;
@end

static char kReadyContext;

@implementation SGRAlbumHero {
    CAGradientLayer *_scrim, *_dissolve;
    __weak UIImageView *_cover;
    NSString *_motionFor;
    NSURLSessionTask *_fetch;
    AVQueuePlayer *_player;
    AVPlayerLooper *_looper;
    AVPlayerLayer *_motion;
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
    [_fetch cancel];
    [_motion removeObserver:self forKeyPath:@"readyForDisplay" context:&kReadyContext];
    [_player pause];
}

- (void)sgr_fieldColorDidChange {
    if (self.superview) self.fieldColor = SGRAlbumFieldColor(self);
}

- (void)setFieldColor:(UIColor *)color {
    if (!color || [_fieldColor isEqual:color]) return;
    _fieldColor = [color copy];
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
    _motion.frame = bounds;
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
}

- (void)findMotionOf:(NSString *)album by:(NSString *)artist {
    if (!album.length || !artist.length || !SGFlag(SGRKeyAnimatedCovers, YES)) return;
    // Not even looked up while it could not move: the clip is megabytes.
    if (SGRReduceMotion() || NSProcessInfo.processInfo.lowPowerModeEnabled) return;
    NSString *wanted = [NSString stringWithFormat:@"%@\n%@", artist, album];
    if ([_motionFor isEqualToString:wanted]) return;
    _motionFor = wanted;
    __weak SGRAlbumHero *weakSelf = self;
    SGAppleArtworkFind(artist, album, NO, ^(SGCanvas *canvas, NSString *note) {
        SGRAlbumHero *hero = weakSelf;
        if (!hero || ![hero->_motionFor isEqualToString:wanted]) return;
        if (!canvas) {
            SGLog(@"redesign album: no animated cover for \"%@\": %@", album, note);
            return;
        }
        hero->_fetch = SGArtworkFetchAside(canvas.identifier, canvas.address, ^(NSURL *file, NSString *fetched) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGRAlbumHero *owner = weakSelf;
                if (!owner || ![owner->_motionFor isEqualToString:wanted]) return;
                owner->_fetch = nil;
                SGLog(@"redesign album: animated cover for \"%@\", %@", album, fetched);
                if (file) [owner playMotion:file];
            });
        });
    });
}

// Muted, never on AirPlay, and letting the screen lock: a picture, not a video.
- (void)playMotion:(NSURL *)file {
    if (_motion) return;
    AVQueuePlayer *player = [AVQueuePlayer new];
    player.muted = YES;
    player.allowsExternalPlayback = NO;
    player.preventsDisplaySleepDuringVideoPlayback = NO;
    _looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:[AVPlayerItem playerItemWithURL:file]];
    _player = player;
    _motion = [AVPlayerLayer playerLayerWithPlayer:player];
    _motion.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _motion.zPosition = 0.5;
    _motion.opacity = 0;
    _motion.frame = self.bounds;
    [self.layer addSublayer:_motion];
    [_motion addObserver:self forKeyPath:@"readyForDisplay" options:0 context:&kReadyContext];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    [self updateMotion];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kReadyContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_motion.readyForDisplay || self->_motion.opacity > 0) return;
        [CATransaction begin];
        [CATransaction setAnimationDuration:SGRCrossfade];
        self->_motion.opacity = 1;
        [CATransaction commit];
    });
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

// Only while the page is on screen and in front: a page under another one, or a tab away, holds still.
- (void)updateMotion {
    if (!_player) return;
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL moving = self.window && front && !SGRReduceMotion() && !NSProcessInfo.processInfo.lowPowerModeEnabled;
    if (moving && _player.rate == 0) [_player play];
    else if (!moving && _player.rate != 0) [_player pause];
}

- (void)followCover:(UIImageView *)source {
    if (!source) return;
    [self takeCover:source late:NO];
    if (_cover == source) return;
    _cover = source;
    __weak SGRAlbumHero *weakSelf = self;
    SGRObserveImage(source, ^(UIImageView *view) { [weakSelf takeCover:view late:YES]; });
}

- (void)takeCover:(UIImageView *)source late:(BOOL)late {
    UIImage *image = source.image;
    if (!image || source.bounds.size.width < kMinCover || _picture.image == image) return;
    _picture.image = image;
    // The page's field takes its colour from the same picture.
    SGRAlbumSetArtwork(self, image);
    SGRRevealMark(SGRAlbumPageOf(self), SGRRevealPicture);
    static BOOL logged;
    if (late && !logged) {
        logged = YES;
        SGLog(@"redesign album: the cover landed after the header had laid out; the hero took it");
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

static void applyHero(UIView *header, UIView *cover, CGFloat bottom) {
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    if (!hero) {
        hero = [[SGRAlbumHero alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kHeroKey, hero, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hero.superview != header) [header insertSubview:hero atIndex:0];
    else if (header.subviews.firstObject != hero) [header sendSubviewToBack:hero];

    CGFloat height = [objc_getAssociatedObject(hero, &kHeroHeightKey) doubleValue];
    if (bottom > height + 0.5) {
        height = round(bottom);
        objc_setAssociatedObject(hero, &kHeroHeightKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign album: hero %.0fpt across the top of the header", height);
    }
    if (height < kMinHero) return;
    setFrame(hero, CGRectMake(0, 0, header.bounds.size.width, height));
    hero.fieldColor = SGRAlbumFieldColor(header);

    [hero followCover:coverImageIn(cover)];
    conceal(cover);
}

#pragma mark - what the header shows

static NSString *trimmed(NSString *text) {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : nil;
}

// The first label under `root` with more than a letter in it: the facepile's initials are labels of their own.
static NSString *firstText(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (found || ![v isKindOfClass:UILabel.class]) return;
        NSString *text = trimmed(((UILabel *)v).text);
        if (text.length > 1) found = text;
    });
    return found;
}

static NSString *metadataText(UIView *metadata) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(metadata, ^(UIView *v) {
        if ([v isKindOfClass:UILabel.class] && trimmed(((UILabel *)v).text) && v.window) [labels addObject:(UILabel *)v];
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGFloat ax = [a convertPoint:CGPointZero toView:metadata].x, bx = [b convertPoint:CGPointZero toView:metadata].x;
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UILabel *label in labels) [parts addObject:trimmed(label.text)];
    return parts.count ? [parts componentsJoinedByString:@" "] : nil;
}

static void applyHeader(UIView *header, UIView *page);

// The Kit's view over the whole header, its content on the header's bottom edge; Spotify's own column goes.
static SGRHeaderInfo *applyInfo(UIView *header, UIView *page) {
    SGRHeaderInfo *info = objc_getAssociatedObject(header, &kInfoKey);
    if (!info) {
        info = [[SGRHeaderInfo alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &kInfoKey, info, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (info.superview != header) [header addSubview:info];
    else if (header.subviews.lastObject != info) [header bringSubviewToFront:info];
    SGRAlbumHero *hero = objc_getAssociatedObject(header, &kHeroKey);
    for (UIView *sub in header.subviews) {
        if (sub != info && sub != hero) blank(sub);
    }
    setFrame(info, header.bounds);

    UIView *title = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey);
    UIView *parent = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ParentRow", &kParentKey);
    UIView *metadata = SGRFindByIdentifier(header, @"Components.UI.MetadataRow", &kMetaKey);
    NSString *name = firstText(title), *length = metadataText(metadata);
    NSString *artist = firstText(parent) ?: trimmed(parent.accessibilityLabel);
    [info showTitle:name creator:artist length:length about:nil];
    [(SGRAlbumHero *)objc_getAssociatedObject(header, &kHeroKey) findMotionOf:name by:artist];
    NSInteger tries = [objc_getAssociatedObject(header, &kRetryKey) integerValue];
    if (!length && metadata && tries < 12) {
        objc_setAssociatedObject(header, &kRetryKey, @(tries + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHeader = header, *weakPage = page;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
        });
    }

    [info showCreatorLink:parent];

    // More, pinned over the page rather than left in the header, which is blanked and scrolls away.
    SGRPinnedMore(page, &kPinnedMoreKey, SGRFindByIdentifier(header, @"Components.UI.ContextMenuButton*", &kMoreKey));

    UIView *play = floatingIn(page, @"header-play-button", &kPlayKey);
    UIView *shuffle = floatingIn(page, @"Components.UI.ShuffleButton", &kShuffleKey);
    UIView *add = SGRFindByIdentifier(header, @"Components.UI.AddToButton", &kAddKey);
    UIView *download = SGRFindByIdentifier(header, @"DownloadButton.Granular*", &kDownloadKey);
    [info showAlbumShuffle:shuffle play:play download:download add:add playColor:SGRAlbumFieldColor(header)];
    // Only what the two floating buttons draw goes: a concealed layer still sends the actions the row fires.
    if (play) conceal(wrapperFor(play, page));
    if (shuffle) conceal(wrapperFor(shuffle, page));
    // The kind and the date are waited for too: arriving late they pushed the title up by a line.
    if (name && play && length) SGRRevealMark(page, SGRRevealHeader);

    UIView *inRow = add ?: download ?: SGRFindByIdentifier(header, @"Components.UI.WatchFeedEntityExplorerButton", &kExploreKey);
    __weak UIView *weakHeader = header, *weakPage = page;
    watch(rowOf(inRow, header), &kRowWatchedKey, ^(UIView *view) {
        if (weakHeader && weakPage) applyHeader(weakHeader, weakPage);
    });

    static BOOL logged;
    if (!logged && header.window && title) {
        logged = YES;
        SGLog(@"redesign album: own block \"%@\" by %@, \"%@\"; shuffle %@, play %@, %@", firstText(title),
              firstText(parent) ?: @"nobody", metadataText(metadata) ?: @"no metadata", shuffle ? @"found" : @"missing",
              play ? @"found" : @"missing", add ? @"add" : (download ? @"download" : @"nothing on the right"));
    }
    return info;
}

#pragma mark - the header's pass

static void maskOut(UIView *view) {
    if (!view || view.layer.mask) return;
    view.layer.mask = [CALayer layer];
    view.accessibilityElementsHidden = YES;
}

static void applyWash(UIView *page) {
    for (UIView *sub in page.subviews) {
        NSString *name = NSStringFromClass(sub.class);
        if (![name containsString:@"HeaderView"] && ![name containsString:@"HeaderNavigationBar"]) continue;
        for (UIView *v in sub.subviews) {
            if ([NSStringFromClass(v.class) containsString:@"GradientView"]) maskOut(v);
        }
    }
}

static void applyHeader(UIView *header, UIView *page) {
    if (!SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.TitleRow", &kTitleKey)) return;
    // An album's page: its curtain waits for all of it (AlbumField.x put it up).
    SGRRevealHold(page, SGRRevealPage);
    applyWash(page);
    SGRHeaderInfo *info = applyInfo(header, page);

    CGFloat rest = MAX([objc_getAssociatedObject(header, &kHeaderHeightKey) doubleValue], header.bounds.size.height);
    objc_setAssociatedObject(header, &kHeaderHeightKey, @(rest), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat bottom = rest - SGRHeaderInfoBottom - [info contentHeightForWidth:header.bounds.size.width] + SGRHeaderInfoTitleRise;
    UIView *cover = SGRFindByIdentifier(header, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt", &kCoverKey);
    if (cover) applyHero(header, cover, bottom);
}

static void applyPage(UIView *page) {
    UIView *header = SGRFindByIdentifier(page, @"CreativeWorkPlatform.Components.UI.CreativeWorkHeader", &kHeaderKey);
    if (!header) return;
    applyHeader(header, page);
    watch(header, &kHeaderWatchedKey, ^(UIView *view) {
        UIView *owner = SGRAlbumPageOf(view);
        if (owner) applyHeader(view, owner);
    });
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    applyPage((UIView *)self);
}
%end

%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if (button.layer.hidden || ![button.accessibilityIdentifier isEqualToString:@"header-play-button"]) return;
    UIView *page = SGRAlbumPageOf(button);
    if (!page) return;
    conceal(wrapperFor(button, page));
    applyPage(page);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView",
    ]);
}
