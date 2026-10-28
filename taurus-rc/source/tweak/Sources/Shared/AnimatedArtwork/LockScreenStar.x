// The lock screen's favorite star cycles the configured artwork views.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"

static NSString *const kLikeDislikeFlag = @"ios-feature-lockscreen.like_dislike_enabled";
static MPFeedbackCommand *sg_like;
static id sg_target;

static NSString *currentStarView(void) {
    return SGLockScreenCurrentStarView();
}

static BOOL starOn(void) {
    return SGHidden(SGKeyLockScreenStar) && SGLockScreenAvailableStarViews().count > 1;
}

static MPRemoteCommandHandlerStatus tapped(void) {
    if (!starOn()) return MPRemoteCommandHandlerStatusCommandFailed;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGLockScreenStarAdvanceView();
    });
    return MPRemoteCommandHandlerStatusSuccess;
}

static void arm(void) {
    SGLockScreenStarEnsureView();
    static BOOL lastOn, lastActive;
    BOOL on = starOn(), active = on && [currentStarView() isEqualToString:@"lyrics"];
    if (sg_like && !sg_like.enabled) sg_like.enabled = YES;
    if (on == lastOn && active == lastActive && on == (sg_like != nil)) return;
    lastOn = on;
    lastActive = active;
    if (!on && !sg_like) return;
    MPFeedbackCommand *like = MPRemoteCommandCenter.sharedCommandCenter.likeCommand;
    if (!on) {
        [like removeTarget:sg_target];
        sg_target = nil;
        sg_like = nil;
        like.enabled = NO;
        like.active = NO;
        SGLog(@"lock star: off");
        return;
    }
    if (!sg_like) {
        [like removeTarget:nil];
        sg_target = [like addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) { return tapped(); }];
        like.localizedTitle = @"Cycle lock-screen artwork";
        sg_like = like;
    }
    like.enabled = YES;
    like.active = active;
}

%hook MPRemoteCommand
- (void)setEnabled:(BOOL)enabled {
    if (!enabled && sg_like && self == sg_like) enabled = YES;
    %orig(enabled);
}

- (void)removeTarget:(id)target {
    if (sg_like && self == sg_like && target != sg_target && !target) sg_like = nil;
    %orig;
}
%end

@interface SGLockScreenStar : NSObject <SGPlayerStateObserver>
@end

@implementation SGLockScreenStar
- (void)playerStateDidChange:(SPTPlayerState *)state {
    arm();
}
@end

%ctor {
    if (@available(iOS 26.0, *)) {
        BOOL atLaunch = starOn();
        SGRegisterFlagForcer(YES, ^id(NSString *key) {
            return atLaunch && [key isEqualToString:kLikeDislikeFlag] ? @NO : nil;
        }, ^id(NSString *key) {
            return starOn() && [key isEqualToString:kLikeDislikeFlag] ? @NO : nil;
        });
        %init;
        static SGLockScreenStar *observer;
        observer = [SGLockScreenStar new];
        SGAddPlayerStateObserver(observer);
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ arm(); });
        }];
        SGLog(@"lock star: %@", atLaunch ? @"on" : @"off");
    }
}
