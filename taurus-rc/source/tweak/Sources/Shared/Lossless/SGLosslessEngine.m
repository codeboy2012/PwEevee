// The anchor comes from the sound itself: a few seconds of Spotify's own output are matched against the file by
// cross-correlation, so Spotify's position reports (1.2 s off after a false stall at 1.5x) only narrow the search.
//
// The file is never decoded whole. The search runs on a copy at 1/16 of the rate (about 2 MB for a 3 minute song)
// and is made exact on a short window read at full rate. Playback reads from a ring that a worker fills ahead of
// where Spotify plays; a block the ring does not hold yet keeps Spotify's sound.
#import "SGLossless.h"
#import "Core/SGCore.h"
#import "Shared/Player/SpeedPitch.h"
#import <Accelerate/Accelerate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <stdatomic.h>

enum { kIdle, kArmed, kFull };
enum { kCoarse = 16 };                      // decimation for the coarse search
enum { kRing = 1 << 19 };                   // frames the ring holds, about 12 s at 44.1 kHz
enum { kChunk = 8192 };                     // frames per read
static const double kAnchorSeconds = 4, kCheckSeconds = 1, kHintWindow = 8;
static const float kMinMatch = 0.8f;        // normalized correlation below this is another recording or master

#pragma mark - capture (render thread writes while armed)

static float *sg_cap;
static uint32_t sg_capLength;
static _Atomic uint32_t sg_capFill;
static _Atomic int sg_capState;
static uint64_t sg_capStart, sg_capEpoch, sg_capNext;
static AudioUnit sg_capUnit;
static double sg_capRate;

static void capture(AudioUnit output, uint64_t epoch, double sourceFrame, double rate, UInt32 frames, AudioBufferList *data) {
    if (atomic_load(&sg_capState) != kArmed) return;
    const float *l = data->mBuffers[0].mData, *r = data->mBuffers[1].mData;
    uint32_t fill = atomic_load(&sg_capFill);
    if (fill && ((uint64_t)sourceFrame != sg_capNext || epoch != sg_capEpoch || output != sg_capUnit)) fill = 0;
    if (!fill) { sg_capStart = (uint64_t)sourceFrame; sg_capEpoch = epoch; sg_capUnit = output; sg_capRate = rate; }
    UInt32 n = MIN(frames, sg_capLength - fill);
    for (UInt32 i = 0; i < n; i++) sg_cap[fill + i] = 0.5f * (l[i] + r[i]);
    sg_capNext = (uint64_t)sourceFrame + frames;
    atomic_store(&sg_capFill, fill + n);
    if (fill + n == sg_capLength) atomic_store(&sg_capState, kFull);
}

#pragma mark - the ring (static, never freed: a render call never reads freed memory)

static float sg_ringL[kRing], sg_ringR[kRing];
// File frames [start, end) are in the ring, frame f at f % kRing. The writer moves both forward only.
static _Atomic uint64_t sg_ringStart, sg_ringEnd;
// Where the render thread reads, so the writer never overwrites it.
static _Atomic uint64_t sg_readAt;

static bool ringRead(uint64_t at, UInt32 frames, float *l, float *r) {
    atomic_store_explicit(&sg_readAt, at, memory_order_relaxed);
    uint64_t start = atomic_load(&sg_ringStart), end = atomic_load(&sg_ringEnd);
    if (at < start || at + frames > end || frames > kRing) return false;
    uint64_t i = at % kRing;
    UInt32 first = (UInt32)MIN((uint64_t)frames, kRing - i);
    memcpy(l, sg_ringL + i, first * sizeof(float));
    memcpy(r, sg_ringR + i, first * sizeof(float));
    memcpy(l + first, sg_ringL, (frames - first) * sizeof(float));
    memcpy(r + first, sg_ringR, (frames - first) * sizeof(float));
    return true;
}

#pragma mark - what plays (set off render only while no reader is admitted)

static atomic_bool sg_live;
static atomic_uint sg_readers;
static uint64_t sg_playEpoch, sg_playSource, sg_playAsset;
static AudioUnit sg_playUnit;
static double sg_playRate;
static _Atomic uint32_t sg_gainBits;
static _Atomic uint64_t sg_replaced;

