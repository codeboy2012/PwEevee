// AirPods gestures: CMHeadphoneMotionManager's attitudes fed to SGHeadDetector while the switch is on and
// Spotify plays, or while the page records, tries or holds the motion, and each gesture's action done to
// Spotify's player. The same manager's motion goes to the features listening through SGHeadMotionListen
// (Sing's spatial voice), and keeps running for them with the switch off; the detector is fed only while
// the gestures want it.
//
// The actions are the player's own commands (Headers/SPTPlayer.h) on SGKaraokePlayer, the ones the Live
// Activity's control menu sends: seekTo:, pause: and resume:, skipToNextTrackWithOptions: and
// skipToPreviousTrackWithOptions:, setShufflingContext:, and setRepeatingContext: with setRepeatingTrack:.
// Like adds the playing track to the collection, which for a track is Liked Songs, through
// -addURL:showUIConfirmation:completion: of Spotify's collection platform. Spotify 9.1.78 has four classes
// with that selector and with -stateProvider (SPTCollectionPlatformImplementation, Collection_PlatformImpl's
// CollectionPlatformImpl and CollectionPlatformMigration, AlignedCuration's ACUCollectionPlatform);
// whichever the app last reached for is kept, weakly, the way Redesigned/Artist/ArtistFollow.x keeps its
// state provider. The lock screen's like (LockScreenBaseRemoteControlPolicy's
// likeButtonPressedWithCompletion:identifier:) is not used: it toggles, and a second nod would take the
// song out again.
//
// The gestures listen while Spotify plays, and while a track is loaded and paused too when one of them is
// set to Play or pause, which could not resume otherwise.
//
// The cue is a tone played through Spotify's own playback session, mixed into the music in the AirPods:
// a system sound would follow the Ring/Silent switch, and a phone in a pocket is often on silent. A rising
// pair says the gesture was done, one low tone that it failed, and a single middle one is the teaching
// sheet's signal to move. A haptic comes with it while Spotify is in front, and Spotify's own "Added to
// Liked Songs" toast shows only then too.
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "HeadGestures.h"

@protocol SGCollectionPlatform <NSObject>
- (void)addURL:(NSURL *)url showUIConfirmation:(BOOL)show completion:(id)completion;
@end

// Tink, the passcode key's, should the cue's player not load.
static const SystemSoundID kCueSound = 1057;
// Each of the cue's tones, and how loud, of the most a sample holds; the player plays at the system volume.
static const double kToneSeconds = 0.09;
static const double kToneLevel = 0.5;
static const double kMilli = 1000;
static const double kSeekSeconds = 15;

static CMHeadphoneMotionManager *sg_manager;
static NSOperationQueue *sg_queue;   // serial: the detector, the recording and the queue's copies live on it alone
static SGHeadDetector sg_detector;
static NSMutableData *sg_recorded;   // a recording's samples, three doubles each
static NSInteger sg_queueHeard;      // samples the detector was fed since a try started
static BOOL sg_recording, sg_trying, sg_held;
static void (^sg_tryDone)(SGHeadGesture gesture, BOOL heard);
static NSUInteger sg_ticket;         // which recording or try is current: a stopped one's timer finds it moved on
static BOOL sg_listening;            // started with the handler, by updateListening
static BOOL sg_detecting;            // the gestures want the motion: the page's listening, or the switch on and Spotify playing
static BOOL sg_queueDetecting;       // sg_detecting, on sg_queue
static NSMutableDictionary<NSString *, void (^)(CMDeviceMotion *)> *sg_listeners;   // other features', by name
static NSArray<void (^)(CMDeviceMotion *)> *sg_queueListeners;                     // their handlers, on sg_queue
static __weak id sg_platform;

#pragma mark - the collection platform

