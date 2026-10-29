#import "Core/SGCore.h"
#import "Onboarding.h"

%hook _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!SGFlag(SGKeyOnboardingSeen, NO)) SGShowOnboarding();
        });
    });
}
%end

%ctor {
    if (SGFlag(SGKeyOnboardingSeen, NO)) return;
    %init;
    SGRequireClasses(@[@"_TtC19Home_FunkisPageImpl20FunkisViewController"]);
}
