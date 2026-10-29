// Player redesign: a volume slider under the controls, as the Music app has. It is MPVolumeView, as the HIG asks
// (sliders.md, playing-audio.md), so it is the system's volume: the hardware buttons move it, and while Spotify plays
// on a Connect device it is that device's, which Spotify hands iOS through its remote volume. No route button: the
// footer's Connect glyph is the route.
//
// It sits in Spotify's bottom stack, outside its arranged views, between the controls and the footer row, so the
// lyrics fade it with the rest of the stack (PlayerLyrics.x) and its touches stay inside the stack. The footer's
// lowerRow (PlayerFooter.x) places it after the moves, and keeps the controls where Spotify put them to make the room.
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

// The row's height (the touch area) and the glyphs' point size and gap to the track.
static const CGFloat kRowHeight = 32, kGlyphSize = 13, kGlyphGap = 10;
// Half the play button's height and half the footer glyphs': below this much room between them it does not fit.
static const CGFloat kButtonsHalf = 24, kGlyphsHalf = 14;
// The track's height at rest and held, how far it grows past each end, how far the glyphs move out and by how much
// they scale (each clamped to the room the row has on that side) — Music's own held numbers.
static const CGFloat kTrackRest = 7, kTrackHeld = 18, kStretch = 7, kGlyphShift = 9, kGlyphHeldScale = 1.08;
// White's opacity: the fill at rest and held, the empty part, the glyphs at rest (held they are full white).
static const CGFloat kFillRest = 0.65, kFillHeld = 1, kEmpty = 0.24, kGlyphRest = 0.68;

static char kSliderContext, kSessionContext;

static UIImageView *glyph(NSString *symbol) {
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:kGlyphSize weight:UIImageSymbolWeightSemibold];
    UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]];
    view.tintColor = UIColor.whiteColor;
    view.alpha = kGlyphRest;
    view.contentMode = UIViewContentModeCenter;
    view.isAccessibilityElement = NO;
    return view;
}

@interface SGRVolumeRow : UIControl
@property (nonatomic) BOOL matchTimeSlider;
@end

@implementation SGRVolumeRow {
    MPVolumeView *_system;
    UISlider *_systemSlider;
    UIView *_track, *_fill;
    UIImageView *_quiet, *_loud;
    CGFloat _value, _startValue, _startX, _trackMin, _trackMax;
    BOOL _held;
    NSTimer *_poll;
    CFTimeInterval _lastPush;
    NSHashTable<UIGestureRecognizer *> *_suspended;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    // Only plumbing: the slider inside moves the system's volume, nobody sees or touches the view.
    _system = [MPVolumeView new];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    _system.showsRouteButton = NO;
#pragma clang diagnostic pop
    _system.alpha = 0.01;
    _system.userInteractionEnabled = NO;
    [self addSubview:_system];

    _track = [UIView new];
    _track.clipsToBounds = YES;
    _track.userInteractionEnabled = NO;
    _track.layer.cornerCurve = kCACornerCurveContinuous;
    _track.backgroundColor = [UIColor colorWithWhite:1 alpha:kEmpty];
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    [_track addSubview:_fill];
    [self addSubview:_track];

    _quiet = glyph(@"speaker.fill");
    _loud = glyph(@"speaker.wave.3.fill");
    [self addSubview:_quiet];
    [self addSubview:_loud];

    _value = AVAudioSession.sharedInstance.outputVolume;
    [AVAudioSession.sharedInstance addObserver:self forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew
                                       context:&kSessionContext];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshFromSystem)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];

    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Volume";
    self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    return self;
}

- (void)dealloc {
    [_poll invalidate];
    [self restoreAncestorGestures];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [AVAudioSession.sharedInstance removeObserver:self forKeyPath:@"outputVolume" context:&kSessionContext];
    [_systemSlider removeObserver:self forKeyPath:@"value" context:&kSliderContext];
}

- (void)setMatchTimeSlider:(BOOL)match {
    if (_matchTimeSlider == match) return;
    _matchTimeSlider = match;
    [self setNeedsLayout];
}

// The volume view builds its slider itself, so it is looked for until it is there.
- (UISlider *)systemSlider {
    if (!_systemSlider) {
        for (UIView *view in _system.subviews) {
            if (![view isKindOfClass:UISlider.class]) continue;
            _systemSlider = (UISlider *)view;
            [_systemSlider addObserver:self
                            forKeyPath:@"value"
                               options:NSKeyValueObservingOptionNew
                               context:&kSliderContext];
            break;
        }
    }

    // Hide the system slider's visible artwork.
    _systemSlider.thumbTintColor = UIColor.clearColor;
    _systemSlider.minimumTrackTintColor = UIColor.clearColor;
    _systemSlider.maximumTrackTintColor = UIColor.clearColor;

    return _systemSlider;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kSliderContext && context != &kSessionContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshFromSystem]; });
}

- (void)refreshFromSystem {
    // Not while the finger is on it, nor just after it let go: the system settles on its own steps a moment later.
    if (_held || CACurrentMediaTime() - _lastPush < 0.6) return;
    UISlider *slider = [self systemSlider];
    CGFloat system = slider ? slider.value : AVAudioSession.sharedInstance.outputVolume;
    if (fabs(system - _value) > 0.002) [self setValue:system fromUser:NO];
}