// Spotify's platforms wrap one another, so the one kept can change often: logged once per class.
static void keepPlatform(id platform) {
    if (platform == sg_platform || ![platform respondsToSelector:@selector(addURL:showUIConfirmation:completion:)]) return;
    NSString *name = NSStringFromClass([platform class]);
    static NSMutableSet<NSString *> *logged;
    // Spotify asks for its state provider from any thread.
    @synchronized (NSObject.class) {
        sg_platform = platform;
        if (!logged) logged = [NSMutableSet set];
        if ([logged containsObject:name]) return;
        [logged addObject:name];
    }
    SGLog(@"head gestures: collection platform %@", name);
}

%hook SPTCollectionPlatformImplementation
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%hook _TtC23Collection_PlatformImpl22CollectionPlatformImpl
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%hook _TtC23Collection_PlatformImpl27CollectionPlatformMigration
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

%hook _TtC26AlignedCuration_CommonImpl21ACUCollectionPlatform
- (id)stateProvider {
    keepPlatform(self);
    return %orig;
}
%end

#pragma mark - the cue

// A WAV in memory of short tones one after the other, each faded in and out so it does not click.
static NSData *tones(NSArray<NSNumber *> *hertz) {
    const uint32_t rate = 44100, perTone = (uint32_t)(rate * kToneSeconds), frames = perTone * (uint32_t)hertz.count;
    NSMutableData *wav = [NSMutableData dataWithLength:44 + frames * sizeof(int16_t)];
    uint8_t *header = wav.mutableBytes;
    // RIFF, then the format chunk (PCM, one channel, 16-bit) and the data chunk; arm64 is little-endian, as WAV is.
    uint32_t words[] = {0x46464952, 36 + frames * 2, 0x45564157, 0x20746d66, 16, 1 | 1 << 16, rate, rate * 2, 2 | 16 << 16,
                        0x61746164, frames * 2};
    memcpy(header, words, sizeof words);
    int16_t *samples = (int16_t *)(header + 44);
    for (NSUInteger tone = 0; tone < hertz.count; tone++) {
        for (uint32_t i = 0; i < perTone; i++) {
            double envelope = sin(M_PI * i / perTone);
            samples[tone * perTone + i] = (int16_t)(kToneLevel * INT16_MAX * envelope * sin(2 * M_PI * hertz[tone].doubleValue * i / rate));
        }
    }
    return wav;
}

// The cue's players live on a queue of their own: loading and starting one goes through the audio
// session, which can hold the main thread up for a moment.
static dispatch_queue_t cueQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.headgestures.cue", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// The middle tone, the rising pair and the low tone, in SGHeadCue's order. On cueQueue only.
static AVAudioPlayer *cuePlayer(SGHeadCue cue) {
    static AVAudioPlayer *players[3];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSArray<NSNumber *> *> *sounds = @[@[@660], @[@880, @1320], @[@330]];
        for (NSUInteger i = 0; i < sounds.count; i++) {
            NSError *error = nil;
            players[i] = [[AVAudioPlayer alloc] initWithData:tones(sounds[i]) error:&error];
            if (!players[i]) SGLog(@"head gestures: no cue player, the system sound instead: %@", error);
            [players[i] prepareToPlay];
        }
    });
    return players[cue];
}

void SGHeadGesturesCue(SGHeadCue cue) {
    dispatch_async(cueQueue(), ^{
        AVAudioPlayer *player = cuePlayer(cue);
        player.currentTime = 0;
        if (![player play]) AudioServicesPlaySystemSound(kCueSound);
    });
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (cue == SGHeadCueReady) {
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        return;
    }
    UINotificationFeedbackGenerator *generator = [UINotificationFeedbackGenerator new];
    [generator notificationOccurred:cue == SGHeadCueWorked ? UINotificationFeedbackTypeSuccess : UINotificationFeedbackTypeError];
}

#pragma mark - the actions

