#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "SGSingLevel.h"

typedef struct {
    float gain, targetGain, step;
    uint32_t remaining;
    double sampleRate;
    float voiceAngle, targetVoiceAngle;
    float directGain, targetDirectGain, sendGain, targetSendGain, width, targetWidth;
    float shadowLeft, shadowRight, middle[64], roomSend;
    uint32_t middleAt;
} SGSingMixer;
// One render-thread owner. Control requests must be delivered atomically by the caller.
void SGSingMixerInit(SGSingMixer *mixer, double sampleRate, float level);
void SGSingMixerSetLevel(SGSingMixer *mixer, float level); // a 30 ms ramp to the new level
void SGSingMixerSetVoiceAngle(SGSingMixer *mixer, float radians);
void SGSingMixerSetSpatial(SGSingMixer *mixer, bool on, float distance, float room, float width);
// Stereo interleaved. Original and vocals must have identical generation, format and source index.
// Instrumental = original - vocals; a unity instrumental gain preserves the original balance.
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
// A 120 ms ramp to the aligned original, no clock change: SGSingReserveFrames at 44.1 kHz.
void SGSingMixerBypass(SGSingMixer *mixer);
