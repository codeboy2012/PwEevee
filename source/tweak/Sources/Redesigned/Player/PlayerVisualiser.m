// Player redesign: the Visualizer background, a calm spectrum of what is playing behind the player, in the
// cover's colors, over the Fluid field held still (PlayerField.x keeps the field Fluid for this choice, as for
// Animated, so the ⋯ menu moves between all six background styles without a restart).
//
// The sound is Spotify's output as it plays, read on the render thread through the audio effects' notify
// (SGAudioSetOutputReader, Shared/AudioEffects/AudioEffects.h) into SGRSpectrum.m's bands. Here, on the main
// thread, a display link reads the bands, brings them to a share of the song's own loudness (the loudest band of
// the last few seconds at the top, so a quiet track moves as much as a loud one), eases each band up quickly
// and down slowly, and draws two soft hills across the foot of the screen, mirrored about its middle, the bass
// in the middle and the treble at either edge: a slow one behind, a quicker one in front. Each is a gradient of
// the cover's colors (SGRPalette's flow colors, kept dark enough that white text on them stays over 5.5:1)
// masked by a shape layer, so the render server does the drawing and the app only hands it two paths a frame.
//
// It moves only while it is in a window, Spotify is in front, the player is not opening or closing, Low Power
// Mode is off and the song plays; a pause lets the hills settle and the link stops, and nothing is read from
// the sound while it is stopped. At most 60 frames a second, 30 while the lyrics, which have a link of their own,
// are open and the hills are blurred behind them, and with Reduce Motion 15, with every band easing over
// seconds. While the player opens or closes the link is down, and comes back only once the animation is over:
// a link at 60 would hold the transition's 120 Hz down with it.
//
// ponytail: the hills follow what the output is handed, which a Bluetooth headset plays a fifth of a second or
// so later. Music Haptics schedules for the output latency; do the same here if the beat looks early on AirPods.
//
// Threading: main thread only, but for the reader, which runs on the render thread.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/AudioEffects/AudioEffects.h"
#import "Shared/Player/PlayerEvents.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "SGRSpectrum.h"

enum { kBands = SGRSpectrumBands, kPoints = 2 * kBands - 1 };
// The loudness a band is drawn against: the loudest band of late at the top, kRange dB under it at the floor,
// the top falling kPeakFall dB a second after a loud passage and never under kPeakFloor, so silence stays flat.
static const float kRange = 40, kPeakFall = 4, kPeakFloor = -60;
// A rise toward the treble, in dB a band (three bands an octave), since music has less there: a tuning knob.
static const float kTilt = 0.6f;
// How quickly a band eases toward its level, up and down, in seconds; the hill behind is slower. With Reduce
// Motion both ease over kStillEase.
static const double kFrontUp = 0.08, kFrontDown = 0.4, kBackUp = 0.3, kBackDown = 0.9, kStillEase = 3;
// No new bands for this long reads as silence (a pause, a stall, a tap that never ran).
static const double kStale = 0.3;
// The hills' height at their tallest and at rest, as shares of the screen's height; the one behind is taller.
static const CGFloat kFrontHeight = 0.24, kBackHeight = 0.3, kRestHeight = 0.012;
// Below this every band has settled (under 2 pt at the top of the front hill), and a paused song's link can stop.
static const float kSettled = 0.02f;
// Each band shares this much with either neighbor, twice over, so one loud band is a hill and not a spike.
static const float kSpread = 0.25f;
static const NSTimeInterval kTransitionSlack = 0.05;

static NSUInteger sg_readers;

// The reader on while any view is moving, so nothing is analyzed while none is.
static void needReader(BOOL need) {
    if (need) {
        if (sg_readers++ == 0) {
            SGRSpectrumPrepare();
            /* no audio reader */
        }
    } else if (sg_readers && --sg_readers == 0) {
        /* no audio reader */
    }
}

static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"path": off, @"colors": off};
    });
    return none;
}