SGHeadAction SGHeadGestureAction(SGHeadGesture gesture) {
    BOOL nod = gesture == SGHeadGestureDoubleNod;
    NSInteger action = SGInt(nod ? SGKeyHeadNodAction : SGKeyHeadShakeAction, nod ? SGHeadActionLike : SGHeadActionNext);
    return action >= 0 && action < SGHeadActionCount ? action : SGHeadActionNothing;
}

void SGSetHeadGestureAction(SGHeadGesture gesture, SGHeadAction action) {
    SGSetInt(gesture == SGHeadGestureDoubleNod ? SGKeyHeadNodAction : SGKeyHeadShakeAction, action);
    SGHeadGesturesSettingsChanged();
}

BOOL SGLikePlayingTrack(void) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    id platform = sg_platform;
    // Only a track: an episode is saved another way, and an ad is nothing to save.
    if (![uri hasPrefix:@"spotify:track:"] || !platform) {
        SGLog(@"head gestures: no like for %@, platform %@", uri, platform);
        return NO;
    }
    BOOL inFront = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    // A block that reads no arguments: whatever the completion is called with, it is safe to ignore.
    [(id<SGCollectionPlatform>)platform addURL:[NSURL URLWithString:uri] showUIConfirmation:inFront completion:^{
        SGLog(@"head gestures: liked %@", uri);
    }];
    return YES;
}

// Whether it was sent: the player answers later, if at all.
static BOOL perform(SGHeadAction action) {
    if (action == SGHeadActionLike) return SGLikePlayingTrack();
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = [player respondsToSelector:@selector(state)] ? player.state : nil;
    if (!state) {
        SGLog(@"head gestures: no player for action %ld", (long)action);
        return NO;
    }
    switch (action) {
        case SGHeadActionSeekBack:
        case SGHeadActionSeekForward: {
            // A paused state's position would run on from when it was made; positionAsOfTimestamp holds still.
            double at = state.isPaused ? state.positionAsOfTimestamp : state.position;
            double to = at + (action == SGHeadActionSeekBack ? -kSeekSeconds : kSeekSeconds);
            if (state.duration > 0) to = MIN(to, state.duration);
            [player seekTo:MAX(0, to)];
            return YES;
        }
        case SGHeadActionPlayPause:
            if (state.isPaused) [player resume:nil];
            else [player pause:nil];
            return YES;
        case SGHeadActionNext:
            [player skipToNextTrackWithOptions:nil];
            return YES;
        case SGHeadActionPrevious:
            [player skipToPreviousTrackWithOptions:nil];
            return YES;
        case SGHeadActionShuffle:
            [player setShufflingContext:!state.options.shufflingContext];
            return YES;
        case SGHeadActionRepeat:
            // Off, then the playlist or album, then the track, then off again, the way Spotify's button goes.
            if (state.options.repeatingTrack) {
                [player setRepeatingTrack:NO];
                [player setRepeatingContext:NO];
            } else if (state.options.repeatingContext) {
                [player setRepeatingTrack:YES];
            } else {
                [player setRepeatingContext:YES];
            }
            return YES;
        default:
            return NO;
    }
}

// What learning stored for `key`, or the detector's default.
static double learnedOr(NSString *key, double fallback) {
    NSInteger learned = SGInt(key, 0);
    return learned > 0 ? learned / kMilli : fallback;
}

static double threshold(NSString *key, double fallback) {
    double sensitivity = MAX(SGHeadSensitivityMin, MIN(SGHeadSensitivityMax, SGInt(SGKeyHeadSensitivity, 100))) / 100.0;
    return learnedOr(key, fallback) / sensitivity;
}

// The other gesture's threshold, as set now at a sensitivity of 100%: what learning `axis` checks with.
static double otherThreshold(SGHeadAxis axis) {
    return axis == SGHeadAxisPitch ? learnedOr(SGKeyHeadShake, SGHeadDefaultShake) : learnedOr(SGKeyHeadNod, SGHeadDefaultNod);
}

