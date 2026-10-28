#import "Core/SGCore.h"
#import "SGRActionRow.h"
#import "SGRGlass.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"
#import "SGRAccent.h"
#import "SGRDownload.h"
#import "SGRReveal.h"

static const CGFloat kGlyphSide = 44, kCapsuleLead = 4, kCapsuleTrail = 20;
// The mirrored glyph, the size Spotify draws one inside a 48pt round button.
static const CGFloat kMirrorGlyph = 24;

static char kCapsuleGlassKey, kMirrorGlassKey;

static UIImageView *glyphIn(UIView *button, CGFloat side) {
    __block UIImageView *glyph = nil;
    SGForEachView(button, ^(UIView *v) {
        if (glyph || ![v isKindOfClass:UIImageView.class] || !((UIImageView *)v).image) return;
        if (side > 0 && (fabs(v.bounds.size.width - side) > 2 || fabs(v.bounds.size.height - side) > 2)) return;
        for (UIView *up = v; up && up != button; up = up.superview) {
            if (up.hidden || up.alpha <= 0.01) return;
        }
        glyph = (UIImageView *)v;
    });
    return glyph;
}

static NSString *wordIn(UIView *button) {
    __block NSString *word = nil;
    SGForEachView(button, ^(UIView *v) {
        if (!word && v.accessibilityLabel.length) word = v.accessibilityLabel;
    });
    return word;
}

#pragma mark - the Play capsule

@implementation SGRPlayCapsule {
    UIImageView *_glyph;
    UILabel *_title;
    __weak UIImageView *_watchedGlyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];

    _title = [UILabel new];
    _title.userInteractionEnabled = NO;
    [self addSubview:_title];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(sgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addTarget:self action:@selector(sgr_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (CGFloat)sgr_width {
    [_title sizeToFit];
    return kCapsuleLead + kGlyphSide + ceil(_title.bounds.size.width) + kCapsuleTrail;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (self.fillColor) {
        if (![self.backgroundColor isEqual:self.fillColor]) self.backgroundColor = self.fillColor;
        self.layer.cornerRadius = bounds.size.height / 2;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    } else {
        SGRGlassCapsuleInside(self, &kCapsuleGlassKey, bounds.size, YES);
    }
    // Given more room than the word asks for, the glyph and the word stay together in the middle.
    CGFloat lead = kCapsuleLead + MAX(0, round((bounds.size.width - [self sgr_width]) / 2));
    _glyph.frame = CGRectMake(lead, round((bounds.size.height - kGlyphSide) / 2), kGlyphSide, kGlyphSide);
    CGSize image = _glyph.image.size;
    UIViewContentMode mode = image.width <= kGlyphSide && image.height <= kGlyphSide ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit;
    if (_glyph.contentMode != mode) _glyph.contentMode = mode;
    [_title sizeToFit];
    CGSize text = _title.bounds.size;
    _title.frame = CGRectMake(CGRectGetMaxX(_glyph.frame), round((bounds.size.height - text.height) / 2),
                              MAX(0, bounds.size.width - kCapsuleTrail - CGRectGetMaxX(_glyph.frame)), text.height);
}

- (void)feedFrom:(UIView *)source {
    if (!source) return;
    _source = source;

    NSString *word = wordIn(source);
    CGSize size = source.bounds.size;
    UIImageView *glyph = glyphIn(source, MIN(size.width, size.height));

    UIFont *font = SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    if (![_title.font isEqual:font]) _title.font = font;
    UIColor *content = self.contentColor ?: SGRAccent();
    if (![_title.textColor isEqual:content]) _title.textColor = content;
    if (word && ![_title.text isEqualToString:word]) {
        _title.text = word;
        self.accessibilityLabel = word;
        [self setNeedsLayout];
    }
    if (![_glyph.tintColor isEqual:content]) _glyph.tintColor = content;

    if (glyph.image && _glyph.image != glyph.image) {
        _glyph.image = [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            SGLog(@"redesign kit: play glyph %@ from %@, word \"%@\"", NSStringFromCGSize(glyph.image.size),
                  NSStringFromClass(glyph.class), word);
        });
    }
    if (glyph && glyph != _watchedGlyph) {
        _watchedGlyph = glyph;
        __weak SGRPlayCapsule *weakSelf = self;
        __weak UIView *weakSource = source;
        SGRObserveImage(glyph, ^(UIImageView *view) {
            if (weakSelf && weakSource) [weakSelf feedFrom:weakSource];
        });
    }
}

- (void)sgr_down {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformMakeScale(0.94, 0.94); }, nil);
}

