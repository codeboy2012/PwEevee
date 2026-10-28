#import <stdbool.h>
#import <stddef.h>
#import <stdint.h>

enum { kSGDSPEngineBlock = 1024 };

typedef struct SGDSPEngine SGDSPEngine;

// Stereo at `sampleRate`, every effect off, output gain 0 dB. NULL when out of memory.
SGDSPEngine *SGDSPEngineCreate(double sampleRate);
// Only once nothing renders through it.
void SGDSPEngineFree(SGDSPEngine *engine);

// Any thread.
double SGDSPEngineSampleRate(const SGDSPEngine *engine);
// A new rate, every effect off until the caller sets them again.
void SGDSPEngineSetSampleRate(SGDSPEngine *engine, double sampleRate);
// Every effect off, for when the output stopped being finite.
void SGDSPEngineReset(SGDSPEngine *engine);
// Frees what the effects replaced once their crossfades are over; the setters do it too.
void SGDSPEngineCollect(SGDSPEngine *engine);

#pragma mark - effects, the config side

void SGDSPEngineSetOutput(SGDSPEngine *engine, double postGainDB, double limiterThresholdDB, double limiterReleaseMS);
// gains: each band's -1 ... 1 at `frequencies` (SGDSPEffects.h, the compander).
void SGDSPEngineSetCompander(SGDSPEngine *engine, bool on, double timeConstant, const double frequencies[7], const double gains[7]);
void SGDSPEngineSetBassBoost(SGDSPEngine *engine, bool on, double maxGainDB);
void SGDSPEngineSetEqualizer(SGDSPEngine *engine, bool on, const double frequencies[15], const double gains[15]);
// preset: an index of SGDSPReverbPresetCount.
void SGDSPEngineSetReverb(SGDSPEngine *engine, bool on, int preset, double amount);
void SGDSPEngineSetStereoWide(SGDSPEngine *engine, bool on, double levelPercent);
// preset: an index of SGDSPCrossfeedPresetCount, lightest first.
void SGDSPEngineSetCrossfeed(SGDSPEngine *engine, bool on, int preset);
void SGDSPEngineSetTube(SGDSPEngine *engine, bool on, double driveDB);

bool SGDSPEngineSetGraphicEq(SGDSPEngine *engine, bool on, const char *nodes, char *error, size_t errorSize);
// An impulse response file (.wav, .irs, .flac) read at the engine's rate. mode: SGDSPImpulseMode.
bool SGDSPEngineSetConvolver(SGDSPEngine *engine, bool on, const char *path, int mode, char *error, size_t errorSize);
// A ViPER DDC file's text.
bool SGDSPEngineSetDDC(SGDSPEngine *engine, bool on, const char *text, char *error, size_t errorSize);
// A Liveprog script's text; an error names the file's line.
bool SGDSPEngineSetLiveprog(SGDSPEngine *engine, bool on, const char *script, char *error, size_t errorSize);

#pragma mark - the render thread

// Replaces `frames` samples of each lane with the processed sound one block before them.
void SGDSPEngineProcess(SGDSPEngine *engine, float *left, float *right, uint32_t frames);
void SGDSPEngineRestart(SGDSPEngine *engine);

#pragma mark - diagnostics, any thread

typedef struct {
    uint64_t blocks;        // processed
    uint64_t dry;           // passed through because a setting was being changed
    uint64_t faults;        // came out not finite and were silenced
    double averageMS;       // processing time of a block, a running average
    double peakMS;          // the longest since the peak was last taken
    double load;            // averageMS over the block's duration
} SGDSPEngineStats;

// takePeak starts the peak over; one reader takes it, the others leave it.
SGDSPEngineStats SGDSPEngineReadStats(SGDSPEngine *engine, bool takePeak);

#pragma mark - curves, any thread

void SGDSPEngineEqualizerCurve(const double bandFrequencies[15], const double gains[15], int count, double *frequencies, double *decibels);
void SGDSPEngineCompanderCurve(const double bandFrequencies[7], const double gains[7], int count, double *frequencies, double *values);
