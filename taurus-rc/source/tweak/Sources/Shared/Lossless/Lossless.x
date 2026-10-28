// Anchors the playing track's lossless file again whenever the anchor stops holding: a new track, a seek, a resume.
// Only at normal speed with Karaoke off; anything else leaves Spotify's own sound.
#import "Core/SGCore.h"
#import <objc/runtime.h>
#import "Shared/Player/PlayerState.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Player/SpeedPitch.h"
#import "SGLossless.h"
#import "SGLosslessStore.h"
#import "LosslessQuality.h"

static const int kTries = 3;            // failed anchors in a row before waiting for the next change of source
static const double kRetrySeconds = 2;

@interface SGLosslessCoordinator : NSObject <SGPlayerStateObserver>
@end

@implementation SGLosslessCoordinator {
    NSString *_track, *_path;
    BOOL _busy, _looked, _nextHas;
    NSString *_next;
    NSDate *_folderChanged;
    int _failures;
    uint64_t _gaveUpEpoch;
    double _retryAt;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self tick];
}

- (void)tick {
    SPTPlayerState *state = SGPlayerState();
    NSString *track = SGURIString(state.track.URI);
    if (![track isEqualToString:_track]) {
        if (_path) SGLosslessStop(YES);
        _track = track;
        _path = nil;
        _looked = NO;
        _failures = 0;
        _gaveUpEpoch = 0;
    }
    // A track's first report can come before its title and length: look again until both are known.
    if (track && !_looked) {
        NSString *title = state.track.trackTitle;
        _path = SGLosslessStoreFile(track, title ?: @"", state.duration);
        _looked = _path || (title.length && state.duration > 0);
        if (_looked) SGLog(@"lossless: %@ (%.1f s): %@", track, state.duration, _path.lastPathComponent ?: @"no file");
    }
    // Spotify fetches a song as it starts, so its quality is set while the one before plays.
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id upcoming = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
    SPTPlayerTrack *next = [upcoming isKindOfClass:objc_getClass("SPTPlayerTrack")] ? upcoming : nil;
    NSString *nextURI = SGURIString(next.URI);
    // Again when the folder changes: a file can arrive while the song before plays.
    NSDate *changed = [NSFileManager.defaultManager attributesOfItemAtPath:SGLosslessStoreDirectory() error:NULL].fileModificationDate;
    if (![nextURI isEqualToString:_next] || ![changed isEqualToDate:_folderChanged]) {
        _next = nextURI;
        _folderChanged = changed;
        _nextHas = nextURI && SGLosslessStoreHas(nextURI, next.trackTitle ?: @"");
    }
    SGLosslessLowerQuality(_nextHas);

    if (!_path || _busy || SGLosslessPlaying()) return;
    if (!state.isPlaying || state.isPaused || fabs(state.playbackSpeed - 1) > 0.001 || SGSingEnabled()) return;
    uint64_t epoch = SGPlayerSourceEpoch();
    if (_gaveUpEpoch && _gaveUpEpoch == epoch) return;
    double now = CFAbsoluteTimeGetCurrent();
    if (now < _retryAt) return;

    _busy = YES;
    NSString *path = _path;
    double hint = state.position;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *error;
        NSDictionary *anchored = SGLosslessAnchor(path, hint, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            if (![track isEqualToString:self->_track]) return;
            if (anchored) {
                self->_failures = 0;
                SGLosslessStoreRemember(track, path);
                SGLog(@"lossless: playing %@ from %.2f s", path.lastPathComponent, [anchored[@"file_seconds"] doubleValue]);
                return;
            }
            self->_retryAt = CFAbsoluteTimeGetCurrent() + kRetrySeconds;
            if (++self->_failures >= kTries) {
                self->_failures = 0;
                self->_gaveUpEpoch = SGPlayerSourceEpoch();
                SGLog(@"lossless: gave up on %@ until the source changes: %@", path.lastPathComponent, error);
            } else {
                SGLog(@"lossless: no anchor (%@)", error);
            }
        });
    });
}
@end

%ctor {
    if (!SGHidden(SGKeyLossless)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGLosslessCoordinator *coordinator;
        coordinator = [SGLosslessCoordinator new];
        SGAddPlayerStateObserver(coordinator);
        // Position reports are not change callbacks, and a seek or resume shows only in the source's epoch.
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [coordinator tick]; }];
    });
}
