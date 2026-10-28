// The teaching sheet: five double nods, then five shakes, each made after a tone in the music. A ring shows the
// head as the AirPods report it, live: a dot in the middle moves with the head, down and up with a nod's pitch,
// left and right with a shake's yaw, a typical gesture taking it near the ring, and the ticks round the ring
// light up toward where the head went and how far, fading back as it settles (Reduce Motion: the dot moves,
// no ticks light). Five dots and "2 of 5" under the ring count what landed. A recording that holds no such
// gesture is not counted and is taken again; Redo last drops the last one counted. Five in, the threshold is
// learned from them together (SGHeadGesturesLearnFrom) and stored, the nod's before the shake begins, so a
// Cancel then keeps it.
//
// The sheet holds the motion open while it is up (SGHeadGesturesHold), so the system's Motion & Fitness prompt,
// the first time, comes over it before Start, and no gesture does anything to the song meanwhile. The ring
// reads the motion through SGHeadMotionListen and draws at 60 fps at most, only while the sheet shows.
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "HeadGestures.h"

static const NSInteger kSamples = 5;
// After the tone: a moment to react, a slow double nod and its settle.
static const double kWindow = 2.5;
// A beat to read the line before the next tone; with VoiceOver, room for its announcement first.
static const double kGap = 1.2;
static const double kSpokenGap = 3;
static const double kFade = 0.2;

// The ring: its size, its ticks, and the dot.
static const CGFloat kRingSize = 220;
enum { kTicks = 60 };
static const CGFloat kTickLength = 10, kTickWidth = 3, kDotSize = 18;
// How far the head turns, from where it rests, to take the dot to the ring: a brisk nod dips about 17
// degrees, a shake swings about 12 either side.
static const double kPitchReach = 0.3, kYawReach = 0.22;
// Where the head rests follows it this slowly, so a gesture moves the dot and a new posture does not.
static const double kRestSeconds = 1.2;
// The dot follows the motion's 25 samples a second this closely, so it glides between them at 60 fps.
static const double kFollowSeconds = 0.05;
// A lit tick fades back this slowly; the light spreads this far either side of the head's direction.
static const double kTickFadeSeconds = 0.45, kTickSpread = M_PI / 7;
// Under this share of the reach the head is still: no ticks light.
static const double kStill = 0.12;

static UILabel *label(UIFontTextStyle style, UIFontWeight weight, UIColor *color) {
    UILabel *view = [UILabel new];
    UIFont *font = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:style].pointSize weight:weight];
    view.font = [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:font];
    view.adjustsFontForContentSizeCategory = YES;
    view.textColor = color;
    view.textAlignment = NSTextAlignmentCenter;
    view.numberOfLines = 0;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

static void announce(NSString *text) {
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, text);
}

#pragma mark - the head, live

// The last attitude and where the head rests, written on the motion's queue, read by the ring on the main one.
static os_unfair_lock sg_poseLock = OS_UNFAIR_LOCK_INIT;
static struct {
    double pitch, yaw, restPitch, restYaw, time;
    BOOL has;
} sg_pose;

static void headMoved(CMDeviceMotion *motion) {
    os_unfair_lock_lock(&sg_poseLock);
    if (!motion) {
        sg_pose.has = NO;
    } else {
        double pitch = motion.attitude.pitch, yaw = motion.attitude.yaw, time = motion.timestamp, dt = time - sg_pose.time;
        if (!sg_pose.has || dt <= 0 || dt > 0.3) {
            sg_pose.restPitch = pitch;
            sg_pose.restYaw = yaw;
        } else {
            double k = 1 - exp(-dt / kRestSeconds);
            sg_pose.restPitch += k * (pitch - sg_pose.restPitch);
            sg_pose.restYaw = remainder(sg_pose.restYaw + k * remainder(yaw - sg_pose.restYaw, 2 * M_PI), 2 * M_PI);
        }
        sg_pose.pitch = pitch;
        sg_pose.yaw = yaw;
        sg_pose.time = time;
        sg_pose.has = YES;
    }
    os_unfair_lock_unlock(&sg_poseLock);
}

