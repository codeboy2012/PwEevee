#if SG_DRIVER
#import <mach/mach_time.h>
#import "Core/SGLog.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Lyrics/Lyrics.h"
#import "SGAnchor.h"

static SGAnchorSample sg_latest;
static BOOL sg_haveSample;
static double sg_tickSeconds;
static uint64_t sg_session, sg_sequence;
static BOOL sg_enabled;

static NSString *field(NSString *value) {
    static NSCharacterSet *allowed;
    if (!allowed) allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:._-"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"-";
}

void SGAnchorLog(NSString *kind, NSString *evidence, uint64_t epoch, uint64_t host) {
    if (!sg_enabled) return;
    unsigned dropped;
    SGAnchorSample sample;
    if (SGPlayerAnchorRead(&sample, &dropped)) { sg_latest = sample; sg_haveSample = YES; }
    uint64_t before = mach_absolute_time();
    SPTPlayerState *state = SGPlayerState();
    double position = state ? (state.isPaused ? state.positionAsOfTimestamp : state.position) : -1;
    double raw = state ? SGSingSourcePosition(state) : -1;
    NSInteger karaoke = SGKaraokePositionMs();
    bool engaged;
    double latency = SGPlayerAnchorLatency(&engaged);
    uint64_t after = mach_absolute_time();
    double control = ((double)before + (double)(after - before) / 2) * sg_tickSeconds;
    double sampleTime = sg_haveSample ? sg_latest.host * sg_tickSeconds : 0;
    SGLog(@"lossless-anchor: v=1 session=%llu seq=%llu kind=%@ evidence=%@ event_host=%.6f event_epoch=%llu control_host=%.6f read_ms=%.3f epoch=%llu sample=%d sample_epoch=%llu output=%llu source_frame=%.0f frames=%u rate=%.0f host=%.6f age_ms=%.3f silent=%d status=%d dropped=%u uri=%@ karaoke_uri=%@ position_ms=%.3f raw_ms=%.3f asof_ms=%.3f stamp=%.3f karaoke_ms=%ld playing=%d paused=%d speed=%.6f pitch=%.3f follows=%d tp_engaged=%d tp_latency_ms=%.3f sing_on=%d sing_active=%d sing_state=%ld",
        (unsigned long long)sg_session, (unsigned long long)++sg_sequence, kind, evidence,
        host * sg_tickSeconds, (unsigned long long)epoch, control, (after - before) * sg_tickSeconds * 1000,
        (unsigned long long)SGPlayerSourceEpoch(), sg_haveSample, (unsigned long long)sg_latest.epoch,
        (unsigned long long)sg_latest.output, sg_latest.sourceFrame, sg_latest.frames, sg_latest.rate,
        sampleTime, sg_haveSample ? (control - sampleTime) * 1000 : -1, sg_latest.silent, sg_latest.status, dropped,
        field(SGURIString(state.track.URI)), field(SGKaraokePlayingTrack()), position * 1000, raw * 1000, state ? state.positionAsOfTimestamp * 1000 : -1,
        state.timestamp ? state.timestamp.timeIntervalSinceReferenceDate : 0, (long)karaoke,
        state.isPlaying, state.isPaused, SGPlayerSpeed(), SGPlayerPitch(), SGPlayerPitchFollowsSpeed(), engaged, latency * 1000,
        SGSingEnabled(), SGSingStateIsOn(SGSingCurrentState()), (long)SGSingCurrentState());
}

__attribute__((constructor)) static void start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // The compile flag follows FLEX packaging; the runtime check matches Sing's dev model slot.
        if (!NSClassFromString(@"FLEXManager")) return;
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        sg_tickSeconds = (double)timebase.numer / timebase.denom / 1e9;
        sg_session = mach_absolute_time();
        sg_enabled = YES;
        SGAnchorLog(@"start", @"diagnostic", SGPlayerSourceEpoch(), sg_session);
        static dispatch_source_t timer;
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_MSEC * 50);
        dispatch_source_set_event_handler(timer, ^{
            static double speed, pitch;
            static BOOL follows;
            double nextSpeed = SGPlayerSpeed(), nextPitch = SGPlayerPitch();
            BOOL nextFollows = SGPlayerPitchFollowsSpeed();
            BOOL changed = speed && (nextSpeed != speed || nextPitch != pitch || nextFollows != follows);
            speed = nextSpeed; pitch = nextPitch; follows = nextFollows;
            if (changed) SGPlayerInvalidateSource();
            SGAnchorLog(changed ? @"speed_pitch" : @"sample", changed ? @"polled" : @"timer",
                        SGPlayerSourceEpoch(), mach_absolute_time());
        });
        dispatch_resume(timer);
    });
}
#endif
