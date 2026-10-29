#pragma once
#import <AudioToolbox/AudioToolbox.h>
#import "SGAudioSourceQueue.h"
#include <stdbool.h>

typedef enum {
    SGAudioStageSing,
    SGAudioStageSpeedPitch,
    SGAudioStageEffects,
    SGAudioStageHaptics,
    SGAudioStageCount
} SGAudioStage;

typedef struct {
    // Non-render thread: start or format change, before output is started.
    void (*prepare)(AudioUnit output);
    // Render thread: output-domain processors run once, in the order above.
    AURenderCallback output;
} SGAudioProcessor;

// Register immutable, process-lifetime storage, during startup only. No dynamic callbacks/blocks.
bool SGAudioPipelineRegister(SGAudioStage stage, const SGAudioProcessor *processor);
bool SGAudioPipelineAvailable(void);
bool SGAudioPipelineTapped(void);
UInt32 SGAudioPipelineMaximumFrames(void);
// Input to speed/pitch: the mixer in unique sample-time chunks, then source-domain processing.
OSStatus SGAudioPipelinePull(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time);
typedef OSStatus (*SGAudioSourceProcessor)(void *context, UInt32 frames, AudioBufferList *data,
                                          const AudioTimeStamp *time);
OSStatus SGAudioPipelinePullOriginal(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time);
// When `sounding` is non-NULL, stops at the first source chunk marked silent and reports its prefix.
OSStatus SGAudioPipelinePullOriginalAvailable(UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time,
                                             UInt32 *sounding);
UInt32 SGAudioPipelineSourceAheadFrames(UInt32 maximumFrames);
SGAudioSourcePrefix SGAudioPipelineSourcePrefix(UInt32 maximumFrames, bool continuous);
bool SGAudioPipelineSourceCanReadAhead(void); // off-render; exact supported source callback
bool SGAudioPipelineSetSourceProcessor(SGAudioSourceProcessor processor, void *context);
bool SGAudioPipelineClearSourceProcessor(void *context); // only if this context is still installed
bool SGAudioPipelineSourceFormat(AudioStreamBasicDescription *format); // off-render snapshot
bool SGAudioPipelineSourceProcessorAttached(void *context); // lock-free control/diagnostic read
// A pull processor either handles the buffer (including an error) or leaves source unconsumed.
typedef bool (*SGAudioPullProcessor)(UInt32 frames, AudioBufferList *data, OSStatus *status);
void SGAudioPipelineSetPullProcessor(SGAudioPullProcessor processor);