static void selector(AudioUnit output, uint64_t epoch, double sourceFrame, double rate, UInt32 frames, AudioBufferList *data) {
    if (data->mNumberBuffers != 2 || !data->mBuffers[0].mData || !data->mBuffers[1].mData
        || data->mBuffers[0].mDataByteSize < frames * sizeof(float) || data->mBuffers[1].mDataByteSize < frames * sizeof(float)) return;
    capture(output, epoch, sourceFrame, rate, frames, data);
    atomic_fetch_add(&sg_readers, 1);
    if (atomic_load(&sg_live) && epoch == sg_playEpoch && epoch == SGPlayerSourceEpoch() && output == sg_playUnit
        && rate == sg_playRate && sourceFrame >= sg_playSource) {
        uint64_t at = sg_playAsset + ((uint64_t)sourceFrame - sg_playSource);
        float *l = data->mBuffers[0].mData, *r = data->mBuffers[1].mData;
        if (ringRead(at, frames, l, r)) {
            uint32_t bits = atomic_load(&sg_gainBits);
            float gain;
            memcpy(&gain, &bits, sizeof gain);
            vDSP_vsmul(l, 1, &gain, l, 1, frames);
            vDSP_vsmul(r, 1, &gain, r, 1, frames);
            atomic_fetch_add_explicit(&sg_replaced, frames, memory_order_relaxed);
        }
    }
    atomic_fetch_sub(&sg_readers, 1);
}

// Off render: no reader is inside the play fields after this returns.
static void quiesce(void) {
    atomic_store(&sg_live, false);
    while (atomic_load(&sg_readers)) usleep(100);
}

#pragma mark - the file

typedef struct {
    ExtAudioFileRef file;
    double fileRate, rate;
    uint64_t frames;                        // at the client rate
} Reader;

static void closeReader(Reader *reader) {
    if (reader->file) ExtAudioFileDispose(reader->file);
    *reader = (Reader){0};
}

static BOOL openReader(Reader *reader, NSString *path, double rate, NSString **error) {
    closeReader(reader);
    ExtAudioFileRef file;
    if (ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], &file)) { *error = @"the file does not open"; return NO; }
    AudioStreamBasicDescription source = {0};
    UInt32 size = sizeof source;
    SInt64 frames = 0;
    OSStatus status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source);
    size = sizeof frames;
    if (!status) status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &frames);
    BOOL lossless = source.mFormatID == kAudioFormatFLAC || source.mFormatID == kAudioFormatAppleLossless;
    AudioStreamBasicDescription client = {rate, kAudioFormatLinearPCM,
        kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    if (!status && lossless && source.mChannelsPerFrame == 2 && frames > 0)
        status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof client, &client);
    if (status || !lossless || source.mChannelsPerFrame != 2 || frames <= 0) {
        ExtAudioFileDispose(file);
        *error = @"not stereo FLAC or ALAC";
        return NO;
    }
    *reader = (Reader){file, source.mSampleRate, rate, (uint64_t)floor(frames * rate / source.mSampleRate)};
    return YES;
}

// Up to `count` frames from file frame `at` into l and r; the frames read (0 at the end).
static UInt32 readAt(Reader *reader, uint64_t at, UInt32 count, float *l, float *r, BOOL seek) {
    if (seek && ExtAudioFileSeek(reader->file, (SInt64)llround(at * reader->fileRate / reader->rate))) return 0;
    struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, count * 4, l}}}, {1, count * 4, r}};
    UInt32 frames = count;
    if (ExtAudioFileRead(reader->file, &frames, &buffers.list)) return 0;
    return frames;
}

// Mono of file frames [from, from + count), silence outside the file. The caller frees it.
static float *readMono(Reader *reader, int64_t from, uint32_t count) {
    float *mono = calloc(count, sizeof(float)), *l = malloc(kChunk * sizeof(float)), *r = malloc(kChunk * sizeof(float));
    int64_t at = MAX(from, 0);
    BOOL seek = YES;
    while (at < from + count && (uint64_t)at < reader->frames) {
        UInt32 want = (UInt32)MIN((int64_t)kChunk, from + count - at);
        UInt32 got = readAt(reader, at, want, l, r, seek);
        if (!got) break;
        seek = NO;
        for (UInt32 i = 0; i < got; i++) mono[at - from + i] = 0.5f * (l[i] + r[i]);
        at += got;
    }
    free(l); free(r);
    return mono;
}

#pragma mark - the anchor's queue owns these

static dispatch_queue_t sg_queue;
static NSString *sg_path;
static Reader sg_reader;                    // for searches and checks
static float *sg_coarse;                    // the file's mono at 1/kCoarse of the rate
static uint64_t sg_coarseCount;
static _Atomic uint64_t sg_anchorEpoch;
static _Atomic uint64_t sg_generation;      // the writer stops when this changes
static atomic_uint sg_writers;              // writers still running

