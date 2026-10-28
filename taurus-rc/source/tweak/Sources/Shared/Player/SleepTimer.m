// The sleep timer (SleepTimer.h): a check four times a second while one is set, which fades the gain over
// the last seconds (the Fade out choice) and pauses once it is up.
//
// The end of the album is read from the player's tracks to come: SPTPlayerTrack's provider (a property
// with its own ivar in the binary, beside albumURI and contextSource) and the metadata keys is_queued and
// autoplay.is_autoplay (strings in the binary) tell a track queued by hand or picked by autoplay from one
// of the album or playlist. What they read on a real queue is logged once each time the mode is set.
#import "Core/SGLog.h"
#import "Core/SGPrefs.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Player/SleepTimer.h"

static const NSTimeInterval kCheckEvery = 0.25;
// The end of track and end of album timers pause this close to the end, so the next track never starts.
static const NSTimeInterval kBeforeEnd = 0.5;
// The fade's depth: 60 dB down is as good as silent, and the pause takes it from there.
static const float kFadeDecibels = 60;
// The Fade out choices, by index, and the one unless another is picked.
static const NSTimeInterval kFades[] = {0, 10, 30, 60, 120};
static const NSInteger kFadeDefault = 2;
// The gain goes back to normal this long after the pause, once what was still on its way out has played.
static const NSTimeInterval kRestoreAfter = 1;

static SGSleepTimerMode sg_mode;
static NSDate *sg_end;
// The track and the context playing when it was set, by URI.
static NSString *sg_track, *sg_context;
static NSTimer *sg_timer;
// Whether this timer's fade has started, so the log says so once.
static BOOL sg_fading;

NSArray<NSString *> *SGSleepTimerFadeNames(void) {
    return @[@"Off", @"10 s", @"30 s", @"1 minute", @"2 minutes"];
}

NSInteger SGSleepTimerFadeChoice(void) {
    NSInteger index = SGInt(SGKeySleepTimerFade, kFadeDefault);
    return index >= 0 && index < (NSInteger)(sizeof kFades / sizeof *kFades) ? index : kFadeDefault;
}

NSTimeInterval SGSleepTimerFade(void) {
    return kFades[SGSleepTimerFadeChoice()];
}

SGSleepTimerMode SGSleepTimerCurrentMode(void) {
    return sg_mode;
}

NSDate *SGSleepTimerEnd(void) {
    return sg_mode == SGSleepTimerAtTime ? sg_end : nil;
}

float SGSleepTimerGain(NSTimeInterval left, NSTimeInterval fade) {
    if (fade <= 0 || left >= fade) return 1;
    return powf(10, -kFadeDecibels / 20 * (float)(1 - MAX(left, 0) / fade));
}

static BOOL metadataSays(SPTPlayerTrack *track, NSString *key) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    return [metadata isKindOfClass:NSDictionary.class] && [[metadata[key] description] isEqualToString:@"true"];
}

static NSString *providerOf(SPTPlayerTrack *track) {
    NSString *provider = [track respondsToSelector:@selector(provider)] ? track.provider : nil;
    return [provider isKindOfClass:NSString.class] ? provider : nil;
}

static BOOL isAutoplay(SPTPlayerTrack *track) {
    return [providerOf(track) isEqualToString:@"autoplay"] || metadataSays(track, @"autoplay.is_autoplay");
}

// A track of the album or playlist itself, not one queued by hand or picked by autoplay.
static BOOL isContextTrack(id track) {
    if (![track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] || !SGURIString([(SPTPlayerTrack *)track URI])) return NO;
    return ![providerOf(track) isEqualToString:@"queue"] && !metadataSays(track, @"is_queued") && !isAutoplay(track);
}

BOOL SGSleepTimerOnLastOfContext(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    SPTPlayerTrack *next = nil;
    for (id track in [future isKindOfClass:NSArray.class] ? future : @[]) {
        if (isContextTrack(track)) { next = track; break; }
    }
    if (!next) return YES;
    // Repeating, the album comes round again: the next track is this one or one already played.
    if (!state.options.repeatingContext) return NO;
    NSString *uri = SGURIString(next.URI);
    if ([uri isEqualToString:SGURIString(state.track.URI)]) return YES;
    id reverse = [state respondsToSelector:@selector(reverse)] ? state.reverse : nil;
    for (id track in [reverse isKindOfClass:NSArray.class] ? reverse : @[]) {
        if ([track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] && [SGURIString([(SPTPlayerTrack *)track URI]) isEqualToString:uri]) return YES;
    }
    return NO;
}

NSTimeInterval SGSleepTimerTrackLeft(SPTPlayerState *state) {
    double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
    NSInteger position = SGKaraokePositionMs();
    return duration > 0 && position >= 0 ? MAX(0, duration - position / 1000.0) : -1;
}

static void stopChecking(void) {
    [sg_timer invalidate];
    sg_timer = nil;
    sg_mode = SGSleepTimerOff;
    sg_end = nil;
    sg_track = nil;
    sg_context = nil;
    sg_fading = NO;
}

