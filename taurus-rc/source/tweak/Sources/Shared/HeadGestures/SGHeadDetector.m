#import "SGHeadDetector.h"

// Longer between two samples than this and the head's speed is a guess: start over. AirPods send 25 a
// second.
static const double kGap = 0.3;
// Still for this long and the burst is over.
static const double kQuiet = 0.35;
// The longest a gesture takes, first swing to last. A shake is quicker than two nods.
static const double kNodLength = 1.6;
static const double kShakeLength = 1.2;
static const double kCooldown = 1.0;
// Learning counts swings over this, under the least threshold, so a slow learner's swings are seen,
// and sets the threshold this far under the weakest swing the gesture needs.
static const double kLearnFloor = 0.5;
static const double kLearnMargin = 0.6;
// The spacing of the still samples learning adds after a recording, AirPods' own.
static const double kStillStep = 0.04;

static double wrapAngle(double angle) {
    return remainder(angle, 2 * M_PI);
}

static void endBurst(SGHeadDetector *d) {
    d->pitchSign = d->yawSign = 0;
    d->pitchSwings = d->yawSwings = 0;
}

void SGHeadDetectorReset(SGHeadDetector *d, double nodThreshold, double shakeThreshold) {
    memset(d, 0, sizeof *d);
    d->nodThreshold = nodThreshold;
    d->shakeThreshold = shakeThreshold;
}

// Counts a swing when `rate` is over `threshold` the other way from the last one.
static bool swing(double rate, double threshold, int *sign, int *swings) {
    if (fabs(rate) <= threshold) return false;
    int way = rate > 0 ? 1 : -1;
    if (way != *sign) {
        *sign = way;
        (*swings)++;
    }
    return true;
}

static SGHeadGesture readBurst(const SGHeadDetector *d) {
    double length = d->lastActive - d->burstStart;
    if (d->pitchSwings >= 4 && d->pitchSwings <= 5 && d->yawSwings <= 1 && length <= kNodLength) return SGHeadGestureDoubleNod;
    if (d->yawSwings >= 3 && d->yawSwings <= 6 && d->pitchSwings <= 1 && length <= kShakeLength) return SGHeadGestureShake;
    return SGHeadGestureNone;
}

SGHeadGesture SGHeadDetectorFeed(SGHeadDetector *d, double time, double pitch, double yaw) {
    double dt = time - d->lastTime;
    bool fresh = d->hasLast && dt > 0 && dt <= kGap;
    double pitchRate = fresh ? (pitch - d->lastPitch) / dt : 0;
    double yawRate = fresh ? wrapAngle(yaw - d->lastYaw) / dt : 0;
    d->lastTime = time;
    d->lastPitch = pitch;
    d->lastYaw = yaw;
    d->hasLast = true;
    if (!fresh) {
        endBurst(d);
        return SGHeadGestureNone;
    }

    bool inBurst = d->pitchSwings || d->yawSwings;
    bool pitchActive = swing(pitchRate, d->nodThreshold, &d->pitchSign, &d->pitchSwings);
    bool yawActive = swing(yawRate, d->shakeThreshold, &d->yawSign, &d->yawSwings);
    if (pitchActive || yawActive) {
        if (!inBurst) d->burstStart = time;
        d->lastActive = time;
        return SGHeadGestureNone;
    }
    if (!inBurst || time - d->lastActive < kQuiet) return SGHeadGestureNone;

    SGHeadGesture gesture = readBurst(d);
    endBurst(d);
    // A burst that began inside the cooldown is the last gesture's settle, or a repeat too quick to mean.
    if (gesture == SGHeadGestureNone || d->burstStart < d->readyAt) return SGHeadGestureNone;
    d->readyAt = time + kCooldown;
    return gesture;
}

static int descending(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? 1 : x > y ? -1 : 0;
}

