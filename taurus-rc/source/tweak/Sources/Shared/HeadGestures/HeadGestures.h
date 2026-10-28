// AirPods gestures (Mod Settings > Player > AirPods gestures), under either look: a double nod and a shake of
// the head, each doing what its pull-down says (Like and Next track until changed), read from the head motion
// that AirPods Pro, AirPods 3 and later, AirPods Max and some Beats report through CMHeadphoneMotionManager.
//
//     SGHeadDetector.m         the gestures out of the motion, plain C, tested on the Mac (harness/head-gestures)
//     HeadGestures.x           the motion listened to while the switch is on and Spotify plays, and what each
//                              gesture does through Spotify's player and its collection platform
//     HeadGesturesSettings.m   the page: the switch, each gesture's action, the sensitivity, Try it and Forget
//     HeadGesturesTeach.m      the teaching sheet: five of each gesture, one after each tone, over a ring that
//                              shows the head live
//
// HeadGestures.x owns the app's one CMHeadphoneMotionManager (iOS hands a manager's motion to one handler) and
// lends its motion to other features through SGHeadMotionListen: Sing's spatial voice listens there.
//
// Everything applies at once, without a restart.
// Threading: main thread only, but for the listeners' handlers.
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import "SGHeadDetector.h"

#define SGKeyHeadGestures @"spotifyglass.headgestures"
// A percentage the thresholds are divided by: over 100 a smaller move counts.
#define SGKeyHeadSensitivity @"spotifyglass.headgestures.sensitivity"
// What learning set, in thousandths of a radian a second; unset or 0 is the detector's default.
#define SGKeyHeadNod @"spotifyglass.headgestures.nod"
#define SGKeyHeadShake @"spotifyglass.headgestures.shake"
// Each gesture's SGHeadAction; unset is Like for the nod and Next track for the shake.
#define SGKeyHeadNodAction @"spotifyglass.headgestures.nodaction"
#define SGKeyHeadShakeAction @"spotifyglass.headgestures.shakeaction"

enum { SGHeadSensitivityMin = 50, SGHeadSensitivityMax = 200, SGHeadSensitivityStep = 10 };

// What a gesture does, stored as this number: the order is the pull-down's and only grows at the end.
typedef NS_ENUM(NSInteger, SGHeadAction) {
    SGHeadActionNothing,
    SGHeadActionSeekBack,      // 15 s
    SGHeadActionSeekForward,   // 15 s
    SGHeadActionPlayPause,
    SGHeadActionNext,
    SGHeadActionPrevious,
    SGHeadActionShuffle,       // on or off
    SGHeadActionRepeat,        // off, the context, the track, as Spotify's button goes
    SGHeadActionLike,          // into Liked Songs, never out
    SGHeadActionCount,
};
SGHeadAction SGHeadGestureAction(SGHeadGesture gesture);
void SGSetHeadGestureAction(SGHeadGesture gesture, SGHeadAction action);

// The cue's sounds, mixed into the music: one tone to time a gesture by, a rising pair when one worked, a low
// tone when it did not. A haptic comes with each while Spotify is in front.
typedef NS_ENUM(NSInteger, SGHeadCue) {
    SGHeadCueReady,
    SGHeadCueWorked,
    SGHeadCueFailed,
};
void SGHeadGesturesCue(SGHeadCue cue);

// Adds the playing track to Liked Songs, never takes it out, through the collection platform kept here: the
// nod's Like, and the Like shortcut's (Shared/LiveActivity). NO when what plays is no track or the platform
// was not reached yet. Spotify's toast shows only with Spotify in front.
BOOL SGLikePlayingTrack(void);

// From the switch, the sensitivity, the actions and learning: listens or stops, and reads the thresholds again.
void SGHeadGesturesSettingsChanged(void);
// Whether this iPhone can read headphone motion at all (iOS 14 and up; the headphones are another matter).
BOOL SGHeadGesturesAvailable(void);

// The page's listening, whatever plays, during which no gesture does anything to the song. One at a time:
// starting one ends the last, and a stopped one's done is never called.
//
// Records `seconds` of motion and hands it back, three doubles a sample (time, pitch, yaw), empty when no
// headphones sent any or motion is not allowed.
void SGHeadGesturesRecord(double seconds, void (^done)(NSData *motion));
// Listens up to `seconds` at the thresholds set now, sensitivity included, and hands back the first gesture,
// or SGHeadGestureNone once the time is up; `heard` says whether any motion came.
void SGHeadGesturesTry(double seconds, void (^done)(SGHeadGesture gesture, BOOL heard));
void SGHeadGesturesStopListening(void);
// While held the motion runs whatever plays and no gesture does anything: the teaching sheet holds it open, so
// the headphones are sending already when each of its recordings starts.
void SGHeadGesturesHold(BOOL hold);

// The threshold one recording of the gesture of `axis` teaches, 0 when it holds no such gesture.
double SGHeadGesturesSampleThreshold(NSData *motion, SGHeadAxis axis);
// Learns `axis` from recordings of it (SGHeadLearnSamples, all but one of them at least) and stores the
// threshold; answers it, or 0 with nothing stored.
double SGHeadGesturesLearnFrom(NSArray<NSData *> *motions, SGHeadAxis axis);

UIViewController *SGHeadGesturesSettingsPage(void);
// What the Status row reads out: why it is or is not listening.
NSString *SGHeadGestureStatus(void);
// The teaching sheet over `owner`; `closed` runs once it is gone, whatever it stored.
void SGPresentHeadGesturesTeaching(UIViewController *owner, void (^closed)(void));

// Head motion for another feature, under `name`; a nil handler takes it out. While any listener is in, the
// manager runs whatever the gestures' switch says. A handler is called on the motion's serial queue with every
// motion, and with nil when the motion stops: the headphones gone, the manager stopped, or the listener taken out.
void SGHeadMotionListen(NSString *name, void (^handler)(CMDeviceMotion *motion));
// Asks for Motion & Fitness now, while a page is in front, if it was never asked and nothing listens yet.
void SGHeadMotionAskPermission(void);