// Seconds until the pause, or -1 when it is not in sight yet (a track whose length is not known, or the
// album still has tracks to go); 0 to pause now.
static NSTimeInterval secondsLeft(SPTPlayerState *state) {
    NSString *track = SGURIString(state.track.URI);
    switch (sg_mode) {
        case SGSleepTimerAtTime:
            return MAX(0, sg_end.timeIntervalSinceNow);
        case SGSleepTimerEndOfTrack:
            // On the next track already, should the length not have been known.
            return [track isEqualToString:sg_track] ? SGSleepTimerTrackLeft(state) : 0;
        case SGSleepTimerEndOfAlbum: {
            NSString *context = SGURIString(state.contextURI);
            if (!(context == sg_context || [context isEqualToString:sg_context]) || isAutoplay(state.track)) return 0;
            return SGSleepTimerOnLastOfContext(state) ? SGSleepTimerTrackLeft(state) : -1;
        }
        default:
            return -1;
    }
}

static void check(void) {
    if (sg_mode == SGSleepTimerOff) return;
    id<SPTPlayer> player = SGKaraokePlayer();
    SPTPlayerState *state = player.state;
    NSTimeInterval left = secondsLeft(state);
    BOOL up = left >= 0 && (sg_mode == SGSleepTimerAtTime ? left <= 0 : left < kBeforeEnd);
    if (!up) {
        NSTimeInterval fade = SGSleepTimerFade();
        // At the end of a track shorter than the fade, the fade starts with the track.
        double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
        if (sg_mode != SGSleepTimerAtTime && duration > 0) fade = MIN(fade, duration);
        float gain = left >= 0 ? SGSleepTimerGain(left, fade) : 1;
        if (gain < 1 && !sg_fading) {
            sg_fading = YES;
            SGLog(@"sleep timer: fading over %.0f s, %.1f s left (mode %ld, track %.1f s, at %ld ms)", fade, left, (long)sg_mode,
                  duration, (long)SGKaraokePositionMs());
        }
        SGPlayerSetGain(gain);
        return;
    }
    SGSleepTimerMode mode = sg_mode;
    stopChecking();
    if (!state.isPaused) [player pause:nil];
    SGLog(@"sleep timer: up (mode %ld), %@%@", (long)mode, state.isPaused ? @"already paused" : @"paused",
          SGSleepTimerFade() > 0 ? @"" : @", no fade (Off)");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRestoreAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_mode == SGSleepTimerOff) SGPlayerSetGain(1);
    });
}

// What the tracks to come say about themselves, once per End of album, so the phone's log shows whether
// the provider and the two keys read the way SGSleepTimerOnLastOfContext expects.
static void logQueue(SPTPlayerState *state) {
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    for (id track in [future isKindOfClass:NSArray.class] ? future : @[]) {
        if (seen.count == 4) break;
        if (![track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) continue;
        [seen addObject:[NSString stringWithFormat:@"%@ provider %@ is_queued %@ autoplay %@ -> %@", [(SPTPlayerTrack *)track trackTitle],
                         providerOf(track), [(SPTPlayerTrack *)track metadata][@"is_queued"],
                         [(SPTPlayerTrack *)track metadata][@"autoplay.is_autoplay"], isContextTrack(track) ? @"album" : @"not album"]];
    }
    SGLog(@"sleep timer: end of album, context %@, playing %@ (provider %@), %lu to come, last of it %@: %@", SGURIString(state.contextURI),
          state.track.trackTitle, providerOf(state.track), (unsigned long)[future count], SGSleepTimerOnLastOfContext(state) ? @"yes" : @"no",
          [seen componentsJoinedByString:@"; "]);
}

void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {
    stopChecking();
    if (mode == SGSleepTimerOff || (mode == SGSleepTimerAtTime && seconds <= 0)) {
        SGPlayerSetGain(1);
        return;
    }
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    sg_mode = mode;
    if (mode == SGSleepTimerAtTime) sg_end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    sg_track = SGURIString(state.track.URI);
    sg_context = SGURIString(state.contextURI);
    if (mode == SGSleepTimerEndOfAlbum) logQueue(state);
    SGLog(@"sleep timer: set (mode %ld, %.0f s), fade %.0f s", (long)mode, seconds, SGSleepTimerFade());
    sg_timer = [NSTimer timerWithTimeInterval:kCheckEvery repeats:YES block:^(NSTimer *timer) { check(); }];
    [NSRunLoop.mainRunLoop addTimer:sg_timer forMode:NSRunLoopCommonModes];
    check();
}

void SGSleepTimerAdd(NSTimeInterval seconds) {
    NSDate *end = SGSleepTimerEnd();
    NSTimeInterval from = end && end.timeIntervalSinceNow > 0 ? end.timeIntervalSinceNow : 0;
    SGSetSleepTimer(SGSleepTimerAtTime, from + seconds);
}
