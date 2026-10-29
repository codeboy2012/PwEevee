// The Spatial voice page's preview (Sing.h): the listener in the middle of a disc of dots seen from just behind
// and above the head, the voice a point of the accent color in front with its light on the floor under it.
// The disc is the room and the camera is the head: as the head turns the disc turns the other way under it, so
// the voice keeps its place in the room and comes round to the side, by the angle SGSpatialVoiceAngle hands the
// Sing stream. Rings go out slowly from the voice, as sound does. With no head to follow, the disc
// sways slowly to show the same thing.
//
// It is drawn once into layers and moved by Core Animation alone: the turn is the disc layer's rotation and the
// voice's position, each motion animated from where it is on screen over the motions' own interval to where the
// head will be by the next one, at the speed it is turning, so the disc keeps up with the head rather than a
// motion behind it, and nothing runs per frame on the main thread. It listens to the head only while it is in
// a window, Spotify is in front and Motion & Fitness is allowed (the page never asks; the switch does). Under
// Reduce Motion the disc holds still and a turn of the head past a step fades it to the new angle.
//
// Threading: main thread, but for the motion handler, which hands its angle to the main queue.
#import <CoreMotion/CoreMotion.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/HeadGestures/HeadGestures.h"
#import "SGSingController.h"
#import "SGSingSpatial.h"
#import "SGSpatialPreview.h"

static NSString *const kListener = @"sing.preview";
static const CGFloat kStageHeight = 200;
static const CGFloat kMiddle = 0.47;            // the listener, down the stage
static const CGFloat kMaxRadius = 168;          // the disc's, at the widest phones
static const CGFloat kTilt = 66 * M_PI / 180;   // the disc tipped away from the camera
static const CGFloat kDistance = 560;           // the camera's, for the perspective
static const int kRings = 10;
static const CGFloat kDotSpacing = 7.5, kDotRadius = 1.15;
static const CGFloat kVoiceRing = 0.62;         // of the radius
static const CGFloat kVoiceHeight = 12;         // over the floor, as the listener's head is
// The sway while there is no head to follow: far enough to see the voice come round, slow enough to be calm,
// starting and turning back with no velocity.
static const double kSwayAngle = 38 * M_PI / 180, kSwaySeconds = 12;
// A turn this long or shorter follows a motion: straight, not eased. Each motion is animated to over the
// motions' interval as heard (AirPods send about 25 a second), held within kFollowShortest and kFollowLongest,
// and leads by no more than kFollowLead.
static const CFTimeInterval kFollowSeconds = 0.12, kFollowShortest = 1.0 / 120, kFollowLongest = 0.08;
static const double kFollowLead = 12 * M_PI / 180;
// Under Reduce Motion, the turn the voice must move by before the still picture fades to it.
static const double kStillStep = 15 * M_PI / 180;

@implementation SGSpatialPreview {
    CALayer *_stage, *_plane, *_field, *_listener, *_voice;
    CAReplicatorLayer *_ripples;
    UILabel *_caption;
    CGFloat _radius;
    double _angle;           // the disc's turn as last set, unwrapped
    double _heard;           // the voice's angle in the last motion, and when that motion was (its timestamp)
    NSTimeInterval _heardAt, _interval;   // the interval between motions, smoothed
    BOOL _listening, _live, _swaying;
    CMAuthorizationStatus _allowed;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.preservesSuperviewLayoutMargins = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitImage | UIAccessibilityTraitUpdatesFrequently;
    _stage = [CALayer layer];
    [self.layer addSublayer:_stage];
    _caption = [UILabel new];
    _caption.font = SGSubtitleFont();
    _caption.adjustsFontForContentSizeCategory = YES;
    _caption.textColor = SGGrey();
    _caption.numberOfLines = 0;
    [self addSubview:_caption];
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, UIApplicationDidEnterBackgroundNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:name object:nil];
    }
    return self;
}

- (void)dealloc {
    if (_listening) SGHeadMotionListen(kListener, nil);
}

#pragma mark - the picture

