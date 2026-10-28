// Rings of dots seen from above, like a drop on still water: a tap presses the middle and a crest runs out
// ring by ring, pushing each ring's dots out a few points and lighting them in the look's accent color as it
// passes, the Taptic Engine playing on the same frame. The stronger the feature's Strength, the higher the
// crest and the further it carries; at the lowest it dies out a few rings in. Music Haptics' taps, while it
// is on and the page shows, send out a low crest of their own that fades within the inner rings.
//
// Each ring is a CAReplicatorLayer copying one white dot and one accent dot around it, so a ring is
// animated by animating its two dots. The animations are additive keyframes that start and end at nothing,
// so a crest sent while another runs passes through it instead of cutting it off, and nothing runs between
// taps: no display link, no animation left over. With Reduce Motion nothing moves: every ring lights up at
// once and fades, and the music's taps send nothing.
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Haptics.h"
#import "SGVibrationsPreview.h"

static const NSInteger kRings = 9;
static const CGFloat kFirstRadius = 15, kRingGap = 10.5;
static const CGFloat kDotGap = 8.5;   // between two dots of a ring, along it
static const CGFloat kDot = 2.5, kMiddle = 6;
static const CGFloat kField = 2 * (kFirstRadius + (kRings - 1) * kRingGap) + 24;
static const CGFloat kCaptionGap = 6, kBottom = 14;
// How far a full-strength crest pushes the first ring out, how long it takes to reach the next ring, how
// long a ring takes to settle, and how long it stays lit: short, so the light reads as one ring traveling.
static const CGFloat kCrest = 6;
static const CFTimeInterval kRingDelay = 0.05, kCrestLength = 0.6, kLightLength = 0.34;
// Music Haptics' taps are felt at their own strength; their crest is this much of a tapped one.
static const CGFloat kPulse = 0.32;

typedef NS_ENUM(NSInteger, Feature) {
    FeatureControls,
    FeatureMusic,
    FeatureNative,   // only In the Background: iOS plays it, nothing to play from here
    FeatureNone,
};

static Feature featureNow(void) {
    if (SGEnabled(SGKeyControlHaptics)) return FeatureControls;
    if (SGMusicHapticsOn()) return FeatureMusic;
    return SGMusicHapticsInBackground() ? FeatureNative : FeatureNone;
}

static NSString *captionFor(Feature feature) {
    switch (feature) {
        case FeatureControls: return @"Tap to feel Controls";
        case FeatureMusic: return @"Tap to feel Music Haptics";
        case FeatureNative: return @"In the Background is played by iOS. Turn on Controls or Music Haptics to feel a tap";
        case FeatureNone: return @"Turn on Controls or Music Haptics to feel a tap";
    }
    return nil;
}

// What a tap shows of the feature's strength, 0 to 1: Controls' 10 to 100% as it is, Music Haptics' 20 to 200%
// halved, so its 100% is a middling crest.
static CGFloat strengthOf(Feature feature) {
    if (feature == FeatureControls) return SGHapticsStrength(SGKeyControlStrength);
    if (feature == FeatureMusic) return SGHapticsStrength(SGKeyMusicStrength) / 2;
    return 0.5;
}

