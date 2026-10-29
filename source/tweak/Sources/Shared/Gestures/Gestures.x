#import "Core/SGCore.h"
#import "Gestures.h"
#import "Headers/SPTNowPlayingPlaybackController.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"

static __weak SPTNowPlayingPlaybackControllerImplementation *sg_player;
static void (^sg_observer)(SGGestureAction action);

static __weak id sg_auxModel;

void SGGestureSetObserver(void (^observer)(SGGestureAction action)) {
    sg_observer = [observer copy];
}

#pragma mark - what a cell does

@protocol SGAuxActions <NSObject>
- (void)addToCollection;
- (BOOL)isInCollection;
- (BOOL)disallowAddingToCollection;
@end

@protocol SGCollectableTrack <NSObject>
@property (nonatomic, readonly) BOOL isPodcast;
@property (nonatomic, readonly) BOOL isAudiobook;
@end

static void like(void) {
    id<SGAuxActions> model = sg_auxModel;
    if (![model respondsToSelector:@selector(addToCollection)]) return;
    SPTPlayerTrack *track = SGPlayerState().track;
    if (!track) return;
    if ([track respondsToSelector:@selector(isPodcast)] && [(id<SGCollectableTrack>)track isPodcast]) return;
    if ([track respondsToSelector:@selector(isAudiobook)] && [(id<SGCollectableTrack>)track isAudiobook]) return;
    if ([model isInCollection]) return;
    if ([model disallowAddingToCollection]) return;
    [model addToCollection];
}

void SGPerformGestureAction(SGGestureAction action) {
    SPTNowPlayingPlaybackControllerImplementation *player = sg_player;
    if (!player) return;
    if (action != SGGestureNothing && sg_observer) sg_observer(action);
    switch (action) {
        case SGGestureNothing:
            break;
        case SGGestureSeekBack:
            if (player.seekingAllowed) [player seekBackwardBySeconds:SGGestureStep()];
            break;
        case SGGestureSeekForward:
            if (player.seekingAllowed) [player seekForwardBySeconds:SGGestureStep()];
            break;
        case SGGesturePlayPause:
            if (player.isPaused ? !player.disallowResuming : !player.disallowPausing) {
                [player setPaused:!player.isPaused];
            }
            break;
        case SGGestureNextTrack:
            if (player.canSkipNext) [player skipToNextWhileDragging:NO];
            break;
        case SGGesturePreviousTrack:
            [player skipToPreviousWhileDragging:NO];
            break;
        case SGGestureShuffle:
            [player setGlobalShuffleMode:!player.isShuffling];
            break;
        case SGGestureRepeat:
            [player toggleRepeatMode];
            break;
        case SGGestureLike:
            like();
            break;
    }
}

#pragma mark - the recognizer

@interface SGGestureTarget : NSObject
@end

@implementation SGGestureTarget

- (void)doubleTapped:(UITapGestureRecognizer *)tap {
    if (!SGFlag(SGKeyGestures, NO)) return;
    UIView *host = tap.view;
    CGRect visible = host.bounds;
    CGPoint point = [tap locationInView:host];
    point.x -= visible.origin.x;
    point.y -= visible.origin.y;
    NSInteger cell = SGGestureCellAt(point, visible.size);
    NSArray<NSNumber *> *zones = SGGestureZones();
    if (cell < 0 || cell >= (NSInteger)zones.count) return;
    SGPerformGestureAction((SGGestureAction)zones[(NSUInteger)cell].integerValue);
}

@end

static SGGestureTarget *target(void) {
    static SGGestureTarget *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [SGGestureTarget new]; });
    return shared;
}

static void yieldSingleTaps(UIView *host, UITapGestureRecognizer *tap) {
    for (UIView *view = host; view; view = view.superview) {
        for (UIGestureRecognizer *other in view.gestureRecognizers) {
            if (other == tap || ![other isKindOfClass:UITapGestureRecognizer.class]) continue;
            if (((UITapGestureRecognizer *)other).numberOfTapsRequired != 1) continue;
            [other requireGestureRecognizerToFail:tap];
        }
    }
}

static char kTapKey, kSeenKey;

static NSUInteger tapsAbove(UIView *host) {
    NSUInteger count = 0;
    for (UIView *view = host; view; view = view.superview) count += view.gestureRecognizers.count;
    return count;
}

void SGGestureAttach(UIView *host) {
    if (!host || !SGFlag(SGKeyGestures, NO)) return;
    UITapGestureRecognizer *tap = objc_getAssociatedObject(host, &kTapKey);
    if (!tap) {
        tap = [[UITapGestureRecognizer alloc] initWithTarget:target() action:@selector(doubleTapped:)];
        tap.numberOfTapsRequired = 2;
        [host addGestureRecognizer:tap];
        objc_setAssociatedObject(host, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *seen = objc_getAssociatedObject(host, &kSeenKey);
    NSUInteger now = tapsAbove(host);
    if (seen.unsignedIntegerValue == now) return;
    objc_setAssociatedObject(host, &kSeenKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    yieldSingleTaps(host, tap);
}

#pragma mark - hooks

%hook SPTNowPlayingPlaybackControllerImplementation
- (id)initWithPlayer:(id)player testManager:(id)manager inStreamClient:(id)client {
    id controller = %orig;
    sg_player = controller;
    return controller;
}
%end

%hook SPTNowPlayingAuxiliaryActionsModel
- (id)initWithCollectionPlatform:(id)collectionPlatform testManager:(id)testManager statefulPlayer:(id)statefulPlayer yourEpisodesSaveManager:(id)saveManager curationPlatform:(id)curationPlatform smartShuffleHandler:(id)shuffleHandler playingTrackProvider:(id)provider {
    id model = %orig;
    sg_auxModel = model;
    return model;
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTNowPlayingPlaybackControllerImplementation"]);
}
