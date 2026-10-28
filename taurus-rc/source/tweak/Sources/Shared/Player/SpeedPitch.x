#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import "Headers/SPTPlayer.h"
#import "SpeedPitch.h"
#import "SGTimePitch.h"

// The unit stays in this long after speed and pitch both came back to normal.
static const double kOffAfter = 1.5;

#pragma mark - shared between the threads

static float sg_speed = 1, sg_semitones;     // main thread
static BOOL sg_follows;                      // main thread, pitch follows speed as stored
static atomic_uint sg_speedBits;             // sg_speed for SPTPlayerState, read on any thread
static atomic_uint sg_gainBits;              // the output gain, 1 when normal, for the sleep timer's fade

static _Atomic(SGTimePitch *) sg_pull, sg_varispeed, sg_inPlace, sg_chain;
static atomic_bool sg_engaged, sg_busy;
static pthread_mutex_t sg_buildLock = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
    atomic_uint_fast64_t rateBits;
    atomic_uint flags, channels, bytes;
} Format;
static Format sg_client, sg_hardware;

static BOOL tapped(void) {
    return SGAudioPipelineTapped();
}

static float loadFloat(atomic_uint *slot) {
    uint32_t bits = atomic_load(slot);
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static void storeFloat(atomic_uint *slot, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store(slot, bits);
}

#pragma mark - the render thread: the chain

static OSStatus pullForUnit(void *context, UInt32 frames, AudioBufferList *data) {
    return SGAudioPipelinePull(frames, data, NULL);
}

static BOOL fitsUnit(const AudioBufferList *data, UInt32 frames, SGTimePitch *unit) {
    if (data->mNumberBuffers != SGTimePitchChannels(unit) || frames > kSGTimePitchMaxFrames) return NO;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * sizeof(float)) return NO;
    }
    return YES;
}

// Called only by the central pipeline, before the output-domain processors.
static bool processPull(UInt32 frames, AudioBufferList *data, OSStatus *status) {
    atomic_store(&sg_busy, true);
    SGTimePitch *unit = atomic_load(&sg_chain);
    bool handles = data && atomic_load(&sg_engaged) && unit && fitsUnit(data, frames, unit);
    if (handles) *status = SGTimePitchRender(unit, frames, data);
    // An errored render may already have pulled input. Do not pull it a second time as a fallback.
    atomic_store(&sg_busy, false);
    return handles;
}

#pragma mark - the render thread: in place, the fallback

static float sg_scratch[kSGTimePitchMaxChannels][kSGTimePitchMaxFrames];

static inline float readSample(const void *data, UInt32 index, UInt32 bytes, BOOL isFloat, UInt32 fraction) {
    if (bytes == 4) {
        if (isFloat) return ((const float *)data)[index];
        int32_t value = ((const int32_t *)data)[index];
        return fraction ? (float)((double)value / (double)(1u << fraction)) : (float)(value / 2147483648.0);
    }
    return ((const int16_t *)data)[index] / 32768.0f;
}

static inline void writeSample(void *data, UInt32 index, float value, UInt32 bytes, BOOL isFloat, UInt32 fraction) {
    if (bytes == 4 && isFloat) {
        ((float *)data)[index] = value;
        return;
    }
    value = fmaxf(-1, fminf(value, 1));
    if (bytes == 4) {
        double scale = fraction ? (double)(1u << fraction) : 2147483647.0;
        ((int32_t *)data)[index] = (int32_t)(value * scale);
    } else {
        ((int16_t *)data)[index] = (int16_t)(value * 32767);
    }
}

