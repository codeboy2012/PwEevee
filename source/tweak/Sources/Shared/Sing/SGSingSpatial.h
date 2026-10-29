#pragma once
#include <math.h>
#include <stdbool.h>

typedef struct {
    bool hasFront;
    double front, last;
} SGSpatialFront;

static inline double SGSpatialVoiceAngle(SGSpatialFront *front, double yaw, double time, double frontSeconds) {
    const double motionGap = 1;
    double since = time - front->last;
    if (!front->hasFront || since < 0 || since > motionGap) {
        front->front = yaw;
    } else {
        front->front = remainder(front->front + remainder(yaw - front->front, 2 * M_PI) *
                                 (1 - exp(-3 * since / frontSeconds)), 2 * M_PI);
    }
    front->hasFront = true;
    front->last = time;
    return remainder(yaw - front->front, 2 * M_PI);
}
