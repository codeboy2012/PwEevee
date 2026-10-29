// Home redesign, FLEX builds only: what a scroll of Home costs. While Home's list is dragged or
// decelerating, a display link at the screen's own rate times each frame, and the Home hooks add up
// the calls and the time spent in them (SGRHomeProbeBegin/End). When the list settles, one log line
// says the scroll's frames, its hitches (a frame late by half a frame or more), the worst frame and
// each hook's share. A hitch the hooks do not account for is Spotify's main thread; lag with no
// hitches here is the render server (masks, clipping), which a display link does not see.
//
// Main thread stalls over 120 ms are sampled too (Diagnostics/SGHangSampler.h): for 90 s once Home is
// up, and during every scroll.
//
// The hooks install with the rest of the redesign and return at once outside a FLEX build: FLEX is
// injected after the tweak, so whether it is there is only known once the app runs.
#import <QuartzCore/QuartzCore.h>
#import "Core/SGCore.h"
#import "Diagnostics/Diagnostics.h"
#import "Diagnostics/SGHangSampler.h"
#import "Home.h"

// Frames with nothing moving before a scroll counts as over.
static const NSUInteger kSettledFrames = 10;
// A frame this long is described, the first few of each scroll.
static const CFTimeInterval kLongFrame = 0.1;
static const NSUInteger kLongFramesDescribed = 5;

// Section sizing includes Spotify's own measuring of the cell, which the hook calls through.
static const char *const kProbeNames[SGRHomeProbeCount] = {"section sizing", "header", "headings", "cards", "tiles"};
static NSUInteger sg_calls[SGRHomeProbeCount];
static CFTimeInterval sg_time[SGRHomeProbeCount];
static __weak UIScrollView *sg_list;
static char kHomeTabKey;

static BOOL probing(void) {
    static int state = -1;
    if (state < 0) state = SGIsDebugBuild() ? 1 : 0;
    return state == 1;
}

CFTimeInterval SGRHomeProbeBegin(void) {
    return probing() ? CACurrentMediaTime() : 0;
}

void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) {
    if (began <= 0 || probe >= SGRHomeProbeCount) return;
    sg_calls[probe]++;
    sg_time[probe] += CACurrentMediaTime() - began;
}

@interface SGRHomeScrollMeter : NSObject
- (void)watch:(UIScrollView *)list;
@end

@implementation SGRHomeScrollMeter {
    CADisplayLink *_link;
    __weak UIScrollView *_list;
    CFTimeInterval _start, _last, _worst, _frameSum;
    NSUInteger _frames, _hitches, _dropped, _settled, _layouts, _described;
    NSUInteger _calls[SGRHomeProbeCount];
    CFTimeInterval _time[SGRHomeProbeCount];
}

- (void)watch:(UIScrollView *)list {
    _layouts++;
    if (_link || !(list.isDragging || list.isDecelerating)) return;
    _list = list;
    _start = CACurrentMediaTime();
    _last = _worst = _frameSum = 0;
    _frames = _hitches = _dropped = _settled = _described = 0;
    _layouts = 1;
    SGHangSamplerStart(@"home scroll", 0);
    memcpy(_calls, sg_calls, sizeof(_calls));
    memcpy(_time, sg_time, sizeof(_time));
    _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    // A link left at its default rate holds the whole app to 60 Hz while it runs (CLAUDE.md).
    if (@available(iOS 15.0, *)) _link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)tick:(CADisplayLink *)link {
    CFTimeInterval expected = link.targetTimestamp - link.timestamp;
    if (_last > 0 && expected > 0) {
        CFTimeInterval gap = link.timestamp - _last;
        _frames++;
        _frameSum += expected;
        _worst = MAX(_worst, gap);
        if (gap > expected * 1.5) {
            _hitches++;
            _dropped += (NSUInteger)MAX(1, round(gap / expected) - 1);
            if (gap > kLongFrame && _described < kLongFramesDescribed) {
                _described++;
                [self describeLongFrame:gap];
            }
        }
    }
    _last = link.timestamp;
    UIScrollView *list = _list;
    if (list && (list.isDragging || list.isDecelerating || list.isTracking)) {
        _settled = 0;
        return;
    }
    if (++_settled >= kSettledFrames) [self finish];
}

