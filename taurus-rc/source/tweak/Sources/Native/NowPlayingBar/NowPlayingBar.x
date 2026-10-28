#import "Core/SGCore.h"
#import "NowPlayingBar.h"

static BOOL insideClass(UIView *view, NSString *marker) {
    for (UIView *v = view; v; v = v.superview) if ([NSStringFromClass(v.class) containsString:marker]) return YES;
    return NO;
}

static void hideConnectButton(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = NSStringFromClass(v.class);
        if (![name containsString:@"ConnectButtonView"] && ![name containsString:@"ConnectStateView"]) return;
        if (insideClass(v, @"InformationContainer")) return;
        UIView *item = v;
        while (item.superview && ![item.superview isKindOfClass:UIStackView.class]) item = item.superview;
        if (item.superview && !item.hidden) item.hidden = YES;
    });
}

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    hideConnectButton(((UIViewController *)self).view);
}
%end

%ctor {
    if (!SGNativeUI() || !SGHidden(SGHideBarConnect)) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
