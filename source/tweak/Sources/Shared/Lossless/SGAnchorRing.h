#pragma once
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>

#if SG_DRIVER
// One producer per output, one control-thread reader. Slots are never reset or freed.
// A full ring drops the new sample. The reader reports that loss with its next line.
_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2, "anchor flags must be lock-free");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "anchor epochs must be lock-free");
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "anchor indices must be lock-free");
enum { kSGAnchorCapacity = 256 };
typedef struct {
    double sourceFrame, rate;
    uint64_t host, epoch, output;
    uint32_t frames;
    int32_t status;
    bool silent;
} SGAnchorSample;
typedef struct {
    SGAnchorSample samples[kSGAnchorCapacity];
    atomic_uint read, write, dropped;
    uint64_t lastEpoch;
    unsigned pulls;
} SGAnchorRing;

static inline bool SGAnchorPush(SGAnchorRing *ring, SGAnchorSample sample) {
    unsigned write = atomic_load_explicit(&ring->write, memory_order_relaxed);
    unsigned read = atomic_load_explicit(&ring->read, memory_order_acquire);
    if (write - read == kSGAnchorCapacity) {
        atomic_fetch_add_explicit(&ring->dropped, 1, memory_order_relaxed);
        return false;
    }
    ring->samples[write % kSGAnchorCapacity] = sample;
    atomic_store_explicit(&ring->write, write + 1, memory_order_release);
    return true;
}

static inline bool SGAnchorPop(SGAnchorRing *ring, SGAnchorSample *sample) {
    unsigned read = atomic_load_explicit(&ring->read, memory_order_relaxed);
    if (read == atomic_load_explicit(&ring->write, memory_order_acquire)) return false;
    *sample = ring->samples[read % kSGAnchorCapacity];
    atomic_store_explicit(&ring->read, read + 1, memory_order_release);
    return true;
}
#endif