static void drop(void) {
    closeReader(&sg_reader);
    free(sg_coarse);
    sg_coarse = NULL;
    sg_coarseCount = 0;
    sg_path = nil;
}

static BOOL load(NSString *path, double rate, NSString **error) {
    if (sg_coarse && [sg_path isEqualToString:path] && sg_reader.rate == rate) return YES;
    drop();
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    if (!openReader(&sg_reader, path, rate, error)) return NO;
    sg_coarseCount = sg_reader.frames / kCoarse;
    sg_coarse = calloc(sg_coarseCount + 1, sizeof(float));
    float *l = malloc(kChunk * sizeof(float)), *r = malloc(kChunk * sizeof(float));
    float sum = 0;
    uint64_t at = 0;
    BOOL seek = YES;
    for (UInt32 got; (got = readAt(&sg_reader, at, kChunk, l, r, seek)); at += got) {
        seek = NO;
        for (UInt32 i = 0; i < got; i++) {
            uint64_t f = at + i;
            sum += 0.5f * (l[i] + r[i]);
            if (f % kCoarse == kCoarse - 1) {
                if (f / kCoarse < sg_coarseCount) sg_coarse[f / kCoarse] = sum / kCoarse;
                sum = 0;
            }
        }
    }
    free(l); free(r);
    sg_path = path;
    SGLog(@"lossless: read %@, %llu frames at %.0f Hz in %.2f s", path.lastPathComponent, at, rate, CFAbsoluteTimeGetCurrent() - start);
    if (at + kChunk < sg_reader.frames) { *error = @"the file ended early"; drop(); return NO; }
    return YES;
}

static float dot(const float *a, const float *b, vDSP_Length n) {
    float d;
    vDSP_dotpr(a, 1, b, 1, &d, n);
    return d;
}

// Normalized correlation of `capture` against `window` (both n long), and the gain that maps the file onto it.
static float match(const float *capture, const float *window, vDSP_Length n, float *gain) {
    float cc = dot(capture, window, n), aa = dot(window, window, n), ss = dot(capture, capture, n);
    if (gain) *gain = aa > 0 ? cc / aa : 0;
    return aa > 0 && ss > 0 ? cc / sqrtf(aa * ss) : 0;
}

// The file frame within [from, to] whose following frames best match the capture, read at full rate.
static uint64_t refine(int64_t from, int64_t to, float *score, float *gain) {
    from = MAX(from, 0);
    to = MAX(from, MIN(to, (int64_t)sg_reader.frames - (int64_t)sg_capLength));
    uint32_t span = (uint32_t)(to - from) + sg_capLength;
    float *window = readMono(&sg_reader, from, span);
    uint64_t best = from;
    *score = -2;
    for (int64_t lag = from; lag <= to; lag++) {
        float s = match(sg_cap, window + (lag - from), sg_capLength, NULL);
        if (s > *score) { *score = s; best = lag; }
    }
    match(sg_cap, window + (best - from), sg_capLength, gain);
    free(window);
    return best;
}

// Coarse search of file frames [from, to), then exact around the winner.
static uint64_t search(uint64_t from, uint64_t to, float *score, float *gain) {
    uint64_t lo = from / kCoarse, hi = MIN(to / kCoarse, sg_coarseCount);
    vDSP_Length capN = sg_capLength / kCoarse;
    if (hi <= lo || hi - lo <= capN) { *score = 0; return 0; }
    float *cap = malloc(capN * sizeof(float));
    float filter[kCoarse], one = 1.0f / kCoarse;
    vDSP_vfill(&one, filter, 1, kCoarse);
    vDSP_desamp(sg_cap, kCoarse, filter, cap, capN, kCoarse);
    const float *file = sg_coarse + lo;
    vDSP_Length fileN = hi - lo, lags = fileN - capN + 1;
    float *corr = malloc(lags * sizeof(float));
    vDSP_conv(file, 1, cap, 1, corr, 1, lags, capN);
    double running = 0;
    for (vDSP_Length i = 0; i < capN; i++) running += (double)file[i] * file[i];
    vDSP_Length coarse = 0;
    float best = -INFINITY;
    for (vDSP_Length i = 0; i < lags; i++) {
        float s = running > 1e-9 ? corr[i] / sqrtf((float)running) : 0;
        if (s > best) { best = s; coarse = i; }
        if (i + capN < fileN) running += (double)file[i + capN] * file[i + capN] - (double)file[i] * file[i];
    }
    free(cap); free(corr);
    int64_t center = (int64_t)(lo + coarse) * kCoarse;
    return refine(center - 2 * kCoarse, center + 2 * kCoarse, score, gain);
}