#pragma mark - listening

// Nil to the other features' handlers: the motion has stopped. On sg_queue.
static void motionStopped(void) {
    for (void (^handler)(CMDeviceMotion *) in sg_queueListeners) handler(nil);
}

static void endTry(NSUInteger ticket, SGHeadGesture gesture, BOOL heard);

static void sample(CMDeviceMotion *motion) {
    for (void (^handler)(CMDeviceMotion *) in sg_queueListeners) handler(motion);
    double time = motion.timestamp, pitch = motion.attitude.pitch, yaw = motion.attitude.yaw;
    if (sg_recorded) {
        double values[3] = {time, pitch, yaw};
        [sg_recorded appendBytes:values length:sizeof values];
        return;
    }
    // Running for another feature alone, the gestures off or Spotify paused: no gestures.
    if (!sg_queueDetecting) return;
    sg_queueHeard++;
    SGHeadGesture gesture = SGHeadDetectorFeed(&sg_detector, time, pitch, yaw);
    if (gesture == SGHeadGestureNone) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SGLog(@"head gestures: %@", gesture == SGHeadGestureDoubleNod ? @"double nod" : @"shake");
        if (sg_trying) {
            endTry(sg_ticket, gesture, YES);
            return;
        }
        if (sg_recording || sg_held || !SGFlag(SGKeyHeadGestures, NO)) return;
        SGHeadAction action = SGHeadGestureAction(gesture);
        if (action == SGHeadActionNothing) return;
        SGHeadGesturesCue(perform(action) ? SGHeadCueWorked : SGHeadCueFailed);
    });
}

// The headphones taken out or off: the listeners hear that their motion stopped. Called on the queue the motion
// comes on.
@interface SGHeadMotionDelegate : NSObject <CMHeadphoneMotionManagerDelegate>
@end

@implementation SGHeadMotionDelegate
- (void)headphoneMotionManagerDidDisconnect:(CMHeadphoneMotionManager *)manager {
    [sg_queue addOperationWithBlock:^{ motionStopped(); }];
}
@end

static CMHeadphoneMotionManager *manager(void) {
    static SGHeadMotionDelegate *delegate;   // the manager holds its delegate weakly
    if (!sg_manager) {
        sg_manager = [CMHeadphoneMotionManager new];
        sg_queue = [NSOperationQueue new];
        sg_queue.maxConcurrentOperationCount = 1;
        sg_queue.qualityOfService = NSQualityOfServiceUserInitiated;
        delegate = [SGHeadMotionDelegate new];
        sg_manager.delegate = delegate;
    }
    return sg_manager;
}

// A fresh detector at the thresholds set now.
static void resetDetector(void) {
    double nod = threshold(SGKeyHeadNod, SGHeadDefaultNod), shake = threshold(SGKeyHeadShake, SGHeadDefaultShake);
    [sg_queue addOperationWithBlock:^{ SGHeadDetectorReset(&sg_detector, nod, shake); }];
}

// The gestures want the motion while the page listens or holds it, or while the switch is on and Spotify
// plays (or has a track paused, for Play or pause); the manager runs then and while another feature listens.
// It sends nothing until headphones that track motion are in, so starting it with none costs nothing.
static void updateListening(void) {
    // isPlaying stays on while a track is loaded and paused; isPaused is what tells.
    SPTPlayerState *state = SGPlayerState();
    BOOL resumes = SGHeadGestureAction(SGHeadGestureDoubleNod) == SGHeadActionPlayPause
                   || SGHeadGestureAction(SGHeadGestureShake) == SGHeadActionPlayPause;
    BOOL wanted = state.isPlaying && (!state.isPaused || resumes);
    BOOL detect = sg_recording || sg_trying || sg_held || (SGFlag(SGKeyHeadGestures, NO) && wanted);
    if (detect != sg_detecting) {
        sg_detecting = detect;
        manager();
        if (detect) {
            resetDetector();
            // Loaded now rather than with the first gesture's cue, which then plays on time.
            dispatch_async(cueQueue(), ^{ cuePlayer(SGHeadCueWorked); });
        }
        [sg_queue addOperationWithBlock:^{ sg_queueDetecting = detect; }];
    }
    BOOL listen = detect || sg_listeners.count;
    if (listen == sg_listening) return;
    sg_listening = listen;
    SGLog(@"head gestures: %@", listen ? @"listening" : @"stopped");
    if (!listen) {
        [sg_manager stopDeviceMotionUpdates];
        return;
    }
    [sg_manager startDeviceMotionUpdatesToQueue:sg_queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (motion) sample(motion);
    }];
}