@interface SGRVisualiserView : UIView <SGPlayerStateObserver>
// Where the hills stand, in points from the top: the screen's foot in the player. 0 is the bounds' foot.
@property (nonatomic) CGFloat baseline;
// The height the hills are a share of; 0 is the bounds' height.
@property (nonatomic) CGFloat screenHeight;
@property (nonatomic, readonly) BOOL blurred;
- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated;
- (void)appear:(BOOL)animated;
- (void)disappear:(void (^)(void))done;
@end

@implementation SGRVisualiserView {
    UIView *_content;   // the hills, faded in and out as one
    CAGradientLayer *_backFill, *_frontFill;
    CAShapeLayer *_backShape, *_frontShape;
    UIVisualEffectView *_lyricsBlur;
    UIViewPropertyAnimator *_lyricsBlurAnimator;
    BOOL _lyricsRequested;
    CADisplayLink *_link;
    BOOL _reading, _idle;
    float _front[kBands], _back[kBands], _peak;
    uint64_t _generation;
    CFTimeInterval _fresh, _last;
    NSUInteger _palette;
}

// As PlayerMotion.x: what fades is the effect view's effect, never its alpha or an ancestor's.
static UIBlurEffect *blurEffect(void) {
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
}

static UIViewPropertyAnimator *setBlurIntensity(UIVisualEffectView *view, UIViewPropertyAnimator *animator, CGFloat intensity) {
    intensity = MIN(1, MAX(0, intensity));
    if (animator && animator.state != UIViewAnimatingStateInactive) [animator stopAnimation:YES];
    view.effect = nil;
    if (intensity <= 0) return nil;

    __weak UIVisualEffectView *weakView = view;
    UIViewPropertyAnimator *fractional = [[UIViewPropertyAnimator alloc] initWithDuration:1
                                                                                    curve:UIViewAnimationCurveLinear
                                                                               animations:^{
        weakView.effect = blurEffect();
    }];
    [fractional startAnimation];
    [fractional pauseAnimation];
    fractional.fractionComplete = intensity;
    return fractional;
}

static CAGradientLayer *fill(CAShapeLayer *shape) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.actions = noActions();
    layer.startPoint = CGPointMake(0, 0.5);
    layer.endPoint = CGPointMake(1, 0.5);
    shape.actions = noActions();
    layer.mask = shape;
    return layer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _peak = kPeakFloor;
    _content = [[UIView alloc] initWithFrame:frame];
    _backShape = [CAShapeLayer layer];
    _backFill = fill(_backShape);
    _backFill.opacity = 0.55f;
    [_content.layer addSublayer:_backFill];
    _frontShape = [CAShapeLayer layer];
    _frontFill = fill(_frontShape);
    [_content.layer addSublayer:_frontFill];
    [self addSubview:_content];
    _lyricsBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
    _lyricsBlur.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_lyricsBlur];
    [self applyColors:@[UIColor.darkGrayColor, UIColor.darkGrayColor, UIColor.darkGrayColor, UIColor.darkGrayColor, UIColor.darkGrayColor]];

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    [center addObserver:self selector:@selector(artworkChanged) name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    [center addObserver:self selector:@selector(updateBlurOpacity) name:SGRPlayerBlurOpacityDidChangeNotification object:nil];
    [self updateBlurOpacity];
    SGRObservePlayerTransition(self, ^(id owner) { [owner updateMotion]; }, ^(id owner) { [owner updateMotion]; });
    SGAddPlayerStateObserver(self);
    [self artworkChanged];
    [self draw];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_link invalidate];
}

- (void)updateBlurOpacity {
    CGFloat opacity = MIN(100, MAX(0, SGInt(SGRKeyPlayerVisualiserBlurOpacity, 100))) / 100.0;
    _lyricsBlurAnimator = setBlurIntensity(_lyricsBlur, _lyricsBlurAnimator, _lyricsRequested ? opacity : 0);
    if (_reading) needReader(NO);
}

#pragma mark - color