static void shiftInPlace(SGTimePitch *unit, AudioUnitRenderActionFlags *flags, UInt32 frames, AudioBufferList *data) {
    UInt32 formatFlags = atomic_load_explicit(&sg_hardware.flags, memory_order_relaxed);
    UInt32 bytes = atomic_load_explicit(&sg_hardware.bytes, memory_order_relaxed);
    UInt32 channels = SGTimePitchChannels(unit);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if (frames > kSGTimePitchMaxFrames || (bytes != 2 && bytes != 4)) return;
    if (split ? data->mNumberBuffers != channels : data->mNumberBuffers != 1 || data->mBuffers[0].mNumberChannels != channels) return;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * bytes * (split ? 1 : channels)) return;
    }
    // Silence still goes through, so the sound the unit holds plays out rather than coming back later.
    BOOL silent = (*flags & kAudioUnitRenderAction_OutputIsSilence) != 0;

    float *lanes[kSGTimePitchMaxChannels];
    BOOL direct = split && isFloat && bytes == 4 && !silent;
    for (UInt32 c = 0; c < channels; c++) {
        if (direct) {
            lanes[c] = data->mBuffers[c].mData;
            continue;
        }
        lanes[c] = sg_scratch[c];
        const void *source = data->mBuffers[split ? c : 0].mData;
        for (UInt32 i = 0; i < frames; i++) {
            lanes[c][i] = silent ? 0 : readSample(source, split ? i : i * channels + c, bytes, isFloat, fraction);
        }
    }
    if (!SGTimePitchProcess(unit, lanes, frames) || direct) return;
    for (UInt32 c = 0; c < channels; c++) {
        void *target = data->mBuffers[split ? c : 0].mData;
        for (UInt32 i = 0; i < frames; i++) writeSample(target, split ? i : i * channels + c, lanes[c][i], bytes, isFloat, fraction);
    }
    *flags &= ~kAudioUnitRenderAction_OutputIsSilence;
}

// Scales the finished output in place, so the sleep timer's fade reaches every output format.
static void scaleInPlace(UInt32 frames, AudioBufferList *data) {
    float gain = loadFloat(&sg_gainBits);
    if (gain == 1 || gain < 0) return;
    UInt32 formatFlags = atomic_load_explicit(&sg_hardware.flags, memory_order_relaxed);
    UInt32 bytes = atomic_load_explicit(&sg_hardware.bytes, memory_order_relaxed);
    UInt32 channels = atomic_load_explicit(&sg_hardware.channels, memory_order_relaxed);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if (frames > kSGTimePitchMaxFrames || (bytes != 2 && bytes != 4) || !channels) return;
    if (split ? data->mNumberBuffers != channels : data->mNumberBuffers != 1 || data->mBuffers[0].mNumberChannels != channels) return;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * bytes * (split ? 1 : channels)) return;
    }
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        void *target = data->mBuffers[b].mData;
        UInt32 lanes = split ? 1 : channels;
        for (UInt32 c = 0; c < lanes; c++) {
            for (UInt32 i = 0; i < frames; i++) {
                UInt32 index = split ? i : i * channels + c;
                writeSample(target, index, readSample(target, index, bytes, isFloat, fraction) * gain, bytes, isFloat, fraction);
            }
        }
    }
}

static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    scaleInPlace(frames, data);
    if (tapped() || !atomic_load(&sg_engaged)) return noErr;
    atomic_store(&sg_busy, true);
    SGTimePitch *unit = atomic_load(&sg_inPlace);
    if (atomic_load(&sg_engaged) && unit) shiftInPlace(unit, flags, frames, data);
    atomic_store(&sg_busy, false);
    return noErr;
}

#pragma mark - Spotify's audio thread

// One side of the RemoteIO unit's element 0 into `into`; a side that is not linear PCM is left as it was.
static BOOL readScope(AudioUnit unit, AudioUnitScope scope, Format *into, AudioStreamBasicDescription *format) {
    UInt32 size = sizeof *format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, scope, 0, format, &size);
    if (status != noErr || format->mFormatID != kAudioFormatLinearPCM || format->mSampleRate <= 0) return NO;
    uint64_t bits;
    memcpy(&bits, &format->mSampleRate, sizeof bits);
    atomic_store(&into->rateBits, bits);
    atomic_store(&into->flags, format->mFormatFlags);
    atomic_store(&into->channels, format->mChannelsPerFrame);
    atomic_store(&into->bytes, format->mBitsPerChannel / 8);
    return YES;
}