// How far the head is from where it rests, in radians: down and to the left are negative pitch and positive yaw.
static BOOL headOffset(double *pitch, double *yaw) {
    os_unfair_lock_lock(&sg_poseLock);
    BOOL has = sg_pose.has;
    *pitch = has ? sg_pose.pitch - sg_pose.restPitch : 0;
    *yaw = has ? remainder(sg_pose.yaw - sg_pose.restYaw, 2 * M_PI) : 0;
    os_unfair_lock_unlock(&sg_poseLock);
    return has;
}

#pragma mark - the ring

@interface SGTeachRing : UIView
// Listening and drawing, from when the sheet shows to when it goes.
- (void)start;
- (void)stop;
// The end: every tick lit, a checkmark for the dot, nothing more drawn.
- (void)showDone;
@end

@implementation SGTeachRing {
    CAShapeLayer *_track;
    NSArray<CAShapeLayer *> *_ticks;
    double _levels[kTicks];
    CALayer *_dot;
    CGPoint _dotAt;   // from the center
    UIImageView *_check;
    CADisplayLink *_link;
    CFTimeInterval _lastFrame;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _track = [CAShapeLayer layer];
    _track.strokeColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    _track.lineWidth = kTickWidth;
    _track.lineCap = kCALineCapRound;
    [self.layer addSublayer:_track];
    NSMutableArray<CAShapeLayer *> *ticks = [NSMutableArray array];
    for (NSInteger i = 0; i < kTicks; i++) {
        CAShapeLayer *tick = [CAShapeLayer layer];
        tick.strokeColor = SGAccentMark().CGColor;
        tick.lineWidth = kTickWidth;
        tick.lineCap = kCALineCapRound;
        tick.opacity = 0;
        tick.actions = @{@"opacity": NSNull.null};   // set every frame: no implicit fade on top
        [self.layer addSublayer:tick];
        [ticks addObject:tick];
    }
    _ticks = ticks;

    _dot = [CALayer layer];
    _dot.bounds = CGRectMake(0, 0, kDotSize, kDotSize);
    _dot.cornerRadius = kDotSize / 2;
    _dot.backgroundColor = UIColor.whiteColor.CGColor;
    _dot.actions = @{@"position": NSNull.null};
    [self.layer addSublayer:_dot];

    _check = SGSymbolView(@"checkmark", 34, UIImageSymbolWeightSemibold, 44);
    _check.tintColor = SGAccentMark();
    _check.hidden = YES;
    [self addSubview:_check];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
    return self;
}

- (CGFloat)radius {
    return MIN(self.bounds.size.width, self.bounds.size.height) / 2 - kTickWidth;
}

// How far the dot goes: inside the ticks with room to spare.
- (CGFloat)reach {
    return self.radius - kTickLength - kDotSize / 2 - 6;
}

- (CGPoint)centre {
    return CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGPoint centre = self.centre;
    CGFloat outer = self.radius, inner = outer - kTickLength;
    UIBezierPath *all = [UIBezierPath bezierPath];
    for (NSInteger i = 0; i < kTicks; i++) {
        CGFloat angle = 2 * M_PI * i / kTicks - M_PI_2;
        UIBezierPath *tick = [UIBezierPath bezierPath];
        [tick moveToPoint:CGPointMake(centre.x + inner * cos(angle), centre.y + inner * sin(angle))];
        [tick addLineToPoint:CGPointMake(centre.x + outer * cos(angle), centre.y + outer * sin(angle))];
        _ticks[i].path = tick.CGPath;
        [all appendPath:tick];
    }
    _track.path = all.CGPath;
    _dot.position = CGPointMake(centre.x + _dotAt.x, centre.y + _dotAt.y);
    _check.center = centre;
}

- (void)start {
    if (_link) return;
    SGHeadMotionListen(@"teaching", ^(CMDeviceMotion *motion) { headMoved(motion); });
    _lastFrame = 0;
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(frame:)];
    _link.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [_link invalidate];
    _link = nil;
    SGHeadMotionListen(@"teaching", nil);
}

