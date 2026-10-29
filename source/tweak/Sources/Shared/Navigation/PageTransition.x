#import "Core/SGCore.h"

// SPNavigationController's own states: 0 shows the bar, 1 gives it the page's own alpha, 2 hides it.
static const NSInteger kBarStateHidden = 2;

// SPTNavigationControllerNavigationBarState, which every page on the stack answers.
@interface UIViewController (SGNavigationBarState)
- (NSInteger)preferredNavigationBarState;
- (BOOL)prefersLiquidGlassNavigationBar;
@end

static BOOL wantsNoBar(UIViewController *page) {
    if (![page respondsToSelector:@selector(preferredNavigationBarState)]) return NO;
    if (page.preferredNavigationBarState != kBarStateHidden) return NO;
    return !([page respondsToSelector:@selector(prefersLiquidGlassNavigationBar)] && page.prefersLiquidGlassNavigationBar);
}

%hook SPNavigationController

- (void)navigationController:(UINavigationController *)controller willShowViewController:(UIViewController *)page animated:(BOOL)animated {
    %orig;
    UINavigationController *nav = (UINavigationController *)self;
    if (nav.navigationBarHidden || !wantsNoBar(page)) return;
    SGLog(@"page transition: %@ wants no bar, taking it now rather than at the end", NSStringFromClass(page.class));
    [nav setNavigationBarHidden:YES animated:animated];
}

%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPNavigationController"]);
}
