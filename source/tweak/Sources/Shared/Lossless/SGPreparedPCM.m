#import "SGPreparedPCM.h"
#import <AudioToolbox/AudioToolbox.h>
#import <stdatomic.h>
#include <math.h>

@implementation SGPCMDecodeCancellation {
    atomic_bool _cancelled;
}
- (void)cancel { atomic_store(&_cancelled, true); }
- (BOOL)isCancelled { return atomic_load(&_cancelled); }
@end

static void fail(NSError **error, NSInteger code, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"PwEeveeLosslessDecode" code:code
                                      userInfo:@{NSLocalizedDescriptionKey:message}];
}

@implementation SGPreparedPCM {
    float *_storage;
    uint64_t _capacity;
}
+ (instancetype)prepareURL:(NSURL *)url sampleRate:(double)rate maxBytes:(NSUInteger)maxBytes
              cancellation:(SGPCMDecodeCancellation *)cancellation error:(NSError **)error {
    if (error) *error = nil;
    if (cancellation.cancelled) { fail(error, 1, @"Preparation cancelled."); return nil; }
    if (!url.isFileURL || !isfinite(rate) || rate < 8000 || rate > 192000 || maxBytes < 8192 || maxBytes > 32*1024*1024) {
        fail(error, 2, @"Unsupported file, sample rate or PCM budget."); return nil;
    }
    NSNumber *regular = nil, *fileSize = nil;
    [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
    [url getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
    if (!regular.boolValue || !fileSize || fileSize.unsignedLongLongValue > 64*1024*1024) {
        fail(error, 2, @"Expected a complete local file within the encoded size limit."); return nil;
    }
    ExtAudioFileRef file = NULL;
    OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef)url, &file);
    if (status) { fail(error, status, @"The native decoder could not open the file."); return nil; }
    AudioStreamBasicDescription source = {0}; UInt32 size = sizeof(source);
    status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source);
    SInt64 sourceFrames = 0; size = sizeof(sourceFrames);
    if (!status) status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &sourceFrames);
    BOOL formatOK = (source.mFormatID == kAudioFormatFLAC || source.mFormatID == kAudioFormatAppleLossless)
        && source.mChannelsPerFrame == 2 && isfinite(source.mSampleRate) && source.mSampleRate >= 8000
        && source.mSampleRate <= 192000 && sourceFrames > 0;
    double expected = formatOK ? ceil(sourceFrames * rate / source.mSampleRate) : 0;
    uint64_t limit = maxBytes / (2 * sizeof(float));
    if (status || !formatOK || !isfinite(expected) || expected < 1 || expected > limit) {
        ExtAudioFileDispose(file);
        fail(error, status ?: 3, @"The file is not supported stereo lossless audio within the PCM budget."); return nil;
    }
    AudioStreamBasicDescription target = {rate, kAudioFormatLinearPCM,
        kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, 4, 1, 4, 2, 32, 0};
    status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(target), &target);
    SGPreparedPCM *result = [SGPreparedPCM new];
    result->_sampleRate = rate;
    result->_capacity = MIN(limit, (uint64_t)expected + 4096);
    result->_storage = status ? NULL : calloc((size_t)result->_capacity * 2, sizeof(float));
    if (!status && !result->_storage) status = kAudio_MemFullError;
    while (!status && !cancellation.cancelled) {
        uint64_t at = result->_frameCount;
        UInt32 frames = (UInt32)MIN(4096, result->_capacity - at);
        if (!frames) {
            // A file that exactly fills its budget still needs an EOF check, without allocating more.
            float left, right;
            struct { AudioBufferList list; AudioBuffer second; } tail = {{2, {{1,4,&left}}}, {1,4,&right}};
            UInt32 extra = 1;
            status = ExtAudioFileRead(file, &extra, &tail.list);
            if (!status && extra) status = kAudio_ParamError;
            break;
        }
        struct { AudioBufferList list; AudioBuffer second; } buffers = {
            {2, {{1, frames*4, result->_storage+at}}}, {1, frames*4, result->_storage+result->_capacity+at}};
        status = ExtAudioFileRead(file, &frames, &buffers.list);
        if (status || !frames) break;
        for (UInt32 i = 0; i < frames; ++i) {
            if (!isfinite(result->_storage[at+i]) || !isfinite(result->_storage[result->_capacity+at+i])) {
                status = kAudio_ParamError; break;
            }
        }
        result->_frameCount += frames;
    }
    ExtAudioFileDispose(file);
    if (cancellation.cancelled) { fail(error, 1, @"Preparation cancelled."); return nil; }
    if (status || fabs((double)result->_frameCount - expected) > 1) {
        fail(error, status ?: 4, @"The file did not decode completely within its declared length and budget."); return nil;
    }
    return result;
}
- (const float *)left { return _storage; }
- (const float *)right { return _storage + _capacity; }
- (void)dealloc { free(_storage); }
@end