void SGHeadMotionListen(NSString *name, void (^handler)(CMDeviceMotion *motion)) {
    if (!sg_listeners) sg_listeners = [NSMutableDictionary dictionary];
    void (^old)(CMDeviceMotion *) = sg_listeners[name];
    if (!old && !handler) return;
    sg_listeners[name] = [handler copy];
    manager();
    NSArray<void (^)(CMDeviceMotion *)> *handlers = sg_listeners.allValues;
    [sg_queue addOperationWithBlock:^{
        sg_queueListeners = handlers;
        if (old) old(nil);
    }];
    updateListening();
}

void SGHeadMotionAskPermission(void) {
    // Motion's permission is asked the first time the manager starts. With nothing playing that would be the
    // first song, maybe from the lock screen, so a page asks while it is in front.
    if (sg_listening || CMHeadphoneMotionManager.authorizationStatus != CMAuthorizationStatusNotDetermined) return;
    [manager() startDeviceMotionUpdates];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!sg_listening) [sg_manager stopDeviceMotionUpdates];
    });
}

void SGHeadGesturesSettingsChanged(void) {
    if (sg_manager) resetDetector();
    updateListening();
    if (SGFlag(SGKeyHeadGestures, NO)) SGHeadMotionAskPermission();
}

BOOL SGHeadGesturesAvailable(void) {
    return manager().deviceMotionAvailable;
}

NSString *SGHeadGestureStatus(void) {
    if (!SGFlag(SGKeyHeadGestures, NO)) return @"Off";
    if (!SGHeadGesturesAvailable()) return @"This iPhone cannot track AirPods motion";
    switch (CMHeadphoneMotionManager.authorizationStatus) {
        case CMAuthorizationStatusDenied:
            return @"Turn on Motion & Fitness for Spotify in Settings";
        case CMAuthorizationStatusRestricted:
            return @"Motion & Fitness is restricted on this iPhone";
        case CMAuthorizationStatusNotDetermined:
            return @"Waiting for Motion & Fitness access";
        case CMAuthorizationStatusAuthorized:
            break;
    }
    return @"Listening for a nod or a shake";
}

#pragma mark - the page's listening

void SGHeadGesturesStopListening(void) {
    if (!sg_recording && !sg_trying) return;
    sg_recording = sg_trying = NO;
    sg_tryDone = nil;
    sg_ticket++;
    [sg_queue addOperationWithBlock:^{ sg_recorded = nil; }];
    SGLog(@"head gestures: the page's listening stopped");
    SGHeadGesturesSettingsChanged();
}

void SGHeadGesturesHold(BOOL hold) {
    if (hold == sg_held) return;
    sg_held = hold;
    manager();
    SGHeadGesturesSettingsChanged();
}

void SGHeadGesturesRecord(double seconds, void (^done)(NSData *motion)) {
    SGHeadGesturesStopListening();
    sg_recording = YES;
    NSUInteger ticket = ++sg_ticket;
    manager();
    [sg_queue addOperationWithBlock:^{ sg_recorded = [NSMutableData data]; }];
    SGHeadGesturesSettingsChanged();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ticket != sg_ticket) return;
        [sg_queue addOperationWithBlock:^{
            NSData *motion = sg_recorded ?: [NSData data];
            sg_recorded = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (ticket != sg_ticket) return;
                sg_recording = NO;
                SGHeadGesturesSettingsChanged();
                done(motion);
            });
        }];
    });
}

