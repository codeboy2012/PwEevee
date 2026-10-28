#import <stdbool.h>
#import <stddef.h>
#import <stdint.h>

// y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2, run as transposed direct form II in double.
typedef struct {
    double b0, b1, b2, a1, a2;
} SGBiquad;

typedef struct {
    double s1, s2;
} SGBiquadState;

static inline double SGBiquadTick(const SGBiquad *q, SGBiquadState *s, double x) {
    double y = q->b0 * x + s->s1;
    s->s1 = q->b1 * x - q->a1 * y + s->s2;
    s->s2 = q->b2 * x - q->a2 * y;
    return y;
}

// A lane through `count` sections in turn, in place.
void SGBiquadRun(const SGBiquad *sections, SGBiquadState *states, int count, float *lane, uint32_t frames);

SGBiquad SGBiquadPeak(double rate, double frequency, double q, double gainDB);
SGBiquad SGBiquadLowShelf(double rate, double frequency, double q, double gainDB);
SGBiquad SGBiquadLowPass(double rate, double frequency, double q);
SGBiquad SGBiquadHighPass(double rate, double frequency, double q);
SGBiquad SGBiquadAllPass(double rate, double frequency, double q);
double SGBiquadGainDB(const SGBiquad *sections, int count, double rate, double frequency);

void SGDSPDesignEqualizer(double rate, const double frequencies[15], const double gains[15], SGBiquad bands[15]);

// `count` frequencies log spaced from 20 Hz to 20 kHz.
void SGDSPLogFrequencies(int count, double *frequencies);

// A smooth curve through points on a log frequency axis (monotone cubic, flat past the ends), for drawing.
double SGDSPSmoothCurve(const double *frequencies, const double *values, int count, double frequency);

#pragma mark - ViPER DDC

typedef struct {
    SGBiquad *sections[2];
    int counts[2];
} SGDSPDDC;

bool SGDSPParseDDC(const char *text, SGDSPDDC *ddc, char *error, size_t errorSize);
void SGDSPFreeDDC(SGDSPDDC *ddc);
SGBiquad *SGDSPDDCFor(const SGDSPDDC *ddc, double rate, int *count);

#pragma mark - GraphicEQ and minimum phase

// AutoEq's "GraphicEQ: 20 -1.2; 21 -1.1; ...": its points, sorted by frequency.
typedef struct {
    double *frequencies, *gains;
    int count;
} SGDSPGraphicCurve;

bool SGDSPParseGraphicEq(const char *text, SGDSPGraphicCurve *curve);
void SGDSPFreeGraphicEq(SGDSPGraphicCurve *curve);
// dB at `frequency`: straight between points on a log frequency axis, flat past the ends.
double SGDSPGraphicEqAt(const SGDSPGraphicCurve *curve, double frequency);
// The curve as a minimum phase FIR at `rate`, `*taps` long (malloc'd); NULL when out of memory.
float *SGDSPDesignGraphicEq(const SGDSPGraphicCurve *curve, double rate, int *taps);

bool SGDSPMinimumPhase(const double *magnitude, int log2n, float *impulse, int taps);
