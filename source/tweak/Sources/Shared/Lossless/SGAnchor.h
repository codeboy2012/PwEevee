#pragma once
#import <Foundation/Foundation.h>
#import "SGAnchorRing.h"

#if SG_DRIVER
// Main thread only. The event's epoch and host time are captured where it happened.
void SGAnchorLog(NSString *kind, NSString *evidence, uint64_t epoch, uint64_t host);
// SpeedPitch owns the rings; only the diagnostic's main-thread drain calls this.
bool SGPlayerAnchorRead(SGAnchorSample *latest, unsigned *dropped);
double SGPlayerAnchorLatency(bool *engaged);
#else
static inline void SGAnchorLog(NSString *kind, NSString *evidence, uint64_t epoch, uint64_t host) {}
#endif