// Bottom left, the whole cover and bottom right in front, the top two behind, so the hills read as the cover's
// lower half under its upper.
- (void)applyColors:(NSArray<UIColor *> *)colors {
    if (colors.count < 5) return;
    _frontFill.colors = @[(id)colors[2].CGColor, (id)colors[4].CGColor, (id)colors[3].CGColor];
    _backFill.colors = @[(id)colors[0].CGColor, (id)colors[1].CGColor];
}

- (void)artworkChanged {
    UIImage *image = SGRNowPlayingArtwork(NULL, NULL);
    if (!image) return;
    NSUInteger generation = ++_palette;
    SGRPaletteRequest request = {CGSizeZero, NO, YES, YES, NO};
    __weak SGRVisualiserView *weakSelf = self;
    [SGRPalette paletteForImage:image request:request completion:^(SGRPalette *palette) {
        SGRVisualiserView *view = weakSelf;
        if (!view || !palette.flowColors || generation != view->_palette) return;
        if (!view.window) {
            [view applyColors:palette.flowColors];
            return;
        }
        // The colors cross over as the field's do.
        [CATransaction begin];
        [CATransaction setAnimationDuration:SGRCrossfade];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        for (CAGradientLayer *layer in @[view->_frontFill, view->_backFill]) {
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"colors"];
            fade.fromValue = (layer.presentationLayer ?: layer).colors;
            [layer addAnimation:fade forKey:@"colors"];
        }
        [view applyColors:palette.flowColors];
        [CATransaction commit];
    }];
}

#pragma mark - showing

- (void)setBaseline:(CGFloat)baseline {
    if (baseline == _baseline) return;
    _baseline = baseline;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    _content.frame = bounds;
    _lyricsBlur.frame = bounds;
    _backFill.frame = bounds;
    _frontFill.frame = bounds;
    _backShape.frame = bounds;
    _frontShape.frame = bounds;
    [self draw];
}

- (void)appear:(BOOL)animated {
    _content.alpha = 0;
    if (animated) SGRAnimate(SGRMotionFade, ^{ self->_content.alpha = 1; }, nil);
    else _content.alpha = 1;
}

- (void)disappear:(void (^)(void))done {
    SGRAnimate(SGRMotionFade, ^{
        self->_content.alpha = 0;
        self->_lyricsRequested = NO;
        self->_lyricsBlurAnimator = setBlurIntensity(self->_lyricsBlur, self->_lyricsBlurAnimator, 0);
    }, ^(BOOL finished) { done(); });
}

- (BOOL)blurred {
    return _lyricsRequested;
}

- (void)setBlurred:(BOOL)blurred animated:(BOOL)animated {
    _lyricsRequested = blurred;
    CGFloat opacity = MIN(100, MAX(0, SGInt(SGRKeyPlayerVisualiserBlurOpacity, 100))) / 100.0;
    void (^apply)(void) = ^{
        self->_lyricsBlurAnimator = setBlurIntensity(self->_lyricsBlur, self->_lyricsBlurAnimator, blurred ? opacity : 0);
    };
    if (animated) SGRAnimate(SGRMotionFade, apply, nil);
    else apply();
    [self updateMotion];
}

#pragma mark - moving

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self updateMotion];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
}

// The power state is reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

- (BOOL)settled {
    for (int band = 0; band < kBands; band++) if (_front[band] > kSettled || _back[band] > kSettled) return NO;
    return YES;
}

// Moving while it may and there is something to show: the song playing, or the hills still settling after it
// stopped. While the player animates, it comes back once the animation is expected to be over.
- (void)updateMotion {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateMotion) object:nil];
    BOOL front = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL may = self.window && front && !NSProcessInfo.processInfo.lowPowerModeEnabled;
    NSTimeInterval wait = SGPlayerTransitionEnds() - CACurrentMediaTime();
    if (may && (wait > 0 || SGRPlayerIsTransitioning())) {
        may = NO;
        // Without an expected end, the transition's ended notification brings it back.
        if (wait > 0) [self performSelector:@selector(updateMotion) withObject:nil afterDelay:wait + kTransitionSlack inModes:@[NSRunLoopCommonModes]];
    }
    BOOL playing = !SGPlayerState().isPaused;
    [self setMoving:may && (playing || !self.settled)];
    [self setReading:may && playing];
}

