// The Visualizer's spectrum (SGRSpectrum.h): a ring of the last kSize samples, analyzed every kHop.
#import <Accelerate/Accelerate.h>
#import <math.h>
#import <stdatomic.h>
#import <string.h>
#import "SGRSpectrum.h"

enum { kLog2Size = 12, kSize = 1 << kLog2Size, kHalf = kSize / 2, kHop = 1024 };
// The bands' edges: a kick's fundamental at the bottom, the air of cymbals at the top.
static const double kLowest = 50, kHighest = 14000;

// Main thread, once, before the render thread reads them.
static FFTSetup sg_setup;
static float sg_window[kSize];
static atomic_bool sg_prepared;

// The render thread's own.
static float sg_ring[kSize], sg_windowed[kSize], sg_real[kHalf], sg_imag[kHalf], sg_power[kHalf];
static uint32_t sg_at, sg_sinceLast, sg_filled;
static double sg_rate;
static uint32_t sg_from[SGRSpectrumBands], sg_to[SGRSpectrumBands];   // bins, the end not included

// Published.
static _Atomic(float) sg_levels[SGRSpectrumBands];
static _Atomic(uint64_t) sg_generation;

void SGRSpectrumPrepare(void) {
    if (atomic_load(&sg_prepared)) return;
    sg_setup = vDSP_create_fftsetup(kLog2Size, kFFTRadix2);
    vDSP_hann_window(sg_window, kSize, vDSP_HANN_DENORM);
    for (int band = 0; band < SGRSpectrumBands; band++) atomic_store(&sg_levels[band], SGRSpectrumFloor);
    atomic_store_explicit(&sg_prepared, true, memory_order_release);
}

// A band takes the bins whose middles are in it, and at least one, so the low bands, narrower than a bin, still
// read something; two of them can read the same bin.
static void setRate(double rate) {
    sg_rate = rate;
    sg_at = sg_sinceLast = sg_filled = 0;
    memset(sg_ring, 0, sizeof sg_ring);
    double binHz = rate / kSize, ratio = pow(kHighest / kLowest, 1.0 / SGRSpectrumBands);
    for (int band = 0; band < SGRSpectrumBands; band++) {
        double low = kLowest * pow(ratio, band), high = low * ratio;
        uint32_t from = (uint32_t)fmax(1, ceil(low / binHz)), to = (uint32_t)fmin(kHalf, ceil(high / binHz));
        if (from >= kHalf) from = kHalf - 1;
        sg_from[band] = from;
        sg_to[band] = to > from ? to : from + 1;
    }
}

// The power over a band, summed, as a full scale sine's: a Hann window keeps 3/8 of a sine's power over its
// bins, and vDSP's real FFT gives twice the DFT, so a sine of amplitude A sums to 3/8 * kSize^2 * A^2 here.
static void analyse(void) {
    // The ring from its oldest sample, windowed.
    uint32_t tail = kSize - sg_at;
    vDSP_vmul(sg_ring + sg_at, 1, sg_window, 1, sg_windowed, 1, tail);
    vDSP_vmul(sg_ring, 1, sg_window + tail, 1, sg_windowed + tail, 1, sg_at);
    DSPSplitComplex split = {sg_real, sg_imag};
    vDSP_ctoz((const DSPComplex *)sg_windowed, 2, &split, 1, kHalf);
    vDSP_fft_zrip(sg_setup, &split, 1, kLog2Size, kFFTDirection_Forward);
    // The first bin's imaginary part is the Nyquist bin's real one, which no band reaches.
    sg_imag[0] = 0;
    vDSP_zvmags(&split, 1, sg_power, 1, kHalf);
    const float scale = 1.0f / (0.375f * (float)kSize * (float)kSize);
    for (int band = 0; band < SGRSpectrumBands; band++) {
        float sum = 0;
        vDSP_sve(sg_power + sg_from[band], 1, &sum, sg_to[band] - sg_from[band]);
        float level = sum > 0 ? 10 * log10f(sum * scale) : SGRSpectrumFloor;
        atomic_store_explicit(&sg_levels[band], fmaxf(SGRSpectrumFloor, level), memory_order_relaxed);
    }
    atomic_fetch_add_explicit(&sg_generation, 1, memory_order_release);
}

void SGRSpectrumFeed(const float *samples, uint32_t count, double sampleRate) {
    if (!samples || sampleRate <= 0 || !atomic_load_explicit(&sg_prepared, memory_order_acquire)) return;
    if (sampleRate != sg_rate) setRate(sampleRate);
    while (count) {
        uint32_t run = count;
        if (run > kSize - sg_at) run = kSize - sg_at;
        if (run > kHop - sg_sinceLast) run = kHop - sg_sinceLast;
        memcpy(sg_ring + sg_at, samples, run * sizeof(float));
        samples += run;
        count -= run;
        sg_at = (sg_at + run) & (kSize - 1);
        sg_sinceLast += run;
        if (sg_filled < kSize) sg_filled += run;
        if (sg_sinceLast == kHop) {
            sg_sinceLast = 0;
            // Not before the ring is full once: a window half of zeros would read a step in the sound.
            if (sg_filled >= kSize) analyse();
        }
    }
}

uint64_t SGRSpectrumRead(float levels[SGRSpectrumBands]) {
    uint64_t generation = atomic_load_explicit(&sg_generation, memory_order_acquire);
    for (int band = 0; band < SGRSpectrumBands; band++) {
        levels[band] = atomic_load_explicit(&sg_levels[band], memory_order_relaxed);
    }
    return generation;
}