// Records `seconds` of Spotify's sound in one unbroken run; NO after the timeout.
static BOOL record(double seconds, NSString **error) {
    static float *storage;
    if (!storage) storage = malloc((size_t)(kAnchorSeconds * 96000) * sizeof(float));
    sg_cap = storage;
    atomic_store(&sg_capState, kIdle);
    sg_capLength = (uint32_t)(MIN(seconds, kAnchorSeconds) * MIN(sg_capRate > 0 ? sg_capRate : 44100, 96000));
    atomic_store(&sg_capFill, 0);
    atomic_store(&sg_capState, kArmed);
    for (int i = 0; i < (int)(seconds * 20) + 60 && atomic_load(&sg_capState) != kFull; i++) usleep(50000);
    if (atomic_load(&sg_capState) == kFull) return YES;
    atomic_store(&sg_capState, kIdle);
    *error = @"Spotify's sound did not run unbroken long enough";
    return NO;
}

#pragma mark - the writer

// Fills the ring from where the render thread reads until the generation changes or the file ends.
static void fill(NSString *path, double rate, uint64_t from, uint64_t generation) {
    Reader reader = {0};
    NSString *error;
    if (!openReader(&reader, path, rate, &error)) {
        SGLog(@"lossless: the writer could not open the file: %@", error);
        atomic_fetch_sub(&sg_writers, 1);
        return;
    }
    float *l = malloc(kChunk * sizeof(float)), *r = malloc(kChunk * sizeof(float));
    uint64_t end = from;
    BOOL seek = YES;
    while (atomic_load(&sg_generation) == generation) {
        uint64_t reading = MAX(atomic_load_explicit(&sg_readAt, memory_order_relaxed), atomic_load(&sg_ringStart));
        if (reading > end + (uint64_t)rate) {
            // Spotify plays ahead of what the ring holds: start again where it plays.
            end = reading + (uint64_t)(rate / 4);
            atomic_store(&sg_ringStart, end);
            atomic_store(&sg_ringEnd, end);
            seek = YES;
        }
        if (end + kChunk > reading + kRing - kChunk) { usleep(20000); continue; }
        UInt32 got = readAt(&reader, end, kChunk, l, r, seek);
        if (!got) break;
        seek = NO;
        uint64_t i = end % kRing;
        UInt32 first = (UInt32)MIN((uint64_t)got, kRing - i);
        memcpy(sg_ringL + i, l, first * sizeof(float));
        memcpy(sg_ringR + i, r, first * sizeof(float));
        memcpy(sg_ringL, l + first, (got - first) * sizeof(float));
        memcpy(sg_ringR, r + first, (got - first) * sizeof(float));
        end += got;
        // Frames the writer passed out of the ring's reach are gone.
        if (end > kRing && atomic_load(&sg_ringStart) < end - kRing) atomic_store(&sg_ringStart, end - kRing);
        atomic_store(&sg_ringEnd, end);
    }
    free(l); free(r);
    closeReader(&reader);
    atomic_fetch_sub(&sg_writers, 1);
}

#pragma mark - anchor, check, stop

static void stopPlaying(void) {
    atomic_fetch_add(&sg_generation, 1);
    quiesce();
    // A writer of the last anchor still inside its loop would write into the ring the next one resets.
    while (atomic_load(&sg_writers)) usleep(1000);
    atomic_store(&sg_anchorEpoch, 0);
}

