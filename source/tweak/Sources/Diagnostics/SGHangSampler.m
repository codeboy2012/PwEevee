#import <mach/mach.h>
#import <mach/mach_time.h>
#import <pthread.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "SGHangSampler.h"

static const double kThreshold = 0.12, kInterval = 0.08;
static const useconds_t kTick = 10000;
enum { kMaxFrames = 40, kMaxSamplesPerStall = 12 };
// Return addresses signed by pointer authentication keep their address in the low bits.
static const uintptr_t kAddressMask = 0x0000007FFFFFFFFFull;

static mach_port_t sg_main;
static uintptr_t sg_stackLow, sg_stackHigh;
static atomic_int sg_watches;
static atomic_uint_fast64_t sg_pending;   // mach time of the ping not answered yet, 0 when none
static atomic_bool sg_running;
static NSString *sg_reason;

static double seconds(uint64_t mach) {
    static mach_timebase_info_data_t base;
    if (!base.denom) mach_timebase_info(&base);
    return (double)mach * base.numer / base.denom / 1e9;
}

// Nothing here may allocate or lock: the main thread is suspended and may hold either.
static int walk(uintptr_t frames[kMaxFrames]) {
    int n = 0;
    if (thread_suspend(sg_main) != KERN_SUCCESS) return 0;
    arm_thread_state64_t state;
    mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
    if (thread_get_state(sg_main, ARM_THREAD_STATE64, (thread_state_t)&state, &count) == KERN_SUCCESS) {
        frames[n++] = (uintptr_t)arm_thread_state64_get_pc(state) & kAddressMask;
        frames[n++] = (uintptr_t)arm_thread_state64_get_lr(state) & kAddressMask;
        uintptr_t fp = (uintptr_t)arm_thread_state64_get_fp(state);
        while (fp && n < kMaxFrames && fp >= sg_stackLow && fp + 2 * sizeof(uintptr_t) <= sg_stackHigh && !(fp & 0x7)) {
            uintptr_t next = ((uintptr_t *)fp)[0];
            uintptr_t ret = ((uintptr_t *)fp)[1] & kAddressMask;
            if (ret) frames[n++] = ret;
            if (next <= fp) break;
            fp = next;
        }
    }
    thread_resume(sg_main);
    return n;
}

static NSString *describe(uintptr_t address) {
    Dl_info info;
    if (!dladdr((void *)address, &info) || !info.dli_fname) return [NSString stringWithFormat:@"? 0x%lx", (unsigned long)address];
    const char *slash = strrchr(info.dli_fname, '/');
    NSString *image = @(slash ? slash + 1 : info.dli_fname);
    if ([image isEqualToString:@"Spotify"]) {
        intptr_t slide = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            if (strcmp(_dyld_get_image_name(i), info.dli_fname) == 0) {
                slide = _dyld_get_image_vmaddr_slide(i);
                break;
            }
        }
        return [NSString stringWithFormat:@"Spotify 0x%lx", (unsigned long)(address - slide)];
    }
    if (info.dli_sname && strcmp(info.dli_sname, "<redacted>") != 0) {
        return [NSString stringWithFormat:@"%@ %s+%lu", image, info.dli_sname, (unsigned long)(address - (uintptr_t)info.dli_saddr)];
    }
    return [NSString stringWithFormat:@"%@ +0x%lx", image, (unsigned long)(address - (uintptr_t)info.dli_saddr)];
}

static void logSample(uintptr_t frames[kMaxFrames], int count, double stalled, int index, NSString *reason) {
    NSMutableString *text = [NSMutableString stringWithFormat:@"stalled %.0f ms, sample %d\n", stalled * 1000, index];
    for (int i = 0; i < count; i++) [text appendFormat:@"%@\n", describe(frames[i])];
    SGLogLong([NSString stringWithFormat:@"hang %@", reason], text);
}

static void *watch(void *unused) {
    uint64_t sampledStall = 0;
    int samples = 0;
    double lastSample = 0;
    for (;;) {
    while (atomic_load(&sg_watches) > 0) {
        uint64_t pending = atomic_load(&sg_pending);
        uint64_t now = mach_absolute_time();
        if (!pending) {
            atomic_store(&sg_pending, now);
            dispatch_async(dispatch_get_main_queue(), ^{ atomic_store(&sg_pending, 0); });
        } else {
            double stalled = seconds(now - pending);
            if (stalled >= kThreshold) {
                if (sampledStall != pending) {
                    sampledStall = pending;
                    samples = 0;
                    lastSample = 0;
                }
                if (samples < kMaxSamplesPerStall && stalled - lastSample >= kInterval) {
                    uintptr_t frames[kMaxFrames];
                    int count = walk(frames);
                    samples++;
                    lastSample = stalled;
                    if (count) logSample(frames, count, stalled, samples, sg_reason);
                }
            }
        }
        usleep(kTick);
    }
    atomic_store(&sg_running, false);
    // A watch opened while this thread was on its way out finds it still marked running and starts none.
    if (atomic_load(&sg_watches) > 0 && !atomic_exchange(&sg_running, true)) continue;
    break;
    }
    return NULL;
}

void SGHangSamplerStart(NSString *reason, NSTimeInterval duration) {
    if (!NSThread.isMainThread) return;
    if (!sg_main) {
        sg_main = mach_thread_self();
        pthread_t main = pthread_self();
        sg_stackHigh = (uintptr_t)pthread_get_stackaddr_np(main);
        sg_stackLow = sg_stackHigh - pthread_get_stacksize_np(main);
    }
    sg_reason = [reason copy];
    atomic_fetch_add(&sg_watches, 1);
    if (!atomic_exchange(&sg_running, true)) {
        pthread_t thread;
        if (pthread_create(&thread, NULL, watch, NULL) == 0) pthread_detach(thread);
        else atomic_store(&sg_running, false);
        SGLog(@"hang: sampling the main thread (%@)", reason);
    }
    if (duration > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGHangSamplerStop(); });
    }
}

void SGHangSamplerStop(void) {
    if (atomic_load(&sg_watches) > 0) atomic_fetch_sub(&sg_watches, 1);
}
