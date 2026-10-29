// Read-only look-ahead for the verified Spotify decoder. No private calls or PCM reads.
#pragma once
#import <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>

void SGAudioSourceQueueInitialize(void); // off-render, before registering source callbacks
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback);
bool SGAudioSourceQueueProbeRequired(AURenderCallbackStruct callback);
void SGAudioSourceQueueProbe(AURenderCallbackStruct callback); // diagnostics only; never enables an unverified ABI
typedef struct {
    UInt32 frames;
    UInt32 boundary; // first frame after a verified, traversable end marker; UINT32_MAX otherwise
} SGAudioSourcePrefix;
SGAudioSourcePrefix SGAudioSourceQueuePrefix(AURenderCallbackStruct callback, UInt32 maximumFrames, bool continuous);
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames);