- (void)setReading:(BOOL)reading {
    if (reading == _reading) return;
    _reading = reading;
    needReader(reading);
}

- (void)setMoving:(BOOL)moving {
    if (moving) {
        if (!_link) {
            _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
            [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            _last = 0;
        }
        // Calmer behind the lyrics, whose own link runs at the display's rate, and calmest with Reduce Motion.
        // While a playing song sends nothing (a stall, or no tap at all), a few frames a second watch for it.
        float most = _idle ? 4 : SGRReduceMotion() ? 15 : _lyricsBlur.effect ? 30 : 60;
        _link.preferredFrameRateRange = CAFrameRateRangeMake(most / 2, most, most);
    } else if (_link) {
        [_link invalidate];
        _link = nil;
    }
}

static float ease(float value, float target, double dt, double up, double down) {
    double tau = target > value ? up : down;
    return value + (target - value) * (float)(1 - exp(-dt / tau));
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    double dt = _last ? MIN(now - _last, 0.1) : link.duration;
    _last = now;
    float levels[kBands];
    uint64_t generation = SGRSpectrumRead(levels);
    if (generation != _generation) {
        _generation = generation;
        _fresh = now;
    }
    BOOL silent = !_reading || now - _fresh > kStale;
    float loudest = kPeakFloor;
    for (int band = 0; band < kBands; band++) {
        levels[band] += kTilt * band;
        loudest = fmaxf(loudest, levels[band]);
    }
    if (!silent) _peak = fmaxf(fmaxf(loudest, _peak - kPeakFall * (float)dt), kPeakFloor);
    BOOL still = SGRReduceMotion();
    float targets[kBands];
    for (int band = 0; band < kBands; band++) targets[band] = silent ? 0 : fminf(1, fmaxf(0, (levels[band] - (_peak - kRange)) / kRange));
    for (int pass = 0; pass < 2; pass++) {
        float before = targets[0];
        for (int band = 0; band < kBands; band++) {
            float here = targets[band], next = targets[MIN(band + 1, kBands - 1)];
            targets[band] = kSpread * before + (1 - 2 * kSpread) * here + kSpread * next;
            before = here;
        }
    }
    for (int band = 0; band < kBands; band++) {
        float target = targets[band];
        _front[band] = ease(_front[band], target, dt, still ? kStillEase : kFrontUp, still ? kStillEase : kFrontDown);
        _back[band] = ease(_back[band], target, dt, still ? kStillEase : kBackUp, still ? kStillEase : kBackDown);
    }
    [self draw];
    BOOL idle = silent && self.settled;
    if (idle && !_idle) {
        // The last step down to rest, too small to see, so a settled hill is drawn exactly at rest.
        memset(_front, 0, sizeof _front);
        memset(_back, 0, sizeof _back);
        [self draw];
    }
    if (idle != _idle) {
        _idle = idle;
        [self updateMotion];
    }
}

#pragma mark - drawing

// A smooth line through the points (Catmull-Rom as cubic Béziers), closed down to the foot of the bounds.
static CGPathRef hillPath(const CGPoint *points, int count, CGFloat foot) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, points[0].x, foot);
    CGPathAddLineToPoint(path, NULL, points[0].x, points[0].y);
    for (int i = 0; i < count - 1; i++) {
        CGPoint before = points[MAX(i - 1, 0)], from = points[i], to = points[i + 1], after = points[MIN(i + 2, count - 1)];
        CGPathAddCurveToPoint(path, NULL, from.x + (to.x - before.x) / 6, from.y + (to.y - before.y) / 6,
                              to.x - (after.x - from.x) / 6, to.y - (after.y - from.y) / 6, to.x, to.y);
    }
    CGPathAddLineToPoint(path, NULL, points[count - 1].x, foot);
    CGPathCloseSubpath(path);
    return path;
}

