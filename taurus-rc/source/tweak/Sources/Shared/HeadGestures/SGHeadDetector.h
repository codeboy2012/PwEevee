// AirPods gestures' eye: the head's attitude, as the headphones report it, turned into a double nod or a
// shake of the head.
//
// It works on how fast the head turns, worked out from one attitude to the next, so where the head
// rests does not matter and nothing drifts. A swing is the head turning one way faster than the axis's
// threshold; the next counts only once it turns the other way. Swings run together into a burst until
// the head has been still (under both thresholds) for a moment, and then the burst is read:
//
//   - a double nod is two downs and two ups of the pitch (4 or 5 swings, one for a settle), with at most
//     one swing sideways;
//   - a shake is 3 to 6 swings of the yaw with at most one of the pitch, quicker than a nod pair: a
//     glance left and right turns as far but holds at each side, and the hold ends the burst.
//
// A burst longer than a gesture takes is nobody's gesture (walking, running, looking around), and a gap
// in the samples (the headphones taken out, the updates stopped) starts over. After a gesture the
// detector waits a second before it takes another, so a gesture's own settle cannot fire a second one.
//
// Learning reads a few seconds of the user doing one gesture: the swings of its axis over a low floor,
// and the threshold set under the weakest of the swings the gesture needs, so the next one of the same
// size clears it with room to spare. The recording is then read again by a detector set to that
// threshold, and the threshold is kept only if the gesture fires. Teaching records five of the gesture,
// one at a time: each one's threshold is tried on all five, and the one that catches the most is kept,
// if it catches all of them but one at least.
//
// Plain C over a struct the caller owns, Foundation only, so the harness compiles it on the Mac as is.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGHeadGesture) {
    SGHeadGestureNone,
    SGHeadGestureDoubleNod,
    SGHeadGestureShake,
};

typedef NS_ENUM(NSInteger, SGHeadAxis) {
    SGHeadAxisPitch,   // a nod
    SGHeadAxisYaw,     // a shake
};

// Radians a second. The defaults are for someone who has not taught it yet: a brisk nod turns at 2 to
// 3, a walking head bobs at under 0.7.
#define SGHeadDefaultNod 1.1
#define SGHeadDefaultShake 1.4
// What learning will set at most and at least: under the least a walk would start to count.
#define SGHeadMinThreshold 0.8
#define SGHeadMaxThreshold 4.0

typedef struct {
    double nodThreshold, shakeThreshold;
    double lastTime, lastPitch, lastYaw;
    bool hasLast;
    int pitchSign, yawSign;          // the way the last swing went, 0 before a burst
    int pitchSwings, yawSwings;
    double burstStart, lastActive;   // the first swing, the last sample over either threshold
    double readyAt;                  // no gesture before this time
} SGHeadDetector;

void SGHeadDetectorReset(SGHeadDetector *detector, double nodThreshold, double shakeThreshold);
// One sample: seconds, then the attitude's pitch and yaw in radians. Answers the gesture it completes.
SGHeadGesture SGHeadDetectorFeed(SGHeadDetector *detector, double time, double pitch, double yaw);

// The threshold for `axis` learned from `count` samples of one gesture, or 0 when they do not hold
// one (too few swings, too slow to tell from a walk, or a move the detector does not read as the gesture
// at any threshold under its swings). `otherThreshold` is the other axis's, which the check runs with.
double SGHeadLearn(const double *time, const double *pitch, const double *yaw, int count, SGHeadAxis axis, double otherThreshold);

// One recording of a gesture: `count` samples of seconds, pitch and yaw.
typedef struct {
    const double *time, *pitch, *yaw;
    int count;
} SGHeadRecording;

// The threshold for `axis` learned from several recordings of the gesture, one each (the teaching sheet's
// five). What each teaches on its own (SGHeadLearn) is a candidate; the one the detector, set to it, fires
// on in the most recordings wins, the lowest of a tie, so the smallest of them still counts. 0 when no
// candidate fires in `atLeast` of them.
double SGHeadLearnSamples(const SGHeadRecording *recordings, int n, SGHeadAxis axis, double otherThreshold, int atLeast);
