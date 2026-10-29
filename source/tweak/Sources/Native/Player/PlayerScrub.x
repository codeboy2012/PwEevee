// Native player: a scrub is not a pull. A finger dragging the progress bar that drifts down closed the
// player instead of seeking (issue #172): a scroll view lets a UIControl in it track a touch while its own
// pan runs on the same touch, and Spotify's dismiss pull rides on the player list's pan. So that pan is
// off from the moment the slider tracks a touch until it lets go. Under this look the list also scrolls
// to the cards below, and a scrub holds that too while it lasts. The redesign's copy is
// Redesigned/Player/PlayerScroll.x's.
//
// Only the slider the redesign and Shared/Haptics/ControlHaptics.x hook. Spotify 9.1.78 also carries a
// NowPlaying_ECMKit.SliderNowPlaying (a UISlider too) and Encore's SeekBarView (a drag recognizer); which
// of them "New progress slider" brings is not proven, so they are left as Spotify has them.
#import "Core/SGCore.h"

// The player's vertical list (the string is in 9.1.78's binary), so a sideways list inside it is not the one held.
static NSString *const kListIdentifier = @"scrolling_npv_collection_view_accessibility_identifier";

// The list whose pan a scrub turned off, so only that one is turned back on: a pan off for some other
// reason stays off. One finger scrubs at a time, so one is enough.
static __weak UIScrollView *sg_scrubbedList;

static void scrubBegan(UIView *slider) {
    UIScrollView *list = nil;
    for (UIView *v = slider.superview; v && !list; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class] && [v.accessibilityIdentifier isEqualToString:kListIdentifier]) list = (UIScrollView *)v;
    }
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"native player: a scrub %@", list ? @"holds the list's pan" : @"found no list above the slider"); });
    if (!list.panGestureRecognizer.enabled) return;
    list.panGestureRecognizer.enabled = NO;
    sg_scrubbedList = list;
}

static void scrubEnded(void) {
    sg_scrubbedList.panGestureRecognizer.enabled = YES;
    sg_scrubbedList = nil;
}

// Shared/Haptics/ControlHaptics.x hooks the same begin and end for the scrub's taps; both call through.
%hook _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    BOOL tracking = %orig;
    if (tracking) scrubBegan((UIView *)self);
    return tracking;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    %orig;
    scrubEnded();
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    %orig;
    scrubEnded();
}

// A lock, a call or the player closing some other way can take the slider off screen mid-scrub, and then
// neither of the two above may come.
- (void)didMoveToWindow {
    %orig;
    if (!((UIView *)self).window) scrubEnded();
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[@"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider"]);
}