static NSDictionary *anchor(NSString *path, double hint, NSString **error) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGPlayerSetSourceSelector(selector); });
    stopPlaying();
    if (!record(kAnchorSeconds, error)) return nil;
    double rate = sg_capRate;
    if (!load(path, rate, error)) return nil;
    if (sg_reader.frames <= sg_capLength) { *error = @"the file is shorter than the capture"; return nil; }

    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    uint64_t from = 0, to = sg_reader.frames;
    if (hint >= 0) {
        from = (uint64_t)MAX(0, (hint - kHintWindow) * rate);
        to = (uint64_t)((hint + kHintWindow + kAnchorSeconds) * rate);
        if (from + sg_capLength >= sg_reader.frames) { *error = @"Spotify plays past the end of the file"; return nil; }
    }
    float score, gain;
    uint64_t lag = search(from, to, &score, &gain);
    double took = CFAbsoluteTimeGetCurrent() - start;
    SGLog(@"lossless: match %.4f at file %.3f s (hint %.1f s), gain %.3f, search %.2f s", score, lag / rate, hint, gain, took);
    if (score < kMinMatch) { *error = [NSString stringWithFormat:@"no match (%.3f)", score]; return nil; }
    if (sg_capEpoch != SGPlayerSourceEpoch()) { *error = @"the source changed while matching"; return nil; }

    uint32_t bits;
    memcpy(&bits, &gain, sizeof bits);
    atomic_store(&sg_gainBits, bits);
    sg_playEpoch = sg_capEpoch;
    sg_playSource = sg_capStart;
    sg_playAsset = lag;
    sg_playUnit = sg_capUnit;
    sg_playRate = rate;
    // The writer starts where Spotify plays by now, so the ring is not filled with frames already gone.
    uint64_t now = lag + (sg_capNext - sg_capStart);
    atomic_store(&sg_ringStart, now);
    atomic_store(&sg_ringEnd, now);
    atomic_store(&sg_readAt, now);
    uint64_t generation = atomic_load(&sg_generation);
    atomic_fetch_add(&sg_writers, 1);
    // Its own thread: it runs for the rest of the song, which would hold a shared queue's thread that long.
    NSThread *writer = [[NSThread alloc] initWithBlock:^{ fill(path, rate, now, generation); }];
    writer.qualityOfService = NSQualityOfServiceUserInitiated;
    writer.name = @"spotifyglass.lossless.writer";
    [writer start];
    atomic_store(&sg_anchorEpoch, sg_capEpoch);
    atomic_store(&sg_live, true);
    return @{@"rate" : @(rate), @"file_frame" : @(lag), @"file_seconds" : @(lag / rate), @"match" : @(score),
             @"gain" : @(gain), @"search_s" : @(took)};
}

static NSDictionary *check(NSString **error) {
    uint64_t epoch = atomic_load(&sg_anchorEpoch);
    if (!sg_coarse || !epoch) { *error = @"nothing anchored"; return nil; }
    NSMutableDictionary *result = [@{@"replaced_s" : @(atomic_load(&sg_replaced) / sg_reader.rate),
                                     @"epoch_current" : @(epoch == SGPlayerSourceEpoch())} mutableCopy];
    if (!record(kCheckSeconds, error)) return nil;
    if (sg_capUnit != sg_playUnit || sg_capEpoch != epoch) {
        result[@"note"] = @"the source changed since the anchor: Spotify plays its own sound again";
        return result;
    }
    int64_t expected = (int64_t)sg_playAsset + (int64_t)(sg_capStart - sg_playSource);
    if (expected + sg_capLength > sg_reader.frames) {
        result[@"note"] = @"past the end of the file";
        return result;
    }
    float score;
    uint64_t found = refine(expected - 2048, expected + 2048, &score, NULL);
    result[@"offset_frames"] = @((int64_t)found - expected);
    result[@"match"] = @(score);
    result[@"file_seconds"] = @(expected / sg_reader.rate);
    return result;
}

static dispatch_queue_t queue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sg_queue = dispatch_queue_create("spotifyglass.lossless", DISPATCH_QUEUE_SERIAL); });
    return sg_queue;
}

NSDictionary *SGLosslessAnchor(NSString *path, double hintSeconds, NSString **error) {
    __block NSDictionary *result;
    __block NSString *failure;
    dispatch_sync(queue(), ^{ NSString *e; result = anchor(path, hintSeconds, &e); failure = e; });
    *error = failure;
    return result;
}

NSDictionary *SGLosslessCheck(NSString **error) {
    __block NSDictionary *result;
    __block NSString *failure;
    dispatch_sync(queue(), ^{ NSString *e; result = check(&e); failure = e; });
    *error = failure;
    return result;
}

void SGLosslessStop(BOOL release) {
    atomic_fetch_add(&sg_generation, 1);
    atomic_store(&sg_live, false);
    atomic_store(&sg_anchorEpoch, 0);
    if (release) dispatch_async(queue(), ^{ drop(); });
}

BOOL SGLosslessPlaying(void) {
    uint64_t epoch = atomic_load(&sg_anchorEpoch);
    return epoch && epoch == SGPlayerSourceEpoch();
}