// The bass in the middle, each band out to either side, the treble at the edges; a band's height eased in so
// quiet bands lie low and only the strong ones stand up.
static void shape(CAShapeLayer *layer, const float *bands, CGFloat width, CGFloat baseline, CGFloat foot, CGFloat tallest, CGFloat rest) {
    CGPoint points[kPoints];
    for (int i = 0; i < kPoints; i++) {
        float value = bands[abs(i - (kBands - 1))];
        CGFloat height = rest + (tallest - rest) * powf(value, 1.2f);
        points[i] = CGPointMake(width * i / (kPoints - 1), baseline - height);
    }
    CGPathRef path = hillPath(points, kPoints, foot);
    layer.path = path;
    CGPathRelease(path);
}

- (void)draw {
    CGRect bounds = self.bounds;
    if (bounds.size.width <= 0) return;
    CGFloat baseline = _baseline > 0 ? _baseline : bounds.size.height;
    CGFloat screen = _screenHeight > 0 ? _screenHeight : bounds.size.height;
    CGFloat foot = MAX(baseline, bounds.size.height), rest = round(screen * kRestHeight);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    shape(_backShape, _back, bounds.size.width, baseline, foot, screen * kBackHeight, rest * 1.5);
    shape(_frontShape, _front, bounds.size.width, baseline, foot, screen * kFrontHeight, rest);
    [CATransaction commit];
}

@end

#pragma mark - in the player

static SGRVisualiserView *sg_view;

BOOL SGRPlayerVisualiserShowing(void) {
    SGRPlayerBackgroundKind background = SGRPlayerBackground();
    return background == SGRPlayerBackgroundVisualiser
        || (background == SGRPlayerBackgroundAnimated
            && SGRPlayerAnimatedFallback() == SGRPlayerBackgroundVisualiser);
}

// One preview view, reused: the Player page tears its old one down on every tap of the background control,
// and each of those teardowns races the display link and the palette read it had just started.
UIView *SGRPlayerVisualiserPreview(void) {
    static SGRVisualiserView *view;
    if (!view) view = [[SGRVisualiserView alloc] initWithFrame:CGRectZero];
    return view;
}

// The hills from the top of the field to the foot of its bleed, standing on the screen's foot.
static void layOut(SGRArtworkField *field) {
    if (sg_view.superview != field) [field addSubview:sg_view];
    else if (field.subviews.lastObject != sg_view) [field bringSubviewToFront:sg_view];
    CGSize size = field.bounds.size;
    CGFloat screen = field.window.bounds.size.height ?: size.height;
    CGRect frame = CGRectMake(0, 0, size.width, MAX(size.height, screen) + field.bleed.bottom);
    if (!CGRectEqualToRect(sg_view.frame, frame)) sg_view.frame = frame;
    sg_view.baseline = screen;
    sg_view.screenHeight = screen;
}

void SGRPlayerVisualiserUpdate(void) {
    SGRArtworkField *field = SGRPlayerField();
    // Not over an Animated artwork clip still playing: the Player page can change the choice under it, which the
    // player takes up when it next starts.
    BOOL wanted = SGRPlayerVisualiserShowing() && field && !SGRPlayerMotionShowing();
    if (!wanted) {
        SGRVisualiserView *old = sg_view;
        sg_view = nil;
        if (old.window) [old disappear:^{ [old removeFromSuperview]; }];
        else [old removeFromSuperview];
        return;
    }
    BOOL made = !sg_view;
    if (made) sg_view = [[SGRVisualiserView alloc] initWithFrame:CGRectZero];
    layOut(field);
    if (made) {
        [sg_view setBlurred:SGRPlayerLyricsOpen() animated:NO];
        [sg_view appear:field.window != nil];
        SGLog(@"redesign player: visualizer on the field");
    } else {
        BOOL open = SGRPlayerLyricsOpen();
        if (open != sg_view.blurred) [sg_view setBlurred:open animated:sg_view.window != nil];
    }
}