// A point of the floor, in points from the disc's middle (y negative ahead) and `height` over it, where the
// camera sees it with the disc turned by `turn`, from the stage's middle; `scale` how much nearer it is.
- (CGPoint)project:(CGPoint)point height:(CGFloat)height turn:(double)turn scale:(CGFloat *)scale {
    CGFloat x = point.x * cos(turn) - point.y * sin(turn), y = point.x * sin(turn) + point.y * cos(turn);
    CGFloat down = y * cos(kTilt) - height * sin(kTilt), near = y * sin(kTilt) + height * cos(kTilt);
    CGFloat w = 1 - near / kDistance;
    if (scale) *scale = 1 / w;
    return CGPointMake(x / w, down / w);
}

- (CGPoint)voiceAt:(double)turn {
    CGPoint at = [self project:CGPointMake(0, -kVoiceRing * _radius) height:kVoiceHeight turn:turn scale:NULL];
    return CGPointMake(_stage.bounds.size.width / 2 + at.x, _stage.bounds.size.height * kMiddle + at.y);
}

static CALayer *glowDot(CGFloat size, UIColor *color) {
    CALayer *dot = [CALayer layer];
    dot.bounds = CGRectMake(0, 0, size, size);
    dot.cornerRadius = size / 2;
    dot.backgroundColor = color.CGColor;
    dot.shadowColor = color.CGColor;
    dot.shadowOpacity = 0.9;
    dot.shadowRadius = size * 0.9;
    dot.shadowOffset = CGSizeZero;
    dot.shadowPath = [UIBezierPath bezierPathWithOvalInRect:dot.bounds].CGPath;
    return dot;
}

// A soft round light `size` across, fading out from `alpha` in its middle.
static CAGradientLayer *floorLight(CGPoint at, CGFloat size, UIColor *color, CGFloat alpha) {
    CAGradientLayer *light = [CAGradientLayer layer];
    light.type = kCAGradientLayerRadial;
    light.bounds = CGRectMake(0, 0, size, size);
    light.position = at;
    light.colors = @[(id)[color colorWithAlphaComponent:alpha].CGColor, (id)[color colorWithAlphaComponent:alpha * 0.35].CGColor,
                     (id)[color colorWithAlphaComponent:0].CGColor];
    light.locations = @[@0, @0.45, @1];
    light.startPoint = CGPointMake(0.5, 0.5);
    light.endPoint = CGPointMake(1, 1);
    return light;
}