- (void)frame:(CADisplayLink *)link {
    double dt = _lastFrame ? MIN(link.timestamp - _lastFrame, 0.1) : 1.0 / 60;
    _lastFrame = link.timestamp;

    // Screen down is a nod's down (pitch falling), screen left the head turned left (yaw rising).
    double pitch, yaw;
    headOffset(&pitch, &yaw);
    CGFloat reach = self.reach;
    CGFloat x = -yaw / kYawReach * reach, y = -pitch / kPitchReach * reach;
    CGFloat distance = hypot(x, y);
    if (distance > reach) {
        x *= reach / distance;
        y *= reach / distance;
    }
    double follow = 1 - exp(-dt / kFollowSeconds);
    _dotAt = CGPointMake(_dotAt.x + (x - _dotAt.x) * follow, _dotAt.y + (y - _dotAt.y) * follow);
    CGPoint centre = self.centre;
    _dot.position = CGPointMake(centre.x + _dotAt.x, centre.y + _dotAt.y);

    if (UIAccessibilityIsReduceMotionEnabled()) {
        for (CAShapeLayer *tick in _ticks) tick.opacity = 0;
        return;
    }
    double strength = MIN(1, distance / reach), toward = atan2(y, x), fade = exp(-dt / kTickFadeSeconds);
    for (NSInteger i = 0; i < kTicks; i++) {
        double angle = 2 * M_PI * i / kTicks - M_PI_2;
        double off = fabs(remainder(angle - toward, 2 * M_PI));
        double lit = strength > kStill ? strength * MAX(0, 1 - off / kTickSpread) : 0;
        _levels[i] = MAX(_levels[i] * fade, lit);
        float opacity = _levels[i] < 0.02 ? 0 : (float)_levels[i];
        if (fabsf(_ticks[i].opacity - opacity) > 0.01f) _ticks[i].opacity = opacity;
    }
}

- (void)showDone {
    [self stop];
    _dot.hidden = YES;
    _check.hidden = NO;
    [CATransaction begin];
    [CATransaction setAnimationDuration:kFade];
    for (CAShapeLayer *tick in _ticks) {
        tick.actions = nil;
        tick.opacity = 1;
    }
    [CATransaction commit];
}

@end

#pragma mark - the sheet

@interface SGTeachController : UIViewController
@end

@implementation SGTeachController {
    void (^_closed)(void);
    SGTeachRing *_dial;
    NSArray<UIView *> *_dots;
    UILabel *_count, *_heading, *_line;
    UIButton *_primaryButton, *_redoButton;
    NSMutableArray<NSData *> *_samples;
    SGHeadAxis _axis;
    BOOL _running, _finished;
    BOOL _listening;      // a recording is open
    NSUInteger _step;     // which scheduled step is current: Redo, a restart and closing move it on
}

- (instancetype)initWithClosed:(void (^)(void))closed {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _closed = [closed copy];
    _samples = [NSMutableArray array];
    self.title = @"Teach your gestures";
    return self;
}

- (BOOL)nod {
    return _axis == SGHeadAxisPitch;
}

