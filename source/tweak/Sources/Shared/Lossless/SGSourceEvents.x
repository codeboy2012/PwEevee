// Application discontinuities invalidate the source selector's epoch, so a lossless anchor stops at once. Runs
// with lossless on, and in driver (FLEX) builds, whose anchor log records these events.
#import "Core/SGCore.h"
#import "SGLossless.h"
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Sing/SGSingController.h"
#import "SGAnchor.h"

static void event(NSString *kind, NSString *evidence) {
    SGPlayerInvalidateSource();
    uint64_t epoch = SGPlayerSourceEpoch(), host = mach_absolute_time();
    dispatch_block_t log = ^{ SGAnchorLog(kind, evidence, epoch, host); };
    if (NSThread.isMainThread) log();
    else dispatch_async(dispatch_get_main_queue(), log);
}

@interface SGSourceEvents : NSObject <SGPlayerStateObserver>
@end
@implementation SGSourceEvents {
    NSString *_track;
    BOOL _known, _paused, _playing;
    double _position, _duration, _at, _speed;
}
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI) ?: @"-";
    double now = NSProcessInfo.processInfo.systemUptime;
    double position = SGSingSourcePosition(state);
    double speed = state.playbackSpeed;
    if (!_known || ![track isEqualToString:_track]) {
        event(@"track", @"reported");
    } else {
        if (state.isPaused != _paused || state.isPlaying != _playing)
            event(state.isPaused || !state.isPlaying ? @"pause" : @"resume", @"reported");
        // Commands are observed separately. This also catches remote seeks and a same-URI wrap.
        // A wrap near the end with repeat enabled is evidence of a repeat, not a recording id.
        double expected = _position + (_playing && !_paused ? (now - _at) * _speed : 0);
        if (isfinite(position) && position >= 0 && _position >= 0 && fabs(position - expected) > 0.5) {
            BOOL repeat = state.options.repeatingTrack && _duration > 0
                && expected >= _duration - 2 && position < 2 && position < _position;
            event(repeat ? @"repeat" : @"position_jump", @"inferred");
        }
    }
    _known = YES;
    _track = track;
    _paused = state.isPaused;
    _playing = state.isPlaying;
    _position = position;
    _duration = state.duration;
    _at = now;
    _speed = speed;
}
@end

// These terminal command selectors are already evidenced by Spotify's player implementation.
// Shorter seeks and skips forward here, so a single command is counted once.
%hook SPTEsperantoPlayer
- (id)seekTo:(double)position relative:(long long)relative options:(id)options creatorTimestampPositionMs:(double)creator {
    event(@"seek", @"command");
    return %orig;
}
- (id)skipToNextTrackWithOptions:(id)options track:(id)track loggingParams:(id)params {
    event(@"skip", @"next_command");
    return %orig;
}
- (id)skipToPreviousTrackWithOptions:(id)options track:(id)track loggingParams:(id)params {
    event(@"skip", @"previous_command");
    return %orig;
}
- (id)stop {
    event(@"stop", @"command");
    return %orig;
}
%end

%ctor {
    #if !SG_DRIVER
    if (!SGHidden(SGKeyLossless)) return;
    #endif
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGSourceEvents *observer;
        observer = [SGSourceEvents new];
        SGAddPlayerStateObserver(observer);
        if (SGPlayerState()) [observer playerStateDidReport:SGPlayerState()];
        static BOOL sing;
        sing = SGSingEnabled();
        [NSNotificationCenter.defaultCenter addObserverForName:SGSingDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_block_t changed = ^{
                BOOL on = SGSingEnabled();
                if (on != sing) { sing = on; event(on ? @"sing_on" : @"sing_off", @"reported"); }
            };
            if (NSThread.isMainThread) changed();
            else dispatch_async(dispatch_get_main_queue(), changed);
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            event(@"route", [NSString stringWithFormat:@"reason_%lu", (unsigned long)[note.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue]]);
        }];
    });
}