static void endTry(NSUInteger ticket, SGHeadGesture gesture, BOOL heard) {
    if (!sg_trying || ticket != sg_ticket) return;
    void (^done)(SGHeadGesture, BOOL) = sg_tryDone;
    sg_trying = NO;
    sg_tryDone = nil;
    sg_ticket++;
    SGHeadGesturesSettingsChanged();
    done(gesture, heard);
}

void SGHeadGesturesTry(double seconds, void (^done)(SGHeadGesture gesture, BOOL heard)) {
    SGHeadGesturesStopListening();
    sg_trying = YES;
    sg_tryDone = [done copy];
    NSUInteger ticket = ++sg_ticket;
    manager();
    [sg_queue addOperationWithBlock:^{ sg_queueHeard = 0; }];
    // A fresh detector, at the thresholds and sensitivity set now, even if the gestures were listening already.
    SGHeadGesturesSettingsChanged();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (ticket != sg_ticket) return;
        [sg_queue addOperationWithBlock:^{
            BOOL heard = sg_queueHeard > 0;
            dispatch_async(dispatch_get_main_queue(), ^{ endTry(ticket, SGHeadGestureNone, heard); });
        }];
    });
}

#pragma mark - learning

// A recording's samples as the detector's three arrays, in one buffer: free the time's.
static SGHeadRecording unpack(NSData *motion) {
    int count = (int)(motion.length / (3 * sizeof(double)));
    const double *values = motion.bytes;
    double *buffer = malloc(sizeof(double) * 3 * MAX(count, 1));
    for (int i = 0; i < count; i++) {
        buffer[i] = values[3 * i];
        buffer[count + i] = values[3 * i + 1];
        buffer[2 * count + i] = values[3 * i + 2];
    }
    return (SGHeadRecording){buffer, buffer + count, buffer + 2 * count, count};
}

double SGHeadGesturesSampleThreshold(NSData *motion, SGHeadAxis axis) {
    SGHeadRecording recording = unpack(motion);
    double learned = SGHeadLearn(recording.time, recording.pitch, recording.yaw, recording.count, axis, otherThreshold(axis));
    free((void *)recording.time);
    return learned;
}

double SGHeadGesturesLearnFrom(NSArray<NSData *> *motions, SGHeadAxis axis) {
    int n = (int)motions.count;
    SGHeadRecording *recordings = calloc(MAX(n, 1), sizeof *recordings);
    for (int i = 0; i < n; i++) recordings[i] = unpack(motions[i]);
    double learned = SGHeadLearnSamples(recordings, n, axis, otherThreshold(axis), MAX(1, n - 1));
    for (int i = 0; i < n; i++) free((void *)recordings[i].time);
    free(recordings);
    SGLog(@"head gestures: learned %.2f rad/s for %@ from %d recordings", learned, axis == SGHeadAxisPitch ? @"nod" : @"shake", n);
    if (learned > 0) {
        SGSetInt(axis == SGHeadAxisPitch ? SGKeyHeadNod : SGKeyHeadShake, lround(learned * kMilli));
        SGHeadGesturesSettingsChanged();
    }
    return learned;
}

// Playing or not, from the one player hook every feature shares.
@interface SGHeadGesturesObserver : NSObject <SGPlayerStateObserver>
@end

@implementation SGHeadGesturesObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {
    updateListening();
}
@end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTCollectionPlatformImplementation", @"_TtC23Collection_PlatformImpl22CollectionPlatformImpl"]);
    static SGHeadGesturesObserver *observer;
    observer = [SGHeadGesturesObserver new];
    SGAddPlayerStateObserver(observer);
}