// Everything is drawn again for a new width; the turn carries on from where it was.
- (void)build {
    for (CALayer *layer in [_stage.sublayers copy]) [layer removeFromSuperlayer];
    CGFloat width = self.bounds.size.width, scale = UIScreen.mainScreen.scale;
    _radius = MIN(kMaxRadius, width / 2 - 12);
    _stage.frame = CGRectMake(0, 0, width, kStageHeight);
    CGPoint middle = CGPointMake(width / 2, kStageHeight * kMiddle);
    UIColor *accent = SGGreen();

    // The floor: tipped away once, the room turning on it.
    _plane = [CALayer layer];
    _plane.bounds = CGRectMake(0, 0, 2 * _radius, 2 * _radius);
    _plane.position = middle;
    CATransform3D camera = CATransform3DIdentity;
    camera.m34 = -1 / kDistance;
    _plane.sublayerTransform = CATransform3DConcat(CATransform3DMakeRotation(kTilt, 1, 0, 0), camera);
    [_stage addSublayer:_plane];

    // The listener's own faint light on the floor, which never turns, as the head is the camera.
    [_plane addSublayer:floorLight(CGPointMake(_radius, _radius), 0.4 * _radius, UIColor.whiteColor, 0.16)];

    _field = [CALayer layer];
    _field.frame = _plane.bounds;
    [_field setValue:@(_angle) forKeyPath:@"transform.rotation.z"];
    [_plane addSublayer:_field];
    // Rings of dots spaced evenly along each, dimmer outward, one layer a ring.
    for (int ring = 1; ring <= kRings; ring++) {
        CGFloat r = _radius * ring / kRings;
        int count = (int)round(2 * M_PI * r / kDotSpacing);
        UIBezierPath *dots = [UIBezierPath bezierPath];
        for (int i = 0; i < count; i++) {
            double a = 2 * M_PI * (i + 0.5 * (ring % 2)) / count;
            CGPoint at = CGPointMake(_radius + r * cos(a), _radius + r * sin(a));
            [dots moveToPoint:CGPointMake(at.x + kDotRadius, at.y)];
            [dots addArcWithCenter:at radius:kDotRadius startAngle:0 endAngle:2 * M_PI clockwise:YES];
        }
        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.frame = _field.bounds;
        layer.path = dots.CGPath;
        layer.fillColor = UIColor.whiteColor.CGColor;
        layer.opacity = 0.46 * (1 - 0.6 * pow((double)ring / kRings, 1.4));
        layer.contentsScale = scale;
        [_field addSublayer:layer];
    }
    // The voice's light on the floor, and the sound going out from it.
    CGPoint spot = CGPointMake(_radius, _radius - kVoiceRing * _radius);
    CAGradientLayer *pool = floorLight(spot, 0.7 * _radius, accent, 0.6);
    [_field addSublayer:pool];
    _ripples = [CAReplicatorLayer layer];
    _ripples.bounds = pool.bounds;
    _ripples.position = spot;
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.frame = pool.bounds;
    ring.path = [UIBezierPath bezierPathWithOvalInRect:pool.bounds].CGPath;
    ring.fillColor = nil;
    ring.strokeColor = accent.CGColor;
    ring.lineWidth = 1.5;
    ring.opacity = 0;
    ring.contentsScale = scale;
    [_ripples addSublayer:ring];
    [_field addSublayer:_ripples];

    _listener = glowDot(8, [UIColor colorWithWhite:1 alpha:0.95]);
    _listener.shadowOpacity = 0.5;
    CGPoint head = [self project:CGPointZero height:kVoiceHeight turn:0 scale:NULL];
    _listener.position = CGPointMake(middle.x + head.x, middle.y + head.y);
    [_stage addSublayer:_listener];
    _voice = glowDot(10, accent);
    _voice.borderColor = [UIColor colorWithWhite:1 alpha:0.7].CGColor;
    _voice.borderWidth = 1.5;
    _voice.position = [self voiceAt:_angle];
    [_stage addSublayer:_voice];
    _swaying = NO;
    [self moveOn];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, inset = self.layoutMargins.left;
    if (width > 0 && fabs(_stage.bounds.size.width - width) > 0.5) [self build];
    CGFloat height = ceil([_caption sizeThatFits:CGSizeMake(width - 2 * inset, CGFLOAT_MAX)].height);
    _caption.frame = CGRectMake(inset, kStageHeight + 4, width - 2 * inset, height);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat inset = self.layoutMargins.left;
    CGFloat caption = ceil([_caption sizeThatFits:CGSizeMake(size.width - 2 * inset, CGFLOAT_MAX)].height);
    return CGSizeMake(size.width, kStageHeight + 4 + caption + 8);
}

#pragma mark - the turn

// The disc through `turns` (the voice's angle, to the listener's right) over `seconds`, and the voice round its
// ring with it rather than across. A repeating one (the sway) starts at `begin`, in media time.
- (void)animateTurns:(NSArray<NSNumber *> *)turns duration:(CFTimeInterval)seconds repeatFrom:(CFTimeInterval)begin key:(NSString *)key {
    NSMutableArray *positions = [NSMutableArray array];
    for (NSNumber *turn in turns) [positions addObject:[NSValue valueWithCGPoint:[self voiceAt:turn.doubleValue]]];
    CAKeyframeAnimation *rotation = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.values = turns;
    CAKeyframeAnimation *position = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    position.values = positions;
    for (CAKeyframeAnimation *animation in @[rotation, position]) {
        animation.duration = seconds;
        // A turn after the head asks for the display's full rate, so it keeps up with a quick turn.
        if (begin <= 0) {
            if (seconds <= kFollowSeconds) animation.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
            continue;
        }
        animation.repeatCount = HUGE_VALF;
        animation.beginTime = begin;
        // A slow turn is smooth at 60 frames a second, so it asks for no more. Its maximum stays at 120: a cap at 60
        // would hold the player's transitions down with it, should the player open over the page.
        animation.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 60);
    }
    [_field addAnimation:rotation forKey:key];
    [_voice addAnimation:position forKey:key];
}