- (UIButton *)buttonTitled:(NSString *)title prominent:(BOOL)prominent action:(SEL)action {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) config = prominent ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration glassButtonConfiguration];
    else config = prominent ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    if (prominent) {
        config.baseBackgroundColor = SGGreen();
        config.baseForegroundColor = SGOnAccent();
    } else {
        config.baseForegroundColor = UIColor.whiteColor;
    }
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    config.title = title;
    config.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *attributes) {
        NSMutableDictionary *styled = [attributes mutableCopy];
        UIFont *font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        styled[NSFontAttributeName] = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:font];
        return styled;
    };
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    [button addTarget:self action:action forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (void)setPrimaryTitle:(NSString *)title {
    UIButtonConfiguration *config = _primaryButton.configuration;
    config.title = title;
    _primaryButton.configuration = config;
    _primaryButton.hidden = title == nil;
}

// Five dots and "2 of 5" beside them, one line under the ring; VoiceOver reads the count off the ring.
- (UIView *)progressRow {
    NSMutableArray<UIView *> *dots = [NSMutableArray array];
    for (NSInteger i = 0; i < kSamples; i++) {
        UIView *dot = [UIView new];
        dot.layer.cornerRadius = 4;
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[[dot.widthAnchor constraintEqualToConstant:8], [dot.heightAnchor constraintEqualToConstant:8]]];
        [dots addObject:dot];
    }
    _dots = dots;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:dots];
    row.spacing = 6;
    row.alignment = UIStackViewAlignmentCenter;
    UIFont *digits = [UIFont monospacedDigitSystemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline].pointSize weight:UIFontWeightSemibold];
    _count = label(UIFontTextStyleSubheadline, UIFontWeightSemibold, SGGrey());
    _count.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline] scaledFontForFont:digits];
    _count.numberOfLines = 1;
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[row, _count]];
    line.spacing = 12;
    line.alignment = UIStackViewAlignmentCenter;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.accessibilityElementsHidden = YES;
    return line;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // iOS 26 gives a sheet its own material; before it the sheet takes the mod's page color.
    if (@available(iOS 26.0, *)) {} else self.view.backgroundColor = SGPageBackground();
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];

    _dial = [SGTeachRing new];
    _dial.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *progress = [self progressRow];
    _heading = label(UIFontTextStyleTitle2, UIFontWeightBold, UIColor.whiteColor);
    _heading.accessibilityTraits = UIAccessibilityTraitHeader;
    _line = label(UIFontTextStyleBody, UIFontWeightRegular, SGGrey());
    _primaryButton = [self buttonTitled:@"Start" prominent:YES action:@selector(primary)];
    _redoButton = [self buttonTitled:@"Redo last" prominent:NO action:@selector(redo)];
    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_redoButton, _primaryButton]];
    buttons.axis = UILayoutConstraintAxisVertical;
    buttons.spacing = 12;
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView *view in @[_dial, progress, _heading, _line, buttons]) [self.view addSubview:view];

    // The ring stays put as the lines under it change length.
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *size = [_dial.widthAnchor constraintEqualToConstant:kRingSize];
    size.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [_dial.topAnchor constraintEqualToAnchor:safe.topAnchor constant:28],
        [_dial.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_dial.heightAnchor constraintEqualToAnchor:_dial.widthAnchor],
        [_dial.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-80],
        size,
        [progress.topAnchor constraintEqualToAnchor:_dial.bottomAnchor constant:24],
        [progress.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [_heading.topAnchor constraintEqualToAnchor:progress.bottomAnchor constant:24],
        [_heading.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:32],
        [_heading.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-32],
        [_line.topAnchor constraintEqualToAnchor:_heading.bottomAnchor constant:8],
        [_line.leadingAnchor constraintEqualToAnchor:_heading.leadingAnchor],
        [_line.trailingAnchor constraintEqualToAnchor:_heading.trailingAnchor],
        [_line.bottomAnchor constraintLessThanOrEqualToAnchor:buttons.topAnchor constant:-16],
        [buttons.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [buttons.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [buttons.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    ]];

    [self showGesture];
    _line.text = @"After each tone, nod twice the way you would say yes. Five nods, then five shakes.";
    _redoButton.hidden = YES;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    SGHeadGesturesHold(YES);
    if (!_finished) [_dial start];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _step++;
    _listening = NO;
    [_dial stop];
    SGHeadGesturesStopListening();
    SGHeadGesturesHold(NO);
    if (_closed) _closed();
    _closed = nil;
}

#pragma mark - what it shows

- (void)showGesture {
    _heading.text = self.nod ? @"Double nod" : @"Shake";
    _dial.accessibilityLabel = self.nod ? @"Double nods" : @"Shakes";
    [self showCount];
}

- (void)showCount {
    NSInteger landed = (NSInteger)_samples.count;
    _count.text = [NSString stringWithFormat:@"%ld of %ld", (long)landed, (long)kSamples];
    _dial.accessibilityValue = _count.text;
    // Landed dots full, the one being recorded dim, the rest gray: a color change, so Reduce Motion keeps it.
    [UIView animateWithDuration:kFade delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        for (NSInteger i = 0; i < kSamples; i++) {
            BOOL recording = i == landed && self->_listening;
            self->_dots[i].backgroundColor = i < landed ? SGGreen() : recording ? [SGGreen() colorWithAlphaComponent:0.4] : [UIColor colorWithWhite:1 alpha:0.18];
        }
    } completion:nil];
    _redoButton.hidden = !_running || _finished;
    _redoButton.enabled = landed > 0;
}

- (double)gap {
    return UIAccessibilityIsVoiceOverRunning() ? kSpokenGap : kGap;
}

