#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Worker-owned native decode of a complete local lossless file. Not a progressive downloader.
@interface SGPCMDecodeCancellation : NSObject
- (void)cancel;
@property(nonatomic, readonly, getter=isCancelled) BOOL cancelled;
@end

@interface SGPreparedPCM : NSObject
@property(nonatomic, readonly) double sampleRate;
@property(nonatomic, readonly) uint64_t frameCount;
@property(nonatomic, readonly) const float *left;
@property(nonatomic, readonly) const float *right;
// Call off the render/main threads. Only stereo FLAC/ALAC, decoded to planar Float32. maxBytes is
// a PCM allocation budget (at most 32 MiB); encoded files are limited to 64 MiB. Cancellation is
// checked between native reads. The caller retains this object while its pointers are used.
+ (nullable instancetype)prepareURL:(NSURL *)url sampleRate:(double)rate maxBytes:(NSUInteger)maxBytes
                      cancellation:(SGPCMDecodeCancellation *)cancellation error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