// The turn on screen now, unwrapped to the one last set.
- (double)shownTurn {
    NSNumber *shown = [_field.presentationLayer valueForKeyPath:@"transform.rotation.z"];
    return shown ? _angle + remainder(shown.doubleValue - _angle, 2 * M_PI) : _angle;
}

- (void)setTurn:(double)angle {
    _angle = angle;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_field setValue:@(angle) forKeyPath:@"transform.rotation.z"];
    _voice.position = [self voiceAt:angle];
    [CATransaction commit];
}

- (void)turnTo:(double)target seconds:(CFTimeInterval)seconds {
    double from = [self shownTurn], to = from + remainder(target - from, 2 * M_PI);
    if (UIAccessibilityIsReduceMotionEnabled()) {
        if (fabs(to - _angle) < kStillStep && seconds <= kFollowSeconds) return;
        CATransition *fade = [CATransition animation];
        fade.type = kCATransitionFade;
        fade.duration = 0.35;
        [_stage addAnimation:fade forKey:@"fade"];
        [self setTurn:to];
        return;
    }
    // The voice's ring in steps of about 4 degrees, straight between them.
    int steps = MAX(1, (int)ceil(fabs(to - from) / 0.07));
    NSMutableArray<NSNumber *> *turns = [NSMutableArray array];
    for (int i = 0; i <= steps; i++) {
        double t = (double)i / steps;
        // Eased over a long turn, linear over a motion's own short one, so the next carries straight on.
        if (seconds > kFollowSeconds) t = t * t * (3 - 2 * t);
        [turns addObject:@(from + (to - from) * t)];
    }
    [self setTurn:to];
    [self animateTurns:turns duration:seconds repeatFrom:0 key:@"turn"];
}

// The sway: out to one side, then over to the other and back, slowing to a stop at each end. It sets out from
// wherever the disc is, eased out to the first side.
- (void)sway {
    NSMutableArray<NSNumber *> *turns = [NSMutableArray array];
    for (int i = 0; i <= 96; i++) [turns addObject:@(-kSwayAngle * cos(2 * M_PI * i / 96))];
    CFTimeInterval lead = 1.2;
    [self turnTo:-kSwayAngle seconds:lead];
    [self animateTurns:turns duration:kSwaySeconds repeatFrom:[_field convertTime:CACurrentMediaTime() fromLayer:nil] + lead key:@"sway"];
}

// Whichever of following, swaying and holding still is wanted now, and the ripples with it.
- (void)moveOn {
    if (!_field) return;
    BOOL still = UIAccessibilityIsReduceMotionEnabled(), moving = self.window && !still;
    BOOL sway = moving && !_live;
    if (sway != _swaying) {
        _swaying = sway;
        if (sway) [self sway];
        else {
            double shown = [self shownTurn];
            for (CALayer *layer in @[_field, _voice]) [layer removeAnimationForKey:@"sway"];
            [self setTurn:shown];
        }
    }
    if (still && !_live && fabs(_angle) > 0.001) [self turnTo:0 seconds:0.6];
    CALayer *ring = _ripples.sublayers.firstObject;
    if (moving && ![ring animationForKey:@"ripple"]) {
        // Three rings going out from the voice in turn, slowly, as sound does from where it comes from.
        CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        grow.fromValue = @0.18;
        grow.toValue = @1;
        CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
        fade.values = @[@0, @0.55, @0];
        fade.keyTimes = @[@0, @0.15, @1];
        CAAnimationGroup *ripple = [CAAnimationGroup animation];
        ripple.animations = @[grow, fade];
        ripple.duration = 3.6;
        ripple.repeatCount = HUGE_VALF;
        ripple.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.23 :1 :0.32 :1];
        ripple.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 60);
        [ring addAnimation:ripple forKey:@"ripple"];
        _ripples.instanceCount = 3;
        _ripples.instanceDelay = ripple.duration / 3;
    } else if (!moving) {
        [ring removeAnimationForKey:@"ripple"];
    }
}

