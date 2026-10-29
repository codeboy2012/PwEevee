#import <Foundation/Foundation.h>

@interface SPTPlayerTrack : NSObject
@property (nonatomic, readonly) id URI;
@property (nonatomic, readonly) id artistURI;
@property (nonatomic, readonly) NSString *artistName;
@property (nonatomic, readonly) NSString *trackTitle;
// Who the track came from (Spotify's own, a hand-queued track, autoplay); read defensively, it can be absent.
@property (nonatomic, readonly) NSString *provider;
// Every credited artist: artist_uri and artist_name, then artist_uri:1, artist_name:1 and on.
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *metadata;
@end

@interface SPTPlayerOptions : NSObject
@property (nonatomic, readonly) BOOL shufflingContext;
@property (nonatomic, readonly) BOOL repeatingContext;
@property (nonatomic, readonly) BOOL repeatingTrack;
@end

// Spotify's own sleep timer, read off the player's state (its ⋯ menu sets it; the core pauses at its end).
// type: 1 for a time (timestamp), 2 for the end of the track.
@interface SPTSleepTimer : NSObject
@property (nonatomic, readonly) NSUInteger type;
@property (nonatomic, readonly) NSDate *timestamp;
@end

@interface SPTPlayerState : NSObject
@property (nonatomic, readonly) SPTPlayerTrack *track;
@property (nonatomic, readonly) id contextURI;
@property (nonatomic, readonly) SPTPlayerOptions *options;
@property (nonatomic, readonly) BOOL isPaused;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) BOOL isLoading;
// Spotify's own sleep timer, nil when none is set; read only, its fade is the mod's (SpotifySleepTimer.m).
@property (nonatomic, readonly) SPTSleepTimer *sleepTimer;
// Seconds. position runs on from positionAsOfTimestamp by the time elapsed since the state was made.
@property (nonatomic, readonly) double position;
@property (nonatomic, readonly) double positionAsOfTimestamp;
// The track's length, in the same unit as position.
@property (nonatomic, readonly) double duration;
// How fast position advances, 1 at normal speed; SpeedPitch adjusts it by the mod's own speed (Shared/Player/SpeedPitch.x).
@property (nonatomic, readonly) double playbackSpeed;
// The tracks to come and the ones played, nearest first; SPTPlayerTrack each, read with a type check.
@property (nonatomic, readonly) NSArray *future;
@property (nonatomic, readonly) NSArray *reverse;
@end

@protocol SPTPlayer <NSObject>
@property (nonatomic, readonly) SPTPlayerState *state;
- (void)addPlayerObserver:(id)observer;
- (void)skipToNextTrack;
- (void)seekTo:(double)seconds;
- (id)pause:(id)options;
- (id)resume:(id)options;
- (id)skipToNextTrackWithOptions:(id)options;
- (id)skipToPreviousTrackWithOptions:(id)options;
// Skips ahead to `track`, one of the state's future tracks.
- (id)skipToNextTrackWithOptions:(id)options track:(SPTPlayerTrack *)track;
- (id)setShufflingContext:(BOOL)on;
- (id)setRepeatingContext:(BOOL)on;
- (id)setRepeatingTrack:(BOOL)on;
@end
