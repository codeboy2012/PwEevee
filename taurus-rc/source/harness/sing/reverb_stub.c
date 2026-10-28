#include "Shared/AudioEffects/SGDSPEffects.h"

SGDSPReverb *SGDSPReverbCreate(double rate, int preset, double amount) {
    (void)rate;
    (void)preset;
    (void)amount;
    return NULL;
}

void SGDSPReverbRun(void *state, float *left, float *right, uint32_t frames) {
    (void)state;
    (void)left;
    (void)right;
    (void)frames;
}

void SGDSPReverbFree(void *state) {
    (void)state;
}
