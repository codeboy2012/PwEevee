#pragma once
#include "Shared/Audio/SGAudioRingBuffer.h"
#include "Shared/Sing/SGSingFormat.h"

typedef enum {
    SGSingTimelineIdle,
    SGSingTimelinePreparing,
    SGSingTimelineActive,
    SGSingTimelineDraining,
    SGSingTimelineRecovering
} SGSingTimelineState;
enum { SGSingRecoveryLimitFrames = SGSingSampleRate * 8 };
typedef struct SGSingTimeline SGSingTimeline;

SGSingTimeline *SGSingTimelineCreate(uint32_t capacityFrames, uint32_t reserveFrames);
void SGSingTimelineDestroy(SGSingTimeline *timeline); // both endpoints stopped
// Begin also invalidates all retained audio. The caller must change generation before a seek.
void SGSingTimelineBegin(SGSingTimeline *timeline, SGAudioStamp origin, float vocalLevel);
void SGSingTimelineSetLevel(SGSingTimeline *timeline, float level);
void SGSingTimelineSetVoiceAngle(SGSingTimeline *timeline, float radians);
void SGSingTimelineSetSpatial(SGSingTimeline *timeline, bool on, float distance, float room, float width);
void SGSingTimelineBypass(SGSingTimeline *timeline);
SGSingTimelineState SGSingTimelineGetState(const SGSingTimeline *timeline);
uint32_t SGSingTimelineWritable(const SGSingTimeline *timeline);
uint64_t SGSingTimelineConsumed(const SGSingTimeline *timeline);
uint64_t SGSingTimelineQueued(const SGSingTimeline *timeline);
uint64_t SGSingTimelineReadyFrames(const SGSingTimeline *timeline);
bool SGSingTimelineCapture(SGSingTimeline *timeline, SGAudioStamp stamp, const float *original);
// Render owner only: copy a still-retained original prefix to the worker input queue.
uint32_t SGSingTimelineCopyOriginal(const SGSingTimeline *timeline, uint64_t sourceFrame, float *stereo, uint32_t frames);
bool SGSingTimelineVocals(SGSingTimeline *timeline, SGAudioStamp stamp, const float *vocals);
uint32_t SGSingTimelineRead(SGSingTimeline *timeline, float *output, uint32_t frames);