- (void)pushVolume {
    UISlider *slider = [self systemSlider];
    if (!slider) return;
    _lastPush = CACurrentMediaTime();
    [slider setValue:_value animated:NO];
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
}

// The room the row has to either side inside its stack: what the held track and glyphs may grow into.
- (CGFloat)roomLeft { return MAX(0, CGRectGetMinX(self.frame)); }

- (CGFloat)roomRight {
    UIView *stack = self.superview;
    return stack ? MAX(0, stack.bounds.size.width - CGRectGetMaxX(self.frame)) : 0;
}

// The track's frame for the state it is in: it grows past both ends while held.
- (void)syncTrack {
    CGFloat height = _held ? kTrackHeld : kTrackRest;
    CGFloat left = _held ? MIN(kStretch, [self roomLeft]) : 0, right = _held ? MIN(kStretch, [self roomRight]) : 0;
    CGFloat scale = self.traitCollection.displayScale ?: 3;
    CGFloat top = round((CGRectGetMidY(self.bounds) - height / 2) * scale) / scale;
    _track.frame = CGRectMake(_trackMin - left, top, MAX(0, _trackMax - _trackMin) + left + right, height);
    _track.layer.cornerRadius = height / 2;
    [self syncFill];
}

// The fill is a plain rectangle the pill's clipping rounds, so its right edge stays straight, as in Music.
- (void)syncFill {
    CGSize size = _track.bounds.size;
    _fill.frame = CGRectMake(0, 0, size.width * _value, size.height);
}

- (void)syncStyle {
    _fill.backgroundColor = [UIColor colorWithWhite:1 alpha:_held ? kFillHeld : kFillRest];
    CGFloat scale = _held ? kGlyphHeldScale : 1;
    CGFloat left = _held ? MIN(kGlyphShift, [self roomLeft]) : 0, right = _held ? MIN(kGlyphShift, [self roomRight]) : 0;
    CGAffineTransform grown = CGAffineTransformMakeScale(scale, scale);
    _quiet.transform = CGAffineTransformConcat(grown, CGAffineTransformMakeTranslation(-left, 0));
    _loud.transform = CGAffineTransformConcat(grown, CGAffineTransformMakeTranslation(right, 0));
    _quiet.alpha = _loud.alpha = _held ? 1 : kGlyphRest;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat side = kRowHeight, middle = CGRectGetMidY(bounds), glyphWidth = side / 2 + kGlyphSize / 2;
    BOOL match = self.matchTimeSlider;
    _system.frame = CGRectMake(0, 0, MAX(140, bounds.size.width), side);
    [_system layoutIfNeeded];
    [self systemSlider];
    _quiet.hidden = _loud.hidden = match;
    CGFloat loudMin = CGRectGetMaxX(bounds) - side / 2 - kGlyphSize;
    _quiet.bounds = CGRectMake(0, 0, glyphWidth, side);
    _loud.bounds = CGRectMake(0, 0, glyphWidth, side);
    _quiet.center = CGPointMake(glyphWidth / 2, middle);
    _loud.center = CGPointMake(loudMin + glyphWidth / 2, middle);
    _trackMin = match ? 0 : glyphWidth + kGlyphGap;
    _trackMax = match ? bounds.size.width : loudMin - kGlyphGap;
    [self syncTrack];
    [self syncStyle];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [_poll invalidate];
        _poll = nil;
        [self restoreAncestorGestures];
        return;
    }
    [self systemSlider];
    [self refreshFromSystem];
    if (_poll) return;
    __weak SGRVolumeRow *weakSelf = self;
    _poll = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf refreshFromSystem]; }];
    _poll.tolerance = 0.1;
    [NSRunLoop.mainRunLoop addTimer:_poll forMode:NSRunLoopCommonModes];
}

// Prevent the player from stealing volume swipe gesture.
- (void)suspendAncestorGestures {
    if (_suspended) return;
    _suspended = [NSHashTable weakObjectsHashTable];
    for (UIView *view = self.superview; view; view = view.superview) {
        for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
            BOOL pan = [recognizer isKindOfClass:UIPanGestureRecognizer.class];
            if (!pan || [recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class] || !recognizer.enabled) continue;
            recognizer.enabled = NO;
            [_suspended addObject:recognizer];
        }
    }
}

- (void)restoreAncestorGestures {
    for (UIGestureRecognizer *recognizer in _suspended) recognizer.enabled = YES;
    _suspended = nil;
}

- (void)setValue:(CGFloat)value fromUser:(BOOL)fromUser {
    value = MIN(1, MAX(0, value));
    _value = value;
    if (!fromUser && !_held && self.window) {
        UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction |
                                         UIViewAnimationOptionCurveEaseOut;
        [UIView animateWithDuration:0.15 delay:0 options:options animations:^{ [self syncFill]; } completion:nil];
    } else {
        [self syncFill];
    }
    if (fromUser) [self pushVolume];
}

