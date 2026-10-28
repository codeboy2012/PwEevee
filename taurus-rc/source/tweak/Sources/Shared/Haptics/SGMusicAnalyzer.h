#import <Foundation/Foundation.h>

// A hit says which band it came from, so what Music Haptics follows (Haptics.h) can leave some out.
typedef NS_ENUM(uint8_t, SGMusicEventKind) {
    SGMusicEventKick,    // a hit in the bass (a kick, an 808): one transient
    SGMusicEventSnare,   // a hit in the top (a snare, a clap): one transient
    SGMusicEventLevel,   // the continuous vibration from here on, sent about 60 times a second
};

typedef struct {
    uint64_t hostTime;    // mach absolute time of the sound, as the render timestamp gave it
    float intensity;      // 0...1
    float sharpness;      // 0...1
    SGMusicEventKind kind;
} SGMusicEvent;

typedef void (*SGMusicEmit)(const SGMusicEvent *event, void *context);

enum { SGMusicHistoryLength = 256, SGMusicAttackHops = 4, SGMusicWindowHops = 4 };

typedef struct {
    double b0, b1, b2, a1, a2;
    double z1, z2;
} SGMusicBiquad;

typedef struct {
    float history[SGMusicHistoryLength];   // the energy of each hop of the last second
    int count, next;
    double sum;
    float window[SGMusicWindowHops];   // the energy of the last hops
    int windowNext;
    float lastInstant;
    float peakDb;         // the loudest this band has been lately, falling slowly
    float recentDb[SGMusicAttackHops];
    int recentNext;
    int rest;             // hops before the band may hit again
    int pending;          // hops a hit has been rising for, 0 when none
    float pendingRatio;   // the most the rising hit went over the average
    float pendingEnergy;  // its energy then
    float lastHit;        // the energy of the last hit taken
    int sinceHit;         // hops since then
    float pendingDb;
    float pendingBright;
    uint64_t pendingTime;
    int armed;
} SGMusicBand;

typedef struct {
    double sampleRate;
    double ticksPerSecond;
    int hopFrames, hopFilled;
    int historyHops;
    uint64_t hopTime;
    double lowSum, highSum, midSum, fullSum;
    SGMusicBiquad lowPass[2], highPass[2], midPass[2];
    SGMusicBand kick, snap, mid;   // the bass, the top, and the middle (only its average is read)
    double bassEnvelope, brightness;
    int levelCountdown;
    int sinceKick;        // hops since the bass last hit
} SGMusicAnalyzer;

// Before the first buffer, and again when the sample rate changes or the sound jumps (a seek).
void SGMusicAnalyzerReset(SGMusicAnalyzer *analyzer, double sampleRate, double ticksPerSecond);
// `mono` holds `frames` samples in -1...1, the first reaching the output at `hostTime`.
void SGMusicAnalyzerProcess(SGMusicAnalyzer *analyzer, const float *mono, uint32_t frames, uint64_t hostTime,
                             SGMusicEmit emit, void *context);