static void readFormat(AudioUnit unit) {
    AudioStreamBasicDescription client = {0}, hardware = {0};
    BOOL clientRead = readScope(unit, kAudioUnitScope_Input, &sg_client, &client);
    BOOL hardwareRead = readScope(unit, kAudioUnitScope_Output, &sg_hardware, &hardware);
    static int logged;
    if (!clientRead || !hardwareRead) {
        if (logged++ < 6) SGLog(@"redesign speed: the output is not linear PCM (Spotify's side %@, the hardware's %@)", clientRead ? @"is" : @"is not", hardwareRead ? @"is" : @"is not");
        if (!clientRead) return;
    }
    if (logged++ < 6) SGLog(@"redesign speed: Spotify's output is %.0f Hz, %u channels, %u bits, flags 0x%x, into the hardware's %.0f Hz, %u channels, %u bits, flags 0x%x, slices of %u, %@",
                            client.mSampleRate, (unsigned)client.mChannelsPerFrame, (unsigned)client.mBitsPerChannel, (unsigned)client.mFormatFlags,
                            hardware.mSampleRate, (unsigned)hardware.mChannelsPerFrame, (unsigned)hardware.mBitsPerChannel, (unsigned)hardware.mFormatFlags,
                            SGAudioPipelineMaximumFrames(), tapped() ? @"fed through the menu's unit" : @"not taken over");
}

static void apply(void);

static void prepareOutput(AudioUnit unit) {
    atomic_store(&sg_engaged, false);
    readFormat(unit);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_speed != 1 || sg_semitones != 0) apply();
    });
}

#pragma mark - engaging the unit

// Pitch follows speed where speed applies, in the chain.
static BOOL following(void) {
    return sg_follows && tapped();
}

// Stops the render thread using a unit, and returns once it no longer is.
static void disengage(void) {
    atomic_store(&sg_engaged, false);
    for (int i = 0; i < 200 && atomic_load(&sg_busy); i++) usleep(250);
}

static SGTimePitch *unitForFormat(void) {
    BOOL pull = tapped(), varispeed = following();
    Format *format = pull ? &sg_client : &sg_hardware;
    double rate;
    uint64_t bits = atomic_load(&format->rateBits);
    memcpy(&rate, &bits, sizeof rate);
    UInt32 channels = atomic_load(&format->channels);
    if (pull) {
        // In the chain the unit hands its buffers to the RemoteIO unit as they are: float, one per channel.
        UInt32 flags = atomic_load(&format->flags);
        BOOL canonical = (flags & kAudioFormatFlagIsFloat) && (flags & kAudioFormatFlagIsNonInterleaved) && atomic_load(&format->bytes) == 4;
        if (!canonical) {
            static int logged;
            if (logged++ < 3) SGLog(@"redesign speed: the output is not float per channel (flags 0x%x), speed cannot apply", (unsigned)flags);
            return NULL;
        }
    }
    if (rate <= 0 || channels < 1 || channels > kSGTimePitchMaxChannels) return NULL;
    _Atomic(SGTimePitch *) *slot = varispeed ? &sg_varispeed : pull ? &sg_pull : &sg_inPlace;
    pthread_mutex_lock(&sg_buildLock);
    SGTimePitch *unit = atomic_load(slot);
    if (!unit || SGTimePitchSampleRate(unit) != rate || SGTimePitchChannels(unit) != channels) {
        BOOL wasEngaged = atomic_load(&sg_engaged);
        disengage();
        unit = varispeed ? SGTimePitchCreateVarispeed(rate, channels, pullForUnit, NULL)
                         : SGTimePitchCreate(rate, channels, pull ? pullForUnit : NULL, NULL);
        if (unit) {
            SGTimePitchSetRate(unit, pull ? sg_speed : 1);
            SGTimePitchSetSemitones(unit, sg_semitones);
        }
        atomic_store(slot, unit);
        if (pull) atomic_store(&sg_chain, unit);
        SGLog(@"redesign speed: %@ %@ for %.0f Hz, %u channels", unit ? (varispeed ? @"a varispeed" : @"a unit") : @"no unit",
              pull ? @"in the chain" : @"in place", rate, (unsigned)channels);
        if (unit && wasEngaged) atomic_store(&sg_engaged, true);
    }
    pthread_mutex_unlock(&sg_buildLock);
    return unit;
}

