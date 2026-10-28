#import <stdbool.h>
#import <stddef.h>
#import <stdint.h>
#import "SGDSPFilters.h"

typedef void (*SGDSPRun)(void *state, float *left, float *right, uint32_t frames);
typedef void (*SGDSPFree)(void *state);

// Every Run takes up to this many frames.
enum { kSGDSPEffectMaxFrames = 1024 };

typedef struct SGDSPBass SGDSPBass;
SGDSPBass *SGDSPBassCreate(double rate, double maxGainDB);
void SGDSPBassSet(SGDSPBass *bass, double maxGainDB);
void SGDSPBassRun(void *bass, float *left, float *right, uint32_t frames);

typedef struct SGDSPEqualizer SGDSPEqualizer;
// `bands` from SGDSPDesignEqualizer.
SGDSPEqualizer *SGDSPEqualizerCreate(const SGBiquad bands[15]);
void SGDSPEqualizerSet(SGDSPEqualizer *equalizer, const SGBiquad bands[15]);
void SGDSPEqualizerRun(void *equalizer, float *left, float *right, uint32_t frames);

// A cascade of biquads on both channels (ViPER DDC's filters); takes `sections`, which Free frees.
typedef struct SGDSPCascade SGDSPCascade;
SGDSPCascade *SGDSPCascadeCreate(SGBiquad *sections, int count);
void SGDSPCascadeRun(void *cascade, float *left, float *right, uint32_t frames);
void SGDSPCascadeFree(void *cascade);

// Mid and side, the side scaled by level / 50 (50 leaves it as it is); widening leaves the side's lows alone.
typedef struct SGDSPWide SGDSPWide;
SGDSPWide *SGDSPWideCreate(double rate, double levelPercent);
void SGDSPWideSet(SGDSPWide *wide, double levelPercent);
void SGDSPWideRun(void *wide, float *left, float *right, uint32_t frames);

typedef struct SGDSPCompander SGDSPCompander;
SGDSPCompander *SGDSPCompanderCreate(double rate, double timeConstant, const double frequencies[7], const double gains[7]);
void SGDSPCompanderSet(SGDSPCompander *compander, double timeConstant, const double gains[7]);
void SGDSPCompanderRun(void *compander, float *left, float *right, uint32_t frames);

// An asymmetric soft clip at twice the rate: even harmonics first, the level kept for quiet sounds.
typedef struct SGDSPTube SGDSPTube;
SGDSPTube *SGDSPTubeCreate(double rate, double driveDB);
void SGDSPTubeSet(SGDSPTube *tube, double driveDB);
void SGDSPTubeRun(void *tube, float *left, float *right, uint32_t frames);

// preset: SGDSPCrossfeedPresetCount of them, lightest first.
enum { SGDSPCrossfeedPresetCount = 3 };
typedef struct SGDSPCrossfeed SGDSPCrossfeed;
SGDSPCrossfeed *SGDSPCrossfeedCreate(double rate, int preset);
void SGDSPCrossfeedSet(SGDSPCrossfeed *crossfeed, int preset);
void SGDSPCrossfeedRun(void *crossfeed, float *left, float *right, uint32_t frames);

// preset: an index of SGDSPReverbPresetCount. NULL when the unit could not be made.
enum { SGDSPReverbPresetCount = 9 };
typedef struct SGDSPReverb SGDSPReverb;
SGDSPReverb *SGDSPReverbCreate(double rate, int preset, double amount);
void SGDSPReverbSet(SGDSPReverb *reverb, int preset, double amount);
void SGDSPReverbRun(void *reverb, float *left, float *right, uint32_t frames);
void SGDSPReverbFree(void *reverb);

typedef struct SGDSPLiveprog SGDSPLiveprog;
SGDSPLiveprog *SGDSPLiveprogCreate(const char *script, double rate, char *error, size_t errorSize);
void SGDSPLiveprogRun(void *liveprog, float *left, float *right, uint32_t frames);
void SGDSPLiveprogFree(void *liveprog);
