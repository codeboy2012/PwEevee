// Sing's player lifecycle and worker ownership. Main thread except the clock and invalidation APIs.
#import <Foundation/Foundation.h>
#include "SGSingLevel.h"
@class SPTPlayerState;
extern NSString *const SGSingDidChangeNotification;
typedef NS_ENUM(NSUInteger, SGSingState) {
    SGSingUnavailable, SGSingIdle, SGSingPreparing, SGSingActive, SGSingDraining, SGSingFailed,
    SGSingReady, // the local model is loaded; playback has not supplied audio yet
    SGSingRecovering // aligned original audio while a temporarily late worker catches up
};
// Sing is on: the model is loaded and the song's vocals are turned down, or will be as soon as it
// plays (Ready), or are about to be again (Recovering).
static inline BOOL SGSingStateIsOn(SGSingState state) {
    return state == SGSingActive || state == SGSingReady || state == SGSingRecovering;
}
BOOL SGSingSupported(void); // iOS 18, the deployment floor of the Core ML model
// Sing's switch (the redesign's Mod Settings > Karaoke), at launch and whenever it is turned. Off, Sing does no
// work and is unavailable; on, it is available once its voice model is on this iPhone (SGSingModel.h).
void SGSingConfigure(BOOL enabled);
SGSingState SGSingCurrentState(void);
// Sing is switched on and has its model: the lyrics show its microphone. SGSingDidChangeNotification says
// when this changes.
BOOL SGSingAvailable(void);
NSString *SGSingExplanation(void);
BOOL SGSingCanRetry(void); // current playback/thermal restrictions and previous generation retired
BOOL SGSingEnabled(void); // user's intent, retained across playback changes
float SGSingVocalLevel(void);
float SGSingReducedLevel(void); // the last balance below vocals-only, which turning Sing on goes back to
void SGSingSetVocalLevel(float level);
void SGSingSetEnabled(BOOL enabled);
#define SGKeySingIgnoreResourceWarnings @"spotifyglass.sing.ignoreResourceWarnings"
void SGSingResourceWarningsChanged(void);
#if SG_DRIVER
void SGDriverSingSetEnabled(BOOL enabled);
#endif
// Before/after an explicit seek or skip. The first invalidates render output immediately.
void SGSingPlaybackWillChange(void);
void SGSingPlaybackDidChange(void);
void SGSingPlaybackDidSeek(double seconds);
uint64_t SGSingTrackIdentifier(id uri);
BOOL SGSingPosition(SPTPlayerState *state, double *position);
double SGSingSourcePosition(SPTPlayerState *state); // the unmodified player getter, defined by hooks

#define SGKeySingSpatial @"spotifyglass.sing.spatial"
#define SGKeySingSpatialDistance @"spotifyglass.sing.spatial.distance"
#define SGKeySingSpatialRoom @"spotifyglass.sing.spatial.room"
#define SGKeySingSpatialFront @"spotifyglass.sing.spatial.front"
#define SGKeySingSpatialWidth @"spotifyglass.sing.spatial.width"
BOOL SGSingSpatialAvailable(void);
BOOL SGSingSpatial(void);
void SGSetSingSpatial(BOOL on);
double SGSingSpatialDistance(void);
double SGSingSpatialRoom(void);
double SGSingSpatialFront(void);
double SGSingSpatialWidth(void);
void SGSetSingSpatialSound(double meters, double roomPercent, double frontSeconds, double widthPercent);
