#import "Shared/Player/PlayerSource.h"
#import "Shared/Audio/SGAudioPipeline.h"
#import <stdatomic.h>

static _Atomic(uintptr_t) sg_selector;
static _Atomic uint64_t sg_epoch = 1;
static _Atomic uint64_t sg_frame;   // source frames since the epoch began
static double sg_rate = 44100;

uint64_t SGPlayerSourceEpoch(void) {
    return atomic_load(&sg_epoch);
}

void SGPlayerInvalidateSource(void) {
    atomic_fetch_add(&sg_epoch, 1);
    atomic_store(&sg_frame, 0);
}

// The pipeline's source processor: Spotify's own sound is pulled first, then the selector may replace it. Runs on
// the render thread; Spotify's sound is unconsumed if the pull fails, so the pipeline's own path stays in charge.
static OSStatus playerSource(void *context, UInt32 frames, AudioBufferList *data, const AudioTimeStamp *time) {
    OSStatus pulled = SGAudioPipelinePullOriginal(frames, data, time);
    if (pulled != noErr) return pulled;
    SGPlayerSourceSelector selector = (SGPlayerSourceSelector)atomic_load(&sg_selector);
    if (!selector) return noErr;
    uint64_t frame = atomic_load(&sg_frame);
    selector(NULL, atomic_load(&sg_epoch), (double)frame, sg_rate, frames, data);
    atomic_fetch_add(&sg_frame, frames);
    return noErr;
}

void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) {
    atomic_store(&sg_selector, (uintptr_t)selector);
    AudioStreamBasicDescription format = {0};
    if (SGAudioPipelineSourceFormat(&format) && format.mSampleRate > 0) sg_rate = format.mSampleRate;
    // The source processor, not the pull processor: SpeedPitch owns the single pull slot, and its chain pulls the
    // source through here. (False while Spotify has not wired a supported source; the next anchor retries.)
    SGAudioPipelineSetSourceProcessor(playerSource, NULL);
}
