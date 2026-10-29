#import "Core/SGCore.h"
#import "Sing.h"
#import "Shared/Sing/SGSingController.h"

void SGRSingApplySwitch(void) {
    if (!SGRedesignedUI()) return;
    SGSingConfigure(SGFlag(SGRKeySing, NO));
}

%ctor {
    if (!SGRedesignedUI()) return;
    dispatch_async(dispatch_get_main_queue(), ^{ SGRSingApplySwitch(); });
}
