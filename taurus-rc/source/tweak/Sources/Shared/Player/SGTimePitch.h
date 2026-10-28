#import <AudioToolbox/AudioToolbox.h>
#import <stdbool.h>

enum { kSGTimePitchMaxChannels = 2, kSGTimePitchMaxFrames = 4096 };

typedef struct SGTimePitch SGTimePitch;

// Fills `data` (the unit's buffers, one per channel) with the next `frames` frames of input.
typedef OSStatus (*SGTimePitchSource)(void *context, UInt32 frames, AudioBufferList *data);

SGTimePitch *SGTimePitchCreate(double sampleRate, UInt32 channels, SGTimePitchSource source, void *context);
// The varispeed: the same, but pull mode only, so NULL without a source.
SGTimePitch *SGTimePitchCreateVarispeed(double sampleRate, UInt32 channels, SGTimePitchSource source, void *context);
bool SGTimePitchIsVarispeed(const SGTimePitch *unit);
double SGTimePitchSampleRate(const SGTimePitch *unit);
UInt32 SGTimePitchChannels(const SGTimePitch *unit);

// Any thread, taking effect with the next buffer. Rate 1 is normal speed (0.25...4); semitones up or down.
void SGTimePitchSetRate(SGTimePitch *unit, float rate);
void SGTimePitchSetSemitones(SGTimePitch *unit, float semitones);

// Forgets the sound held, so the next buffer starts over from silence. Only while nothing renders.
void SGTimePitchReset(SGTimePitch *unit);

// Pull mode: `frames` frames of output into `data`, float non-interleaved buffers of the unit's channels.
OSStatus SGTimePitchRender(SGTimePitch *unit, UInt32 frames, AudioBufferList *data);

bool SGTimePitchProcess(SGTimePitch *unit, float *const *channels, UInt32 frames);

UInt32 SGTimePitchUnderruns(const SGTimePitch *unit);
UInt32 SGTimePitchFailures(const SGTimePitch *unit);
double SGTimePitchLatency(const SGTimePitch *unit);
UInt32 SGTimePitchLargestPull(const SGTimePitch *unit);
uint64_t SGTimePitchConsumed(const SGTimePitch *unit);