- (void)sgr_up {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformIdentity; }, nil);
}

- (void)sgr_tap {
    SGRActivate(self.source);
}

@end

#pragma mark - a button standing in for Spotify's

static BOOL indicatorOn(UIView *button, BOOL *found) {
    __block UIView *dot = nil;
    SGForEachView(button, ^(UIView *v) {
        if (dot || v == button || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UILabel.class]) return;
        CGSize size = v.bounds.size;
        if (size.width < 2 || size.width > 8 || size.height < 2 || size.height > 8) return;
        CGColorRef paint = v.layer.backgroundColor;
        if (paint && CGColorGetAlpha(paint) > 0.5) dot = v;
    });
    if (found) *found = dot != nil;
    for (UIView *up = dot; up && up != button; up = up.superview) {
        if (up.hidden || up.alpha <= 0.01) return NO;
    }
    return dot != nil;
}

@implementation SGRMirrorButton {
    UIImageView *_glyph;
    __weak UIImageView *_watchedGlyph;
    UIImage *_takenGlyph;
    // Standing in for Spotify's download button: its state drawn, and read again while on screen.
    SGRDownloadGlyph *_download;
    NSTimer *_downloadTimer;
    // A two-state glyph drawn for Spotify (add-to, readState): 1 on, 0 off, -1 none drawn.
    NSInteger _stateShown;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeScaleAspectFit;
    _glyph.userInteractionEnabled = NO;
    [self addSubview:_glyph];
    _stateShown = -1;

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(sgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self addTarget:self action:@selector(sgr_tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    // Until its state is known the button draws nothing: a guess would flash the wrong glyph first.
    if (self.readState && _stateShown < 0) {
        ((UIView *)objc_getAssociatedObject(self, &kMirrorGlassKey)).hidden = YES;
        return;
    }
    SGRGlassInside(self, &kMirrorGlassKey, SGRGlassCircleSize);
    _glyph.frame = CGRectMake(round((bounds.size.width - kMirrorGlyph) / 2), round((bounds.size.height - kMirrorGlyph) / 2),
                              kMirrorGlyph, kMirrorGlyph);
    _download.frame = _glyph.frame;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!_download && _stateShown < 0 && !self.readState) return;
    if (self.window && self.source) [self feedFrom:self.source];
    else [self sgr_followDownload:0];
}

- (void)dealloc {
    [_downloadTimer invalidate];
}

// Shows Spotify's download state; YES when `source` is a download button.
- (BOOL)sgr_feedDownloadFrom:(UIView *)source {
    SGRDownloadState state;
    CGFloat progress;
    if (!SGRReadDownload(source, &state, &progress)) {
        if (_download && !_download.hidden) {
            _download.hidden = YES;
            _glyph.hidden = NO;
            [self sgr_followDownload:0];
        }
        return NO;
    }
    if (!_download) {
        _download = [[SGRDownloadGlyph alloc] initWithFrame:_glyph.frame];
        [self addSubview:_download];
    }
    _download.hidden = NO;
    _glyph.hidden = YES;
    [_download showState:state progress:progress animated:YES];

    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    NSString *value = state == SGRDownloadDownloading && progress >= 0
        ? [NSNumberFormatter localizedStringFromNumber:@(progress) numberStyle:NSNumberFormatterPercentStyle] : nil;
    if (![self.accessibilityValue ?: @"" isEqualToString:value ?: @""]) self.accessibilityValue = value;

    BOOL running = state == SGRDownloadWaiting || state == SGRDownloadDownloading;
    [self sgr_followDownload:self.window ? (running ? 0.5 : 2) : 0];
    return YES;
}

// Draws `offSymbol`, or `onSymbol` in the accent colour, switching between them in place.
- (void)sgr_showOn:(BOOL)on off:(NSString *)offSymbol on:(NSString *)onSymbol source:(UIView *)source {
    if (_stateShown != on) {
        UIImage *image = [UIImage systemImageNamed:on ? onSymbol : offSymbol];
        BOOL animated = _stateShown >= 0 && self.window && !SGRReduceMotion();
        BOOL first = _stateShown < 0;
        _stateShown = on;
        _takenGlyph = nil;
        _glyph.hidden = NO;
        if (@available(iOS 17.0, *)) {
            if (animated) [_glyph setSymbolImage:image withContentTransition:[NSSymbolReplaceContentTransition replaceDownUpTransition]];
            else _glyph.image = image;
        } else {
            _glyph.image = image;
        }
        // On is saved or followed, in the accent colour, as downloaded is.
        _glyph.tintColor = on ? SGRAccent() : SGRPrimary();
        if (first) [self setNeedsLayout];
    }
    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    // Nothing is laid out when it changes from elsewhere (the ⋯ sheet), so it is read again as download is.
    [self sgr_followDownload:self.window ? 2 : 0];
}

// Shows whether Spotify's add-to button has its album or playlist saved; YES when `source` is one.
- (BOOL)sgr_feedAddToFrom:(UIView *)source {
    BOOL added;
    if (!SGRReadAddTo(source, &added)) {
        _stateShown = -1;
        return NO;
    }
    [self sgr_showOn:added off:@"plus" on:@"checkmark" source:source];
    return YES;
}

// Reads the state again every `interval` seconds; 0 stops.
- (void)sgr_followDownload:(NSTimeInterval)interval {
    if (interval <= 0) {
        [_downloadTimer invalidate];
        _downloadTimer = nil;
        return;
    }
    if (_downloadTimer.valid && fabs(_downloadTimer.timeInterval - interval) < 0.01) return;
    [_downloadTimer invalidate];
    __weak SGRMirrorButton *weakSelf = self;
    _downloadTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer *timer) {
        SGRMirrorButton *button = weakSelf;
        if (!button || !button.window || !button.source) {
            [timer invalidate];
            return;
        }
        [button feedFrom:button.source];
    }];
    _downloadTimer.tolerance = interval * 0.2;
}