#pragma mark - the steps

// Runs `next` after `delay` unless something moved the steps on meanwhile.
- (void)after:(double)delay then:(void (^)(void))next {
    NSUInteger step = ++_step;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (step == self->_step) next();
    });
}

- (void)primary {
    if (_finished) {
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    _running = YES;
    [self setPrimaryTitle:nil];
    [self record];
}

- (void)record {
    NSUInteger step = ++_step;
    _listening = YES;
    _line.text = self.nod ? @"Nod twice now." : @"Shake your head now.";
    [self showCount];
    SGHeadGesturesCue(SGHeadCueReady);
    SGHeadGesturesRecord(kWindow, ^(NSData *motion) {
        if (step == self->_step) [self recorded:motion];
    });
}

- (void)recorded:(NSData *)motion {
    _listening = NO;
    if (!motion.length) {
        _running = NO;
        [self showCount];
        SGHeadGesturesCue(SGHeadCueFailed);
        _line.text = @"No motion came in. Put in AirPods that track head motion, and allow Spotify in Settings > "
                      "Privacy & Security > Motion & Fitness.";
        announce(_line.text);
        [self setPrimaryTitle:@"Try again"];
        return;
    }
    BOOL counted = SGHeadGesturesSampleThreshold(motion, _axis) > 0;
    if (counted) [_samples addObject:motion];
    [self showCount];
    SGHeadGesturesCue(counted ? SGHeadCueWorked : SGHeadCueFailed);
    NSInteger landed = (NSInteger)_samples.count;
    if (counted) {
        _line.text = landed < kSamples ? @"Got it." : self.nod ? @"That's five nods." : @"That's five shakes.";
        announce([NSString stringWithFormat:@"Got it, %ld of %ld.", (long)landed, (long)kSamples]);
    } else {
        _line.text = self.nod ? @"That didn't read as a double nod. Once more after the tone."
                              : @"That didn't read as a shake. Once more after the tone.";
        announce(_line.text);
    }
    if (landed < kSamples) [self after:self.gap then:^{ [self record]; }];
    else [self learn];
}

- (void)learn {
    if (SGHeadGesturesLearnFrom(_samples, _axis) <= 0) {
        [_samples removeAllObjects];
        _line.text = @"Those five were too far apart to learn from. Let's take them again.";
        announce(_line.text);
        [self after:self.gap * 2 then:^{
            [self showCount];
            [self record];
        }];
        return;
    }
    if (self.nod) {
        _line.text = @"Your nod is learned. Next, five shakes.";
        announce(_line.text);
        [self after:self.gap * 1.5 then:^{
            self->_axis = SGHeadAxisYaw;
            [self->_samples removeAllObjects];
            [self showGesture];
            self->_line.text = @"After each tone, shake your head the way you would say no.";
            [self after:self.gap then:^{ [self record]; }];
        }];
        return;
    }
    _finished = YES;
    _running = NO;
    self.navigationItem.leftBarButtonItem = nil;
    _heading.text = @"All set";
    [_dial showDone];
    _dial.accessibilityLabel = @"Nod and shake";
    _line.text = @"Both are learned from yours. If one still slips past, raise Sensitivity.";
    announce([@"All set. " stringByAppendingString:_line.text]);
    [self showCount];
    [self setPrimaryTitle:@"Done"];
}

- (void)redo {
    if (!_running || !_samples.count) return;
    _listening = NO;
    SGHeadGesturesStopListening();
    [_samples removeLastObject];
    _line.text = @"Taking that one again.";
    announce([NSString stringWithFormat:@"Removed. %ld of %ld.", (long)_samples.count, (long)kSamples]);
    [self showCount];
    [self after:self.gap then:^{ [self record]; }];
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

void SGPresentHeadGesturesTeaching(UIViewController *owner, void (^closed)(void)) {
    SGTeachController *teach = [[SGTeachController alloc] initWithClosed:closed];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:teach];
    // Outside Spotify's own stacks the sheet would take the system's appearance, light in light mode.
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    SGPresentDark(nav);
    nav.sheetPresentationController.prefersGrabberVisible = YES;
    [owner presentViewController:nav animated:YES completion:nil];
}