#pragma mark - the head

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self refresh];
}

- (void)listen:(BOOL)listen {
    if (listen == _listening) return;
    _listening = listen;
    if (!listen) {
        SGHeadMotionListen(kListener, nil);
        [self followed:NAN at:0];
        return;
    }
    __weak typeof(self) weakSelf = self;
    // A front of the preview's own, from the first motion it hears: the audio's has followed the head for as long
    // as the song has played, and the two agree once the head has been still a while.
    __block SGSpatialFront front = {0};
    SGHeadMotionListen(kListener, ^(CMDeviceMotion *motion) {
        double angle = motion ? SGSpatialVoiceAngle(&front, motion.attitude.yaw, motion.timestamp, SGSingSpatialFront()) : NAN;
        if (!motion) front.hasFront = false;
        NSTimeInterval at = motion.timestamp;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf followed:angle at:at]; });
    });
}

// The voice's angle from the head's motion at its timestamp, NAN when the motion stopped.
- (void)followed:(double)angle at:(NSTimeInterval)at {
    BOOL live = _listening && !isnan(angle);
    double since = at - _heardAt, turned = remainder(angle - _heard, 2 * M_PI);
    _heard = angle;
    _heardAt = at;
    if (live != _live) {
        _live = live;
        _interval = 0;
        [self updateCaption];
        [self moveOn];
        if (live) [self turnTo:angle seconds:0.5];
        return;
    }
    if (!live) return;
    // A gap (the headphones out a moment, Spotify busy) is no interval, and no speed to lead by.
    if (since <= 0 || since > 4 * kFollowLongest) {
        [self turnTo:angle seconds:kFollowLongest];
        return;
    }
    _interval = _interval > 0 ? 0.8 * _interval + 0.2 * since : since;
    CFTimeInterval seconds = fmin(kFollowLongest, fmax(kFollowShortest, _interval));
    double lead = fmax(-kFollowLead, fmin(kFollowLead, turned / since * seconds));
    [self turnTo:angle + lead seconds:seconds];
}

- (void)refresh {
    _allowed = CMHeadphoneMotionManager.authorizationStatus;
    BOOL front = UIApplication.sharedApplication.applicationState != UIApplicationStateBackground;
    [self listen:self.window && front && _allowed == CMAuthorizationStatusAuthorized];
    [self updateCaption];
    [self moveOn];
}

- (void)updateCaption {
    NSString *text;
    if (_live) {
        text = SGSingSpatial() ? @"Following your head. Turn it, and the voice keeps its place in the room while the rest of the song turns "
                                 @"with you; stay turned, and it comes round in front again."
                               : @"Following your head. Turn Spatial voice on to hear the voice keep its place as you turn.";
    } else if (_allowed == CMAuthorizationStatusDenied || _allowed == CMAuthorizationStatusRestricted) {
        text = @"Motion & Fitness is off for Spotify, so the voice stays ahead. Settings > Privacy & Security > Motion & Fitness "
               @"turns it on.";
    } else {
        text = @"Preview. With AirPods that track your head, it follows yours: turn, and the voice keeps its place in the room "
               @"while the rest of the song turns with you.";
    }
    if ([text isEqualToString:_caption.text]) return;
    if (_caption.text) {
        [UIView transitionWithView:_caption duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{ self->_caption.text = text; } completion:nil];
    } else {
        _caption.text = text;
    }
    // A caption of another length makes the header another height, which the page reads as it lays out.
    [self.superview setNeedsLayout];
}

- (NSString *)accessibilityLabel {
    return @"Spatial voice preview: you in the middle of a field of dots, the voice a point in front of you";
}

- (NSString *)accessibilityValue {
    if (!_live) return _caption.text;
    long degrees = lround(fabs(remainder(_angle, 2 * M_PI)) * 180 / M_PI);
    NSString *where = degrees < 3 ? @"The voice is in front of you" : [NSString stringWithFormat:@"The voice is %ld degrees to your %@",
                                                                       degrees, remainder(_angle, 2 * M_PI) > 0 ? @"right" : @"left"];
    return [NSString stringWithFormat:@"%@. %@", where, _caption.text];
}

@end
