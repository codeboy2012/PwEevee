// The App Shortcuts (Siri, the Shortcuts app, the Action button): the intents in AppShortcuts.swift post one
// notification between them and this runs it against the player. The intents run in Spotify's own process,
// where the tweak is loaded, so the notification reaches it there. Main thread only.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/HeadGestures/HeadGestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/SleepTimer.h"
#import "Shared/Sing/SGSingController.h"

// Like, toggle, next, previous, sing, or sleep:<minutes>, what SGShortcutAction (AppShortcuts.swift) posts.
static void runShortcut(NSString *action) {
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@":"];
    NSString *name = parts.firstObject;
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = [player respondsToSelector:@selector(state)] ? player.state : nil;
    id result = nil;
    if ([name isEqualToString:@"like"]) {
        SGLikePlayingTrack();
    } else if ([name isEqualToString:@"toggle"]) {
        if (state) result = state.isPaused ? [player resume:nil] : [player pause:nil];
    } else if ([name isEqualToString:@"next"]) {
        if (state) result = [player skipToNextTrackWithOptions:nil];
    } else if ([name isEqualToString:@"previous"]) {
        if (state) result = [player skipToPreviousTrackWithOptions:nil];
    } else if ([name isEqualToString:@"sing"]) {
        SGSingSetEnabled(!SGSingEnabled());
    } else if ([name isEqualToString:@"sleep"]) {
        NSInteger minutes = parts.count > 1 ? parts[1].integerValue : 0;
        SGSetSleepTimer(SGSleepTimerAtTime, minutes > 0 ? minutes * 60 : 30 * 60);
    } else {
        SGLog(@"shortcut: unknown action %@", action);
        return;
    }
    SGLog(@"shortcut: %@ -> %@", action, result);
}

%ctor {
    if (@available(iOS 17.0, *)) {
        [NSNotificationCenter.defaultCenter addObserverForName:@"SGShortcutAction" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:NSString.class]) runShortcut(note.object);
        }];
    }
}
