#import "Core/SGCore.h"
#import "PlayerEvents.h"

NSString *const SGPlayerTransitionNotification = @"spotifyglass.playerTransition";
NSString *const SGPlayerTransitionEndedNotification = @"spotifyglass.playerTransitionEnded";
static CFTimeInterval sg_transitionEnds;
static NSUInteger sg_transitionGeneration;

CFTimeInterval SGPlayerTransitionEnds(void) {
    return sg_transitionEnds > CACurrentMediaTime() ? sg_transitionEnds : 0;
}

static void announceTransition(UIViewController *unit, BOOL animated, NSString *what) {
    id<UIViewControllerTransitionCoordinator> coordinator = unit.transitionCoordinator;
    if (!animated || !coordinator) return;
    NSTimeInterval duration = MAX(0.1, coordinator.transitionDuration);
    NSUInteger generation = ++sg_transitionGeneration;
    sg_transitionEnds = CACurrentMediaTime() + duration;
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionNotification object:nil];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (generation != sg_transitionGeneration) return;
        sg_transitionEnds = 0;
        [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionEndedNotification object:nil];
    }];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"player %@ over %.2fs, by its appearance callbacks", what, duration); });
}

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    announceTransition((UIViewController *)self, animated, @"opens");
}
- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    announceTransition((UIViewController *)self, animated, @"closes");
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController"]);
}