- (void)setHeld:(BOOL)held {
    if (_held == held) return;
    _held = held;
    if (held) [self suspendAncestorGestures]; else [self restoreAncestorGestures];
    void (^apply)(void) = ^{ [self syncTrack]; [self syncStyle]; };
    UIViewAnimationOptions options = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    if (held) {
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:options
                         animations:apply completion:nil];
    } else {
        [UIView animateWithDuration:0.16 delay:0 options:options | UIViewAnimationOptionCurveEaseOut
                         animations:apply completion:nil];
    }
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    _startX = [touch locationInView:self].x;
    _startValue = _value;
    [self setHeld:YES];
    return YES;
}

// Relative to where the finger came down: the value moves by the finger's travel over the track's length.
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    CGFloat span = MAX(1, _trackMax - _trackMin);
    [self setValue:_startValue + ([touch locationInView:self].x - _startX) / span fromUser:YES];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { [self setHeld:NO]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self setHeld:NO]; }

- (NSString *)accessibilityValue { return [NSString stringWithFormat:@"%d%%", (int)round(_value * 100)]; }
- (void)accessibilityIncrement { [self setValue:_value + 0.0625 fromUser:YES]; }
- (void)accessibilityDecrement { [self setValue:_value - 0.0625 fromUser:YES]; }

@end

static char kVolumeKey, kPlayKey, kProgressSliderKey;

// Read at launch, as the player's other switches are: the footer asks on every layout pass.
BOOL SGRPlayerVolumeOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        id shown = [defaults objectForKey:SGRKeyPlayerVolume];
        id hidden = [defaults objectForKey:SGRKeyHidePlayerVolume];
        if (!shown && hidden) [defaults setBool:![hidden boolValue] forKey:SGRKeyPlayerVolume];
        [defaults removeObjectForKey:SGRKeyHidePlayerVolume];
        shown = [defaults objectForKey:SGRKeyPlayerVolume];
        on = shown ? [shown boolValue] : hidden ? ![hidden boolValue] : SGFlag(SGRKeyPlayerVolume, NO);
    });
    return on;
}

BOOL SGRPlayerPlaceVolume(UIView *stack, UIView *controls, UIView *row, CGFloat margin) {
    SGRVolumeRow *volume = objc_getAssociatedObject(stack, &kVolumeKey);
    if (!SGRPlayerVolumeOn() || !controls) {
        if (volume) volume.alpha = 0;
        return NO;
    }
    if (!volume) {
        volume = [SGRVolumeRow new];
        // The stack grows and shrinks from its top while Spotify's own views stay put on screen: the row keeps its
        // distance from the stack's bottom, as they do (from the top it rode up and sat on the controls at launch).
        volume.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
        objc_setAssociatedObject(stack, &kVolumeKey, volume, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The Match time slider switch is off until asked for; an unset switch must not turn it on and hide the glyphs.
    volume.matchTimeSlider = SGFlag(SGRKeyPlayerVolumeMatchSlider, NO);
    if (volume.superview != stack) [stack addSubview:volume];
    // Halfway between the play button's bottom and the footer glyphs' top, each where it is drawn (convertRect: takes
    // the moves' transforms in): the controls' unit reaches above its buttons, so its own middle sat the row 16pt high.
    // Without the button, the unit's middle stands in for it.
    UIView *play = SGRFindByIdentifier(controls, @"SPTNowPlayingPlayButton", &kPlayKey);
    CGFloat above = play ? CGRectGetMaxY([play convertRect:play.bounds toView:stack])
                         : controls.center.y + controls.transform.ty + kButtonsHalf;
    CGFloat below = [row convertPoint:CGPointMake(CGRectGetMidX(row.bounds), CGRectGetMidY(row.bounds)) toView:stack].y - kGlyphsHalf;
    CGFloat height = kRowHeight, room = below - above;
    CGRect frame = CGRectMake(margin, round((above + below - height) / 2), MAX(0, stack.bounds.size.width - 2 * margin), height);
    if (volume.matchTimeSlider) {
        UIView *player = stack.superview;
        UISlider *progress = (UISlider *)SGRFindByIdentifier(player, @"SPTNowPlayingSliderV2", &kProgressSliderKey);
        if ([progress isKindOfClass:UISlider.class]) {
            CGRect progressFrame = [progress convertRect:progress.bounds toView:stack];
            frame.origin.x = CGRectGetMinX(progressFrame);
            frame.size.width = CGRectGetWidth(progressFrame);
        }
    }
    if (!CGRectEqualToRect(volume.frame, frame)) volume.frame = frame;
    // The lyrics fade the stack's views by their alpha and bring back only the ones they faded.
    // The track is a slim part of the row's height: it fits with the glyphs' and buttons' own clearance around it.
    // The lyrics fade owns the row's alpha while they show their lines alone; a track change
    // lays the stack out again, and geometry must not re-show the row over the lines nor blink
    // it away while the fade holds it.
    BOOL fits = room >= height * 0.6;
    if (SGRLyricsFadedView(volume)) volume.alpha = 0;
    else if (!fits) volume.alpha = 0;
    else if (volume.alpha < 0.01 && controls.alpha > 0.99) volume.alpha = 1;
    return fits;
}
