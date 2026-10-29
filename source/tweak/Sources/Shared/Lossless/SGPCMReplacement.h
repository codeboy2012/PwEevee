#import "SGPreparedPCM.h"
#import "Shared/Player/PlayerSource.h"
#import "Shared/Player/SpeedPitch.h"

// Prototype only: no constructor enables this in Spotify. Call Enable once before using Install.
void SGPCMReplacementEnable(void);
// Off render. epoch must be current. sourceFrame and assetFrame describe the same next source frame,
// established by a playback owner, not by reading an audible position while Sing holds look-ahead.
// Assets are immutable and retained until all admitted readers have left. A publication is refused
// if retirement is backlogged. Initial cap is 32 MiB PCM per asset, at most three retained snapshots.
BOOL SGPCMReplacementInstall(SGPreparedPCM *asset, AudioUnit output, uint64_t epoch,
                             uint64_t sourceFrame, uint64_t assetFrame);
// Off render. Invalidate the epoch and detach the source. An admitted callback may finish its block.
void SGPCMReplacementCancel(void);
// Render implementation exposed for deterministic tests; normally registered through Enable.
void SGPCMReplacementApply(AudioUnit output, uint64_t epoch, double sourceFrame,
                           double sampleRate, UInt32 frames, AudioBufferList *data);
uint64_t SGPCMReplacementFrames(void);
