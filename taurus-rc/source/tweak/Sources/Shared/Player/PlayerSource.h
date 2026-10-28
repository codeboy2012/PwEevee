// The source a local file can play in place of Spotify's own sound. The lossless engine (Shared/Lossless) anchors
// on Spotify's output and then swaps the file in through a selector installed here.
//
// The epoch names the current source: a track, a seek, a pause, a route change each move it, so an anchor taken
// for the old one stops. The selector runs on the render thread once per output buffer, after Spotify's own sound
// has been pulled, and may overwrite the buffer's contents. The tap is the audio pipeline's pull processor
// (Shared/Audio/SGAudioPipeline), which is why the source is pulled here rather than by the pipeline itself.
#pragma once
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <stdint.h>

// `output` only identifies the audio unit the sound came from; `sourceFrame` counts frames from the epoch's start.
typedef void (*SGPlayerSourceSelector)(AudioUnit output, uint64_t epoch, double sourceFrame, double rate,
                                       UInt32 frames, AudioBufferList *data);

// The current source's epoch; it moves when SGPlayerInvalidateSource runs.
uint64_t SGPlayerSourceEpoch(void);
// Installs the render-thread selector and the pipeline tap that drives it; the first call wins.
void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector);
// The source changed: the epoch moves, so an anchor taken for the old one stops.
void SGPlayerInvalidateSource(void);
