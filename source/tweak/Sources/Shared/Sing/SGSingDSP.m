#include "SGSingDSP.h"
#include <math.h>

static const double kLevelRampSeconds = 0.030, kBypassRampSeconds = 0.120;
static const float kVoiceWidth = 0.5f, kVoiceDelay = 0.00065f, kVoiceShadow = 0.35f;
static const float kTau = 6.28318530718f, kPiQuarter = 0.78539816339f, kSqrtTwo = 1.41421356237f;

static float gain(float level) { return SGSingClampLevel(level); }
static void ramp(SGSingMixer *m, float to, double seconds) {
    m->targetGain = to;
    m->remaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->step = (to - m->gain) / m->remaining;
}
void SGSingMixerInit(SGSingMixer *m, double rate, float level) {
    *m = (SGSingMixer){.gain = gain(level), .targetGain = gain(level),
                      .sampleRate = isfinite(rate) && rate >= 8000 && rate <= 192000 ? rate : 44100,
                      .directGain = 1, .targetDirectGain = 1, .width = 1, .targetWidth = 1};
}
void SGSingMixerSetLevel(SGSingMixer *m, float level) {
    float target = gain(level);
    if (target != m->targetGain) ramp(m, target, kLevelRampSeconds);
}
void SGSingMixerBypass(SGSingMixer *m) { ramp(m, 0.5f, kBypassRampSeconds); }
void SGSingMixerSetVoiceAngle(SGSingMixer *m, float radians) {
    m->targetVoiceAngle = isfinite(radians) ? remainderf(radians, kTau) : 0;
}
void SGSingMixerSetSpatial(SGSingMixer *m, bool on, float distance, float room, float width) {
    if (!on) {
        m->targetDirectGain = 1;
        m->targetSendGain = 0;
        m->targetWidth = 1;
        return;
    }
    distance = isfinite(distance) ? fminf(6.5f, fmaxf(1, distance)) : 1.5f;
    room = isfinite(room) ? fminf(1, fmaxf(0, room)) : 0.25f;
    m->targetDirectGain = sqrtf(1 / distance);
    m->targetSendGain = room * (0.5f + 0.5f * (distance - 1) / 5.5f);
    m->targetWidth = isfinite(width) ? fminf(2, fmaxf(0, width)) : 1.1f;
}

void SGSingMixerProcess(SGSingMixer *m, const float *original, const float *vocals, float *out, uint32_t frames) {
    const float glide = 1 - expf(-1 / (0.05f * (float)m->sampleRate));
    bool spatial = m->directGain != 1 || m->targetDirectGain != 1 ||
                   m->sendGain != 0 || m->targetSendGain != 0 ||
                   m->width != 1 || m->targetWidth != 1 ||
                   m->voiceAngle != 0 || m->targetVoiceAngle != 0;
    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            if (!--m->remaining) m->gain = m->targetGain;
        }
        size_t at = (size_t)i * 2;
        float left = isfinite(original[at]) ? original[at] : 0;
        float right = isfinite(original[at + 1]) ? original[at + 1] : 0;
        float vocalLeft = isfinite(vocals[at]) ? vocals[at] : 0;
        float vocalRight = isfinite(vocals[at + 1]) ? vocals[at + 1] : 0;
        if (!spatial) {
            float instrumentMix = m->gain <= 0.5f ? 1 : 2 * (1 - m->gain);
            float voiceMix = m->gain < 0.5f ? 2 * m->gain : 1;
            float instrumentalLeft = left - vocalLeft, instrumentalRight = right - vocalRight;
            out[at] = fmaxf(-1, fminf(1, instrumentMix * instrumentalLeft + voiceMix * vocalLeft));
            out[at + 1] = fmaxf(-1, fminf(1, instrumentMix * instrumentalRight + voiceMix * vocalRight));
            m->roomSend = 0;
            continue;
        }
        m->voiceAngle += remainderf(m->targetVoiceAngle - m->voiceAngle, kTau) * glide;
        m->directGain += (m->targetDirectGain - m->directGain) * glide;
        m->sendGain += (m->targetSendGain - m->sendGain) * glide;
        m->width += (m->targetWidth - m->width) * glide;

        float middle = (vocalLeft + vocalRight) * 0.5f;
        float side = (vocalLeft - vocalRight) * 0.5f;
        m->middle[m->middleAt] = middle;
        float rightward = sinf(m->voiceAngle), far = fabsf(rightward);
        float pan = (kVoiceWidth * rightward + 1) * kPiQuarter;
        float gainLeft = kSqrtTwo * cosf(pan), gainRight = kSqrtTwo * sinf(pan);
        float delay = far * kVoiceDelay * (float)m->sampleRate;
        uint32_t whole = (uint32_t)delay;
        float part = delay - whole;
        uint32_t recent = (m->middleAt - whole) & 63;
        uint32_t older = (recent - (whole < 63)) & 63;
        float delayed = m->middle[recent] * (1 - part) + m->middle[older] * part;
        float shadow = 1 - far * (1 - kVoiceShadow);
        m->shadowLeft += (rightward > 0 ? shadow : 1) * (delayed - m->shadowLeft);
        m->shadowRight += (rightward < 0 ? shadow : 1) * (delayed - m->shadowRight);
        m->middleAt = (m->middleAt + 1) & 63;

        float instrumentalLeft = left - vocalLeft;
        float instrumentalRight = right - vocalRight;
        float instrumentMix = m->gain <= 0.5f ? 1 : 2 * (1 - m->gain);
        float voiceMix = m->gain < 0.5f ? 2 * m->gain : 1;
        float instrumentalSide = (instrumentalLeft - instrumentalRight) * 0.5f;
        instrumentalLeft += (m->width - 1) * instrumentalSide;
        instrumentalRight -= (m->width - 1) * instrumentalSide;
        float placedLeft = gainLeft * m->shadowLeft + side;
        float placedRight = gainRight * m->shadowRight - side;
        m->roomSend = voiceMix * m->sendGain * middle;
        out[at] = fmaxf(-1, fminf(1, instrumentMix * instrumentalLeft + voiceMix * m->directGain * placedLeft));
        out[at + 1] = fmaxf(-1, fminf(1, instrumentMix * instrumentalRight + voiceMix * m->directGain * placedRight));
    }
}