static CAKeyframeAnimation *keyframes(NSString *path, NSArray *values, NSArray<NSNumber *> *times, CFTimeInterval begin, CFTimeInterval length) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:path];
    animation.values = values;
    animation.keyTimes = times;
    animation.timingFunctions = @[[CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1],
                                  [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
                                  [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    animation.additive = YES;
    animation.beginTime = begin;
    animation.duration = length;
    // Without this the crest runs at 60 Hz on a ProMotion screen.
    animation.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    return animation;
}

@implementation SGVibrationsPreview {
    CALayer *_field;
    CALayer *_middle;
    NSMutableArray<CALayer *> *_dots, *_crests;
    UILabel *_caption;
    Feature _feature;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _field = [CALayer layer];
    _field.bounds = CGRectMake(0, 0, kField, kField);
    [self.layer addSublayer:_field];
    _dots = [NSMutableArray array];
    _crests = [NSMutableArray array];
    CGPoint centre = CGPointMake(kField / 2, kField / 2);
    UIColor *accent = SGGreen();
    for (NSInteger ring = 0; ring < kRings; ring++) {
        CGFloat radius = kFirstRadius + ring * kRingGap;
        NSInteger count = MAX(6, lround(2 * M_PI * radius / kDotGap));
        CAReplicatorLayer *replicator = [CAReplicatorLayer layer];
        replicator.frame = _field.bounds;
        replicator.instanceCount = count;
        replicator.instanceTransform = CATransform3DMakeRotation(2 * M_PI / count, 0, 0, 1);
        // Every other ring turned half a step, so the dots weave rather than line up in spokes.
        replicator.transform = CATransform3DMakeRotation(ring % 2 ? M_PI / count : 0, 0, 0, 1);
        // Fainter outward, so the field has no hard edge.
        CGFloat rest = 0.46 - 0.34 * ring / (kRings - 1);
        CALayer *dot = [self dotOfSize:kDot colour:UIColor.whiteColor];
        dot.position = CGPointMake(centre.x + radius, centre.y);
        dot.opacity = rest;
        CALayer *crest = [self dotOfSize:kDot colour:accent];
        crest.position = dot.position;
        crest.opacity = 0;
        [replicator addSublayer:dot];
        [replicator addSublayer:crest];
        [_field addSublayer:replicator];
        [_dots addObject:dot];
        [_crests addObject:crest];
    }
    _middle = [self dotOfSize:kMiddle colour:accent];
    _middle.position = centre;
    _middle.opacity = 0.9;
    [_field addSublayer:_middle];

    _caption = [UILabel new];
    _caption.textColor = SGGrey();
    _caption.textAlignment = NSTextAlignmentCenter;
    _caption.numberOfLines = 0;
    [self addSubview:_caption];

    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(play)]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"Vibrations preview, rings of dots that ripple out from the middle with each tap";
    [self reload];
    return self;
}

- (CALayer *)dotOfSize:(CGFloat)size colour:(UIColor *)colour {
    CALayer *dot = [CALayer layer];
    dot.bounds = CGRectMake(0, 0, size, size);
    dot.cornerRadius = size / 2;
    dot.backgroundColor = colour.CGColor;
    return dot;
}

- (void)reload {
    _feature = featureNow();
    _caption.font = SGSubtitleFont();
    _caption.text = captionFor(_feature);
    self.accessibilityHint = _caption.text;
    [self setNeedsLayout];
}

- (CGFloat)captionHeightForWidth:(CGFloat)width {
    return ceil([_caption sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
}

- (CGFloat)heightForWidth:(CGFloat)width {
    return kField + kCaptionGap + [self captionHeightForWidth:width - 2 * self.layoutMargins.left] + kBottom;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, inset = self.layoutMargins.left;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _field.position = CGPointMake(width / 2, kField / 2);
    [CATransaction commit];
    _caption.frame = CGRectMake(inset, kField + kCaptionGap, width - 2 * inset, [self captionHeightForWidth:width - 2 * inset]);
}

- (BOOL)accessibilityActivate {
    [self play];
    return YES;
}

// The feature's own tap, through the path it plays from everywhere else, and its crest on the same frame.
- (void)play {
    [self reload];
    switch (_feature) {
        case FeatureControls: SGPlayFeedback(SGFeedbackAdd); break;
        case FeatureMusic: SGMusicHapticsPreview(); break;
        case FeatureNative:
        case FeatureNone: break;
    }
    [self rippleAt:strengthOf(_feature) pressing:YES];
}

// No finger is on the rings, so the middle stays where it is.
- (void)rippleAt:(CGFloat)strength {
    [self rippleAt:strength pressing:NO];
}

// A crest at `strength`, 0 to 1. A press dips the middle dot first, the way a finger would.
- (void)rippleAt:(CGFloat)strength pressing:(BOOL)press {
    if (!self.window) return;
    strength = MAX(0.05, MIN(1, strength));
    CFTimeInterval now = [_field convertTime:CACurrentMediaTime() fromLayer:nil];
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    // How many rings the crest carries over before it has lost two thirds of its height.
    CGFloat reach = 1.5 + 7 * strength;
    CGFloat light = 0.25 + 0.75 * strength;

    if (still) {
        for (NSInteger ring = 0; ring < kRings; ring++) {
            CGFloat fade = exp(-ring / reach);
            [_crests[ring] addAnimation:keyframes(@"opacity", @[@0, @(0.6 * light * fade), @(0.2 * light * fade), @0], @[@0, @0.3, @0.6, @1], now, 0.6) forKey:nil];
        }
        return;
    }
    if (press) {
        // From wherever the last press has it, so taps in a row never jump it.
        CGFloat from = (_middle.presentationLayer ?: _middle).transform.m11;
        CAKeyframeAnimation *dip = keyframes(@"transform.scale", @[@(from), @0.6, @(1 + 0.15 * strength), @1], @[@0, @0.25, @0.6, @1], now, 0.36);
        dip.additive = NO;
        [_middle addAnimation:dip forKey:@"press"];
    }
    for (NSInteger ring = 0; ring < kRings; ring++) {
        CGFloat fade = exp(-ring / reach);
        if (fade < 0.04) break;
        CGFloat push = kCrest * strength * fade;
        CFTimeInterval begin = now + ring * kRingDelay;
        // Out past where it rests, a little way back in, then still.
        NSArray *path = @[@0, @(push), @(-0.3 * push), @0];
        NSArray<NSNumber *> *times = @[@0, @0.24, @0.58, @1];
        [_dots[ring] addAnimation:keyframes(@"position.x", path, times, begin, kCrestLength) forKey:nil];
        [_crests[ring] addAnimation:keyframes(@"position.x", path, times, begin, kCrestLength) forKey:nil];
        [_crests[ring] addAnimation:keyframes(@"opacity", @[@0, @(light * fade), @(0.2 * light * fade), @0], @[@0, @0.3, @0.6, @1], begin, kLightLength) forKey:nil];
        [_dots[ring] addAnimation:keyframes(@"opacity", @[@0, @(0.35 * fade), @0, @0], @[@0, @0.3, @0.6, @1], begin, kLightLength) forKey:nil];
    }
}

- (void)setListening:(BOOL)listening {
    if (_listening == listening) return;
    _listening = listening;
    if (!listening) {
        SGMusicHapticsWatchTaps(nil);
        return;
    }
    __weak typeof(self) weakSelf = self;
    SGMusicHapticsWatchTaps(^(float intensity) {
        SGVibrationsPreview *preview = weakSelf;
        // The music's taps are felt anyway; with Reduce Motion they are not also shown.
        if (!preview || UIAccessibilityIsReduceMotionEnabled()) return;
        [preview rippleAt:kPulse * intensity pressing:NO];
    });
}

// Off screen nothing is left running: the page's listening goes, and any crest still out is dropped.
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) return;
    self.listening = NO;
    [_middle removeAllAnimations];
    for (CALayer *dot in _dots) [dot removeAllAnimations];
    for (CALayer *crest in _crests) [crest removeAllAnimations];
}

@end
