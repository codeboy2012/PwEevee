#import "SGPCMReplacement.h"
#import <stdatomic.h>
#import <pthread.h>
#include <math.h>

typedef struct Snapshot {
    CFTypeRef owner;
    const float *left, *right;
    AudioUnit output;
    double rate;
    uint64_t epoch, sourceFrame, assetFrame, length;
    struct Snapshot *next;
} Snapshot;

static _Atomic(Snapshot *) sg_active;
static atomic_uint sg_readers;
static atomic_uint_fast64_t sg_replaced;
static pthread_mutex_t sg_control = PTHREAD_MUTEX_INITIALIZER; // never acquired on render
static Snapshot *sg_retired;
static unsigned sg_retiredCount;
static BOOL sg_reclaimScheduled;

static void reclaim(void) {
    // Sequential consistency is required: a reader increments before loading active; a writer
    // exchanges active before checking readers. A future reader can only see the new snapshot.
    if (atomic_load(&sg_readers)) return;
    while (sg_retired) {
        Snapshot *old = sg_retired; sg_retired = old->next;
        CFRelease(old->owner); free(old); --sg_retiredCount;
    }
}
static void scheduleReclaim(void) {
    if (sg_reclaimScheduled || !sg_retired) return;
    sg_reclaimScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        pthread_mutex_lock(&sg_control);
        sg_reclaimScheduled = NO;
        reclaim(); scheduleReclaim();
        pthread_mutex_unlock(&sg_control);
    });
}
static void retire(Snapshot *old) {
    if (old) { old->next = sg_retired; sg_retired = old; ++sg_retiredCount; }
    reclaim(); scheduleReclaim();
}
void SGPCMReplacementEnable(void) { SGPlayerSetSourceSelector(SGPCMReplacementApply); }
BOOL SGPCMReplacementInstall(SGPreparedPCM *asset, AudioUnit output, uint64_t epoch,
                             uint64_t sourceFrame, uint64_t assetFrame) {
    if (!asset || !output || !epoch || assetFrame >= asset.frameCount || sourceFrame >= (1ULL<<53)) return NO;
    pthread_mutex_lock(&sg_control);
    reclaim();
    if (epoch != SGPlayerSourceEpoch() || sg_retiredCount >= 2) { pthread_mutex_unlock(&sg_control); return NO; }
    Snapshot *next = calloc(1, sizeof(*next));
    if (!next) { pthread_mutex_unlock(&sg_control); return NO; }
    next->owner = CFBridgingRetain(asset);
    next->left = asset.left; next->right = asset.right; next->length = asset.frameCount;
    next->rate = asset.sampleRate; next->output = output; next->epoch = epoch;
    next->sourceFrame = sourceFrame; next->assetFrame = assetFrame;
    retire(atomic_exchange(&sg_active, next));
    pthread_mutex_unlock(&sg_control);
    return YES;
}
void SGPCMReplacementCancel(void) {
    pthread_mutex_lock(&sg_control);
    SGPlayerInvalidateSource();
    retire(atomic_exchange(&sg_active, NULL));
    pthread_mutex_unlock(&sg_control);
}
uint64_t SGPCMReplacementFrames(void) { return atomic_load(&sg_replaced); }
void SGPCMReplacementApply(AudioUnit output, uint64_t epoch, double sourceFrame,
                           double sampleRate, UInt32 frames, AudioBufferList *data) {
    atomic_fetch_add(&sg_readers, 1);
    Snapshot *s = atomic_load(&sg_active);
    if (!s || !frames || !data || data->mNumberBuffers != 2 || output != s->output || epoch != s->epoch
        || epoch != SGPlayerSourceEpoch() || sampleRate != s->rate || !isfinite(sourceFrame)
        || sourceFrame < s->sourceFrame || sourceFrame >= (double)(1ULL<<53) || floor(sourceFrame) != sourceFrame) goto done;
    uint64_t delta = (uint64_t)sourceFrame - s->sourceFrame;
    if (delta > s->length - s->assetFrame || frames > s->length - s->assetFrame - delta) goto done;
    for (UInt32 b = 0; b < 2; ++b) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mNumberChannels != 1
            || data->mBuffers[b].mDataByteSize / sizeof(float) < frames) goto done;
    }
    uint64_t at = s->assetFrame + delta;
    memcpy(data->mBuffers[0].mData, s->left+at, frames*sizeof(float));
    memcpy(data->mBuffers[1].mData, s->right+at, frames*sizeof(float));
    atomic_fetch_add(&sg_replaced, frames);
done:
    atomic_fetch_sub(&sg_readers, 1);
}