static void report(void) {
    SGTimePitch *unit = atomic_load(tapped() ? &sg_chain : &sg_inPlace);
    if (!unit) return;
    SGLog(@"redesign speed: %.2fx, %@, %u underruns, %u failures, largest pull %u, %.1f s of input", sg_speed,
          SGTimePitchIsVarispeed(unit) ? @"pitch following" : [NSString stringWithFormat:@"%+.0f st", sg_semitones],
          SGTimePitchUnderruns(unit), SGTimePitchFailures(unit), SGTimePitchLargestPull(unit),
          SGTimePitchConsumed(unit) / SGTimePitchSampleRate(unit));
}

// Puts the unit in or takes it out for the current speed and pitch.
static void apply(void) {
    BOOL normal = sg_speed == 1 && sg_semitones == 0;
    static NSUInteger change;
    NSUInteger thisChange = ++change;
    if (normal) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOffAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (thisChange != change || sg_speed != 1 || sg_semitones != 0 || !atomic_load(&sg_engaged)) return;
            report();
            disengage();
        });
    }
    SGTimePitch *unit = unitForFormat();
    if (!unit) {
        static int logged;
        if (!normal && logged++ < 3) SGLog(@"redesign speed: Spotify's output has not started, nothing to change yet");
        return;
    }
    SGTimePitchSetRate(unit, tapped() ? sg_speed : 1);
    SGTimePitchSetSemitones(unit, sg_semitones);
    if (tapped() && atomic_load(&sg_chain) != unit) {
        // Pitch began or stopped following speed: the other unit takes the chain over, from silence.
        disengage();
        atomic_store(&sg_chain, unit);
        SGLog(@"redesign speed: the %@ takes over at %.2fx", SGTimePitchIsVarispeed(unit) ? @"varispeed" : @"time and pitch unit", sg_speed);
    }
    if (!normal && !atomic_load(&sg_engaged)) {
        disengage();
        SGTimePitchReset(unit);
        atomic_store(&sg_engaged, true);
    }
}

#pragma mark - the menu's calls

double SGPlayerAudioLatency(void) {
    SGTimePitch *unit = atomic_load(&sg_chain);
    return atomic_load(&sg_engaged) && unit ? SGTimePitchLatency(unit) : 0;
}

double SGPlayerSpeed(void) {
    return sg_speed;
}

BOOL SGPlayerSpeedAllowed(void) {
    return tapped();
}

void SGSetPlayerSpeed(double speed) {
    if (!tapped()) return;
    sg_speed = (float)speed;
    storeFloat(&sg_speedBits, sg_speed);
    apply();
}

void SGPlayerSetGain(float gain) {
    storeFloat(&sg_gainBits, gain);
}

float SGPlayerPitch(void) {
    return sg_semitones;
}

void SGSetPlayerPitch(float semitones) {
    if ((!SGAudioPipelineAvailable() && !tapped()) || following()) return;
    sg_semitones = semitones;
    apply();
}

BOOL SGPlayerPitchAvailable(void) {
    return SGAudioPipelineAvailable() || tapped();
}

BOOL SGPlayerPitchFollowsSpeed(void) {
    return following();
}

void SGSetPlayerPitchFollowsSpeed(BOOL follows) {
    SGSetEnabled(SGKeyPitchFollowsSpeed, follows);
    if (sg_follows == follows) return;
    sg_follows = follows;
    // The pitch slider goes while pitch follows, so what it had set goes with it.
    if (follows) sg_semitones = 0;
    apply();
}

#pragma mark - Spotify's clock

%hook SPTPlayerState
- (double)playbackSpeed {
    double speed = %orig;
    float ours = loadFloat(&sg_speedBits);
    return ours > 0 && ours != 1 ? speed * ours : speed;
}
%end

%ctor {
    storeFloat(&sg_speedBits, 1);
    storeFloat(&sg_gainBits, 1);
    sg_follows = SGFlag(SGKeyPitchFollowsSpeed, NO);
    static const SGAudioProcessor processor = {prepareOutput, rendered};
    SGAudioPipelineRegister(SGAudioStageSpeedPitch, &processor);
    SGAudioPipelineSetPullProcessor(processPull);
    %init;
    SGRequireClasses(@[@"SPTPlayerState"]);
}