// Whether the detector, at these thresholds, fires the gesture of `axis` on the samples and nothing else.
// Still samples follow the last one, so a gesture made at the very end of the recording is read too.
static bool fires(const double *time, const double *pitch, const double *yaw, int count, SGHeadAxis axis,
                  double nodThreshold, double shakeThreshold) {
    if (count < 1) return false;
    SGHeadGesture want = axis == SGHeadAxisPitch ? SGHeadGestureDoubleNod : SGHeadGestureShake;
    SGHeadDetector d;
    SGHeadDetectorReset(&d, nodThreshold, shakeThreshold);
    bool wanted = false;
    for (int i = 0; i < count; i++) {
        SGHeadGesture gesture = SGHeadDetectorFeed(&d, time[i], pitch[i], yaw[i]);
        if (gesture != SGHeadGestureNone && gesture != want) return false;
        wanted = wanted || gesture == want;
    }
    for (double t = time[count - 1] + kStillStep; t <= time[count - 1] + kQuiet + 2 * kStillStep; t += kStillStep) {
        SGHeadGesture gesture = SGHeadDetectorFeed(&d, t, pitch[count - 1], yaw[count - 1]);
        if (gesture != SGHeadGestureNone && gesture != want) return false;
        wanted = wanted || gesture == want;
    }
    return wanted;
}

double SGHeadLearn(const double *time, const double *pitch, const double *yaw, int count, SGHeadAxis axis, double otherThreshold) {
    const double *angle = axis == SGHeadAxisPitch ? pitch : yaw;
    int needed = axis == SGHeadAxisPitch ? 4 : 3;
    double *peaks = calloc(count > 0 ? count : 1, sizeof *peaks);
    int lobes = 0, sign = 0;
    for (int i = 1; i < count; i++) {
        double dt = time[i] - time[i - 1];
        if (dt <= 0 || dt > kGap) {
            sign = 0;
            continue;
        }
        double rate = wrapAngle(angle[i] - angle[i - 1]) / dt;
        if (fabs(rate) <= kLearnFloor) continue;
        int way = rate > 0 ? 1 : -1;
        if (way != sign) {
            sign = way;
            peaks[lobes++] = 0;
        }
        peaks[lobes - 1] = fmax(peaks[lobes - 1], fabs(rate));
    }
    double weakest = 0;
    if (lobes >= needed) {
        qsort(peaks, lobes, sizeof *peaks, descending);
        weakest = peaks[needed - 1];
    }
    free(peaks);
    // Too slow to keep clear of a walk with any margin: not learned.
    if (weakest * kLearnMargin < SGHeadMinThreshold * 0.75) return 0;
    // A threshold is kept only once the detector, set to it, finds the gesture in what was recorded: a
    // low one can let the settle's swings count, which makes a nod pair too many swings, so a closer one
    // is tried before giving up. Too slow or too many moves for the detector, nothing is learned.
    for (double margin = kLearnMargin; margin < 0.95; margin += 0.1) {
        double threshold = fmin(SGHeadMaxThreshold, fmax(SGHeadMinThreshold, weakest * margin));
        double nod = axis == SGHeadAxisPitch ? threshold : otherThreshold;
        double shake = axis == SGHeadAxisPitch ? otherThreshold : threshold;
        if (fires(time, pitch, yaw, count, axis, nod, shake)) return threshold;
    }
    return 0;
}

double SGHeadLearnSamples(const SGHeadRecording *recordings, int n, SGHeadAxis axis, double otherThreshold, int atLeast) {
    double best = 0;
    int bestFired = 0;
    for (int c = 0; c < n; c++) {
        const SGHeadRecording *own = &recordings[c];
        double candidate = SGHeadLearn(own->time, own->pitch, own->yaw, own->count, axis, otherThreshold);
        if (candidate <= 0) continue;
        double nod = axis == SGHeadAxisPitch ? candidate : otherThreshold;
        double shake = axis == SGHeadAxisPitch ? otherThreshold : candidate;
        int fired = 0;
        for (int i = 0; i < n; i++) {
            const SGHeadRecording *r = &recordings[i];
            fired += fires(r->time, r->pitch, r->yaw, r->count, axis, nod, shake);
        }
        if (fired > bestFired || (fired == bestFired && candidate < best)) {
            best = candidate;
            bestFired = fired;
        }
    }
    return bestFired >= atLeast ? best : 0;
}
