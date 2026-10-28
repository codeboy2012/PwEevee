#import <UIKit/UIKit.h>

void SGPlayerMenuWatchMoreButton(UIView *button);
UIView *SGSpeedPitchPanelMake(void);
CGFloat SGSpeedPitchPanelHeight(void);
// What the row says beside its name, the changed speed, pitch and reverb amount, nil while all are normal.
NSString *SGSpeedPitchSummary(void);
extern NSNotificationName const SGSpeedPitchChangedNotification;
// The speed Spotify's sound plays at, 1 when normal.
double SGPlayerSpeed(void);
// Scales Spotify's output, 0...1, for the sleep timer's fade; 1 is normal. Set on the main thread, read on the render thread.
void SGPlayerSetGain(float gain);
// Whether speed can apply: Spotify's output was taken over when it wired it.
BOOL SGPlayerSpeedAllowed(void);
void SGSetPlayerSpeed(double speed);
// Semitones the Pitch slider moves Spotify's output by, 0 when it does not (always while pitch follows speed).
float SGPlayerPitch(void);
void SGSetPlayerPitch(float semitones);
// Whether the output could be reached to change its pitch.
BOOL SGPlayerPitchAvailable(void);
#define SGKeyPitchFollowsSpeed @"spotifyglass.speedPitch.follows"
BOOL SGPlayerPitchFollowsSpeed(void);
void SGSetPlayerPitchFollowsSpeed(BOOL follows);

// Current downstream processing delay, in seconds. Atomic unit ownership; safe off-render.
double SGPlayerAudioLatency(void);
