// The player's settings that do not depend on the look: the Lock Screen page and its flags.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "PlayerSettings.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"

UIViewController *SGLockScreenSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Lock Screen" intro:SGRestartNote sections:@[
        SGSection(@"Controls", @[
            SGFlagRow(@"Like and dislike buttons", @"ios-feature-lockscreen.like_dislike_enabled"),
        ]),
        SGSection(@"Full-screen artwork", SGLockScreenMotionRows()),
    ] footer:nil];
}