- (void)feedFrom:(UIView *)source {
    if (!source) return;
    _source = source;

    if (self.readState) {
        BOOL on = NO;
        if (self.readState(&on)) [self sgr_showOn:on off:self.stateOffSymbol on:self.stateOnSymbol source:source];
        else [self sgr_followDownload:self.window ? 2 : 0];
        BOOL known = _stateShown >= 0;
        if (_glyph.hidden == known) _glyph.hidden = !known;
        if (self.userInteractionEnabled != known) {
            self.userInteractionEnabled = known;
            self.isAccessibilityElement = known;
        }
        return;
    }

    if ([self sgr_feedDownloadFrom:source]) return;
    if ([self sgr_feedAddToFrom:source]) return;

    UIImageView *glyph = glyphIn(source, 0);
    NSString *word = source.accessibilityLabel ?: wordIn(source);
    if (word && ![self.accessibilityLabel isEqualToString:word]) self.accessibilityLabel = word;
    BOOL hasDot = NO;
    BOOL on = self.onGlyphColor && indicatorOn(source, &hasDot);
    UIColor *ownColor = !self.onGlyphColor ? self.glyphColor
                      : hasDot ? (on ? self.onGlyphColor : self.glyphColor ?: SGRPrimary()) : nil;
    if (glyph.image && (_takenGlyph != glyph.image || (ownColor != nil) != (_glyph.image.renderingMode == UIImageRenderingModeAlwaysTemplate))) {
        _takenGlyph = glyph.image;
        _glyph.image = ownColor ? [glyph.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : glyph.image;
    }
    if (!glyph && self.fallbackGlyph && _glyph.image != self.fallbackGlyph) {
        _takenGlyph = nil;
        _glyph.image = self.fallbackGlyph;
    }
    UIColor *tint = ownColor ?: (glyph ? glyph.tintColor : SGRPrimary());
    if (tint && ![_glyph.tintColor isEqual:tint]) {
        // Turning on or off is a moment of its own: the colour fades across rather than jumping.
        BOOL fade = self.window && _glyph.tintColor && hasDot;
        if (fade) {
            [UIView transitionWithView:_glyph duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ self->_glyph.tintColor = tint; } completion:nil];
        } else {
            _glyph.tintColor = tint;
        }
    }

    // As the capsule does: watched per glyph view, so a reused one reports where it is now.
    if (glyph && glyph != _watchedGlyph) {
        _watchedGlyph = glyph;
        __weak SGRMirrorButton *weakSelf = self;
        __weak UIView *weakSource = source;
        SGRObserveImage(glyph, ^(UIImageView *view) {
            if (weakSelf && weakSource) [weakSelf feedFrom:weakSource];
        });
    }
}

