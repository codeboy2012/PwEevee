#import <UIKit/UIKit.h>

#define SGKeyOnboardingSeen @"spotifyglass.onboarding.seen"

// Presents the tour over the top of the app; does nothing while it is already up.
void SGShowOnboarding(void);
BOOL SGOnboardingShowing(void);
