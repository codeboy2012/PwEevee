#import <Foundation/Foundation.h>

#pragma mark - keys

// The master switch, off until asked for. Off, Spotify's sound is left exactly as it was.
#define SGKeyDSP                        @"spotifyglass.dsp"

// Output control, applied while the master switch is on.
#define SGKeyDSPPostGain                @"spotifyglass.dsp.postGain"            // dB
#define SGKeyDSPLimiterThreshold        @"spotifyglass.dsp.limiterThreshold"    // dB
#define SGKeyDSPLimiterRelease          @"spotifyglass.dsp.limiterRelease"      // ms

#define SGKeyDSPCompander               @"spotifyglass.dsp.compander"
#define SGKeyDSPCompanderTime           @"spotifyglass.dsp.compander.time"      // s, the release
#define SGKeyDSPCompanderGains          @"spotifyglass.dsp.compander.gains"

#define SGKeyDSPBass                    @"spotifyglass.dsp.bass"
#define SGKeyDSPBassGain                @"spotifyglass.dsp.bass.gain"           // dB, the most it lifts

#define SGKeyDSPEqualizer               @"spotifyglass.dsp.eq"
// Fifteen gains in dB, "g;g;...;g", at SGDSPEqualizerFrequencies, each within SGDSPEqualizerGainLimit.
#define SGKeyDSPEqualizerGains          @"spotifyglass.dsp.eq.gains"

// The Graphic EQ, in AutoEq's GraphicEQ format: "GraphicEQ: 20 -1.2; 21 -1.1; ...".
#define SGKeyDSPGraphicEq               @"spotifyglass.dsp.geq"
#define SGKeyDSPGraphicEqNodes          @"spotifyglass.dsp.geq.nodes"

#define SGKeyDSPConvolver               @"spotifyglass.dsp.convolver"
#define SGKeyDSPConvolverFile           @"spotifyglass.dsp.convolver.file"
#define SGKeyDSPConvolverMode           @"spotifyglass.dsp.convolver.mode"      // SGDSPConvolverModeNames index

#define SGKeyDSPDDC                     @"spotifyglass.dsp.ddc"
#define SGKeyDSPDDCFile                 @"spotifyglass.dsp.ddc.file"

#define SGKeyDSPLiveprog                @"spotifyglass.dsp.liveprog"
#define SGKeyDSPLiveprogFile            @"spotifyglass.dsp.liveprog.file"

#define SGKeyDSPReverb                  @"spotifyglass.dsp.reverb"
#define SGKeyDSPReverbPreset            @"spotifyglass.dsp.reverb.preset"       // SGDSPReverbPresetNames index
#define SGKeyDSPReverbAmount            @"spotifyglass.dsp.reverb.amount"       // percent of the preset's wet mix

#define SGKeyDSPStereoWide              @"spotifyglass.dsp.wide"
#define SGKeyDSPStereoWideLevel         @"spotifyglass.dsp.wide.level"          // percent, 50 leaving the width as it is

#define SGKeyDSPCrossfeed               @"spotifyglass.dsp.crossfeed"
#define SGKeyDSPCrossfeedMode           @"spotifyglass.dsp.crossfeed.mode"      // SGDSPCrossfeedModeNames index

#define SGKeyDSPTube                    @"spotifyglass.dsp.tube"
#define SGKeyDSPTubeDrive               @"spotifyglass.dsp.tube.drive"          // dB

#pragma mark - values

// A number setting's bounds, the value it has until set, and the step a slider moves it by.
typedef struct {
    double min, max, fallback, step;
} SGDSPRange;

SGDSPRange SGDSPRangeFor(NSString *key);

// Switches, numbers (clamped to their range) and strings. Setting one applies it.
BOOL SGDSPSwitch(NSString *key);
void SGDSPSetSwitch(NSString *key, BOOL on);
double SGDSPNumber(NSString *key);
void SGDSPSetNumber(NSString *key, double value);
void SGDSPSetReverbAmount(double amount);
NSString *SGDSPString(NSString *key);
void SGDSPSetString(NSString *key, NSString *value);

// The equalizer's and the compander's gains as numbers (15 and 7 of them), from and to their keys.
NSArray<NSNumber *> *SGDSPGains(NSString *key);
void SGDSPSetGains(NSString *key, NSArray<NSNumber *> *gains);

// Every key above back to its value until set; the master switch stays as it is.
void SGDSPResetAll(void);

#pragma mark - the lists the choices pick from

extern const double SGDSPEqualizerFrequencies[15];     // Hz, 25 ... 16000
extern const double SGDSPEqualizerGainLimit;           // ±12 dB
extern const double SGDSPCompanderFrequencies[7];      // Hz, 95 ... 7500
extern const double SGDSPCompanderGainLimit;           // ±1.2

NSArray<NSString *> *SGDSPConvolverModeNames(void);
NSArray<NSString *> *SGDSPCrossfeedModeNames(void);
NSArray<NSString *> *SGDSPReverbPresetNames(void);
// The equalizer's presets, names and their 15 gains.
NSArray<NSString *> *SGDSPEqualizerPresetNames(void);
NSArray<NSNumber *> *SGDSPEqualizerPreset(NSInteger index);

#pragma mark - file libraries

typedef NS_ENUM(NSInteger, SGDSPFileKind) {
    SGDSPFileImpulseResponse,   // the convolver's: .wav .flac .irs (a WAV by another name)
    SGDSPFileDDC,               // ViPER DDC's .vdc
    SGDSPFileLiveprog,          // Liveprog's .eel
};

// Documents/spoti.pw/Audio effects/<Convolver|DDC|Liveprog>, made on first use, empty until files are imported.
NSString *SGDSPLibraryDirectory(SGDSPFileKind kind);
NSArray<NSString *> *SGDSPLibraryFiles(SGDSPFileKind kind);   // names, sorted
NSArray<NSString *> *SGDSPFileExtensions(SGDSPFileKind kind); // lowercase, without the dot
NSString *SGDSPImportFile(SGDSPFileKind kind, NSURL *url, NSError **error);
BOOL SGDSPDeleteFile(SGDSPFileKind kind, NSString *name);

#pragma mark - what the engine is doing

// One line for the page: off, waiting for Spotify to play, or running (sample rate, load).
NSString *SGDSPStatus(void);
NSString *SGDSPError(NSString *switchKey);

void SGDSPEqualizerResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *decibels);
// The compander's amounts drawn as a smooth curve, the same way.
void SGDSPCompanderResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *values);