- (void)sgr_down {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformMakeScale(0.92, 0.92); }, nil);
}

- (void)sgr_up {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformIdentity; }, nil);
}

- (void)sgr_tap {
    SGRActivate(self.source);
    __weak SGRMirrorButton *weakSelf = self;
    for (NSNumber *delay in @[@0.3, @1.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRMirrorButton *button = weakSelf;
            if (button.source) [button feedFrom:button.source];
        });
    }
}

@end

#pragma mark - the page's pinned ⋯

static const CGFloat kCornerSide = 16;

static __weak UIView *sg_morePage;
static NSTimeInterval sg_moreTappedAt;
static char kRecorderKey;

UIView *SGRPinnedMoreRecentPage(void) {
    if (!sg_morePage || CACurrentMediaTime() - sg_moreTappedAt > SGRPinnedMoreWindow) return nil;
    return sg_morePage;
}

@interface SGRPinnedMoreRecorder : NSObject
@end
@implementation SGRPinnedMoreRecorder
- (void)sgr_moreTapped:(SGRMirrorButton *)button {
    sg_morePage = button.superview;
    sg_moreTappedAt = CACurrentMediaTime();
}
@end

SGRMirrorButton *SGRPinnedMore(UIView *page, const void *key, UIView *source) {
    if (!page) return nil;
    SGRMirrorButton *button = objc_getAssociatedObject(page, key);
    if (!button) {
        button = [[SGRMirrorButton alloc] initWithFrame:CGRectZero];
        button.fallbackGlyph = [UIImage systemImageNamed:@"ellipsis"];
        button.glyphColor = SGRPrimary();
        // Held by the button, which is held by the page, so the recorder lives exactly as long as both.
        SGRPinnedMoreRecorder *recorder = [SGRPinnedMoreRecorder new];
        objc_setAssociatedObject(button, &kRecorderKey, recorder, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:recorder action:@selector(sgr_moreTapped:) forControlEvents:UIControlEventTouchDown];
        objc_setAssociatedObject(page, key, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (button.superview != page) [page addSubview:button];
    SGRRevealBringToFront(page, button);
    if (source) [button feedFrom:source];
    if (button.hidden != (source == nil)) button.hidden = source == nil;

    UIWindow *window = page.window;
    CGFloat side = SGRGlassCircleSize;
    CGRect frame;
    if (window) {
        CGRect inWindow = CGRectMake(window.bounds.size.width - kCornerSide - side, window.safeAreaInsets.top, side, side);
        frame = [page convertRect:inWindow fromView:nil];
    } else {
        frame = CGRectMake(page.bounds.size.width - kCornerSide - side, page.safeAreaInsets.top, side, side);
    }
    if (!CGRectIsEmpty(frame) && !CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    return button;
}