// What was on screen around a long frame: each section in sight, top down, by the class of its root, and
// whether HomeSections.x collapsed it.
- (void)describeLongFrame:(CFTimeInterval)gap {
    UICollectionView *list = (UICollectionView *)_list;
    if (![list isKindOfClass:UICollectionView.class]) return;
    NSArray<UICollectionViewCell *> *cells = [list.visibleCells sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return a.frame.origin.y < b.frame.origin.y ? NSOrderedAscending : a.frame.origin.y > b.frame.origin.y ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (UICollectionViewCell *cell in cells) {
        UIView *root = cell.contentView.subviews.firstObject.subviews.firstObject;
        NSString *name = root ? NSStringFromClass(root.class) : @"empty";
        NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
        if (dot.location != NSNotFound) name = [name substringFromIndex:dot.location + 1];
        [parts addObject:[NSString stringWithFormat:@"%@%@ %.0f", name, SGRHomeSectionCollapsed(cell) ? @" (collapsed)" : @"", cell.bounds.size.height]];
    }
    SGLog(@"home perf: %.0f ms frame at offset %.0f over %@", gap * 1000, list.contentOffset.y, [parts componentsJoinedByString:@", "]);
}

- (void)finish {
    [_link invalidate];
    _link = nil;
    SGHangSamplerStop();
    CFTimeInterval duration = CACurrentMediaTime() - _start;
    NSMutableString *hooks = [NSMutableString string];
    CFTimeInterval ours = 0;
    for (NSUInteger i = 0; i < SGRHomeProbeCount; i++) {
        NSUInteger calls = sg_calls[i] - _calls[i];
        CFTimeInterval time = sg_time[i] - _time[i];
        ours += time;
        if (calls) [hooks appendFormat:@", %s %lu in %.1f ms", kProbeNames[i], (unsigned long)calls, time * 1000];
    }
    double rate = _frames && _frameSum > 0 ? _frames / _frameSum : 0;
    SGLog(@"home perf: scroll %.1f s, %lu frames at %.0f Hz, %lu hitches (%lu frames dropped), worst frame %.0f ms, list laid out %lu times; hooks %.1f ms in all%@",
          duration, (unsigned long)_frames, rate, (unsigned long)_hitches, (unsigned long)_dropped, _worst * 1000,
          (unsigned long)_layouts, ours * 1000, hooks.length ? hooks : @", none called");
}

@end

static SGRHomeScrollMeter *sg_meter;

static BOOL isHomeTab(UIViewController *page) {
    NSNumber *answer = objc_getAssociatedObject(page, &kHomeTabKey);
    if (answer) return answer.boolValue;
    static Class funkis;
    if (!funkis) funkis = NSClassFromString(@"_TtC19Home_FunkisPageImpl20FunkisViewController");
    BOOL home = NO;
    for (UIViewController *parent = page.parentViewController; parent && !home; parent = parent.parentViewController) {
        home = [parent isKindOfClass:funkis];
    }
    if (page.parentViewController) objc_setAssociatedObject(page, &kHomeTabKey, @(home), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return home;
}

%hook _TtC16Home_EvoPageImpl33EvoLoadableResourceViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (!probing() || sg_list) return;
    UIViewController *page = (UIViewController *)self;
    if (!isHomeTab(page)) return;
    for (UIView *sub in page.viewIfLoaded.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) sg_list = (UIScrollView *)sub;
    }
    if (!sg_list) return;
    SGLog(@"home perf: measuring the scrolls of %@", NSStringFromClass(sg_list.class));
    // The lag reported came in the first half minute after launch, scrolling or not.
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGHangSamplerStart(@"after launch", 90); });
}
%end

// The list lays out on every frame it moves, which is when a scroll is noticed.
%hook _TtC16Home_CarouselKit29TouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    if ((UIView *)self != sg_list) return;
    if (!sg_meter) sg_meter = [SGRHomeScrollMeter new];
    [sg_meter watch:(UIScrollView *)self];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController",
        @"_TtC16Home_CarouselKit29TouchCancellingCollectionView",
    ]);
}
