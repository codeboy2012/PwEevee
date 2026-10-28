// SGLyricsClip.h says what this draws. The words are laid out once per clip and only the backdrop moves,
// so an animated clip costs a scaled image draw and an encode a frame.
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <CoreText/CoreText.h>
#import "SGLyricsClip.h"

// The lock screen fills the screen with a 3:4 clip, so a phone's taller screen cuts its sides off: the
// words keep to this middle share of the width. The center of the words sits this far down, clear of
// the clock above and the controls below.
// ponytail: guessed from the screen's shape, not measured on a lock screen; tune both on a device.
static const CGFloat kColumn = 0.56;
static const CGFloat kCentreY = 0.5;
// The words' size as a share of the width, made smaller down to kSmallest of it while they run taller
// than kTallest of the height.
static const CGFloat kFont = 0.05;
static const CGFloat kSmallest = 0.6;
static const CGFloat kTallest = 0.4;
static const CGFloat kNextAlpha = 0.4;
// A still is one frame held this long; an animated clip breathes once over kLoopSeconds, which is all it
// plays before the lock screen loops it.
static const int32_t kStillSeconds = 2;
static const int32_t kLoopSeconds = 4;
static const int32_t kFPS = 15;   // the breath is slow; at 24 a line took about 4 s to write on the CPU
static const CGFloat kBreath = 0.06;   // how much bigger the cover grows at the top of a breath
static const CGFloat kMotionDim = 0.25, kBandDim = 0.6, kBandReach = 0.3, kSoftWidth = 0.06;
static const CGFloat kShadowAlpha = 0.9, kShadowBlur = 0.15, kMotionNextAlpha = 0.55;
static const double kMotionFPS = 30;

CGSize SGLyricsClipSize(CGFloat pixels) {
    CGFloat width = MAX(floor(pixels / 16) * 16, 16);
    return CGSizeMake(width, round(width * 4 / 3 / 16) * 16);
}

static CGContextRef newContext(CGSize size, void *data, size_t bytesPerRow) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(data, (size_t)size.width, (size_t)size.height, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    return context;
}

// The width the cover is blurred at, before it is drawn at the clip's size.
static const CGFloat kBackdropWidth = 128;

CGImageRef SGLyricsClipBackdrop(CGImageRef cover, CGSize size) {
    CGContextRef context = newContext(size, NULL, 0);
    CGRect bounds = {CGPointZero, size};
    CGContextSetRGBFillColor(context, 0.11, 0.11, 0.12, 1);
    CGContextFillRect(context, bounds);
    if (cover) {
        static CIContext *renderer;
        static dispatch_once_t once;
        // On the CPU: the lock screen asks while Spotify is in the background, where GPU work gets it killed.
        dispatch_once(&once, ^{ renderer = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @YES}]; });
        // Blurred small and drawn large: a blur this wide looks the same either way, and on the CPU at full size it
        // took 12 to 20 s for a song's first line.
        CGSize small = CGSizeMake(kBackdropWidth, round(kBackdropWidth * size.height / size.width));
        // Filled the way the lock screen fills the screen, the square cover's sides overflowing.
        CIImage *image = [CIImage imageWithCGImage:cover];
        CGFloat scale = MAX(small.width / image.extent.size.width, small.height / image.extent.size.height);
        image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
        image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation((small.width - image.extent.size.width) / 2,
                                                                                 (small.height - image.extent.size.height) / 2)];
        // Clamped first, so the blur does not pull the dark in from past the edges.
        image = [[image imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:small.width * 0.05];
        CGImageRef blurred = [renderer createCGImage:image fromRect:(CGRect){CGPointZero, small}];
        CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
        if (blurred) CGContextDrawImage(context, bounds, blurred);
        CGImageRelease(blurred);
        // Darkened, so white words read over a light cover.
        CGContextSetRGBFillColor(context, 0, 0, 0, 0.45);
        CGContextFillRect(context, bounds);
    }
    CGImageRef backdrop = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return backdrop;
}

static NSAttributedString *wordsAt(NSString *previous, NSString *line, NSString *next, CGFloat fontSize, CGFloat dimAlpha) {
    CTFontRef font = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, fontSize, NULL);
    CGFloat spacing = fontSize * 0.6;
    CTParagraphStyleSetting settings[] = {
        {kCTParagraphStyleSpecifierParagraphSpacingBefore, sizeof(spacing), &spacing},
    };
    CTParagraphStyleRef paragraph = CTParagraphStyleCreate(settings, 1);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGFloat white[] = {1, 1, 1, 1}, dim[] = {1, 1, 1, dimAlpha};
    CGColorRef lit = CGColorCreate(space, white), unlit = CGColorCreate(space, dim);
    NSMutableAttributedString *words = [NSMutableAttributedString new];
    NSDictionary *base = @{(id)kCTFontAttributeName: (__bridge id)font, (id)kCTParagraphStyleAttributeName: (__bridge id)paragraph};
    NSString *texts[] = {previous, line, next};
    for (int i = 0; i < 3; i++) {
        if (!texts[i].length) continue;
        NSMutableDictionary *attributes = [base mutableCopy];
        attributes[(id)kCTForegroundColorAttributeName] = (__bridge id)(i == 1 ? lit : unlit);
        NSString *text = words.length ? [@"\n" stringByAppendingString:texts[i]] : texts[i];
        [words appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    }
    CFRelease(font);
    CFRelease(paragraph);
    CGColorRelease(lit);
    CGColorRelease(unlit);
    CGColorSpaceRelease(space);
    return words;
}

// The words alone on a clear image. Over moving artwork, only their box is returned and `drawn` gets its place.
static CGImageRef newWords(NSString *previous, NSString *line, NSString *next, CGSize size, CGRect *drawn) CF_RETURNS_RETAINED {
    if (!previous.length && !line.length && !next.length) return NULL;
    CGFloat width = round(size.width * kColumn);
    CGFloat fontSize = size.width * kFont;
    CTFramesetterRef setter = NULL;
    CGSize fits = CGSizeZero;
    // A long line is set smaller until the two lines fit; past the smallest size it runs taller.
    for (CGFloat scale = 1; scale >= kSmallest - 0.01; scale -= 0.1) {
        if (setter) CFRelease(setter);
        setter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)
            wordsAt(previous, line, next, fontSize * scale, drawn ? kMotionNextAlpha : kNextAlpha));
        fits = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
        if (fits.height <= size.height * kTallest) break;
    }
    CGFloat height = ceil(fits.height) + 1;
    // Core Graphics counts up from the bottom.
    CGRect box = CGRectMake(round((size.width - width) / 2), round(size.height * (1 - kCentreY) - height / 2), width, height);
    CGPathRef path = CGPathCreateWithRect(box, NULL);
    CTFrameRef frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    CGContextRef context = newContext(size, NULL, 0);
    if (drawn) {
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGFloat shade[] = {0, 0, 0, kShadowAlpha};
        CGColorRef color = CGColorCreate(space, shade);
        CGContextSetShadowWithColor(context, CGSizeZero, fontSize * kShadowBlur, color);
        CGColorRelease(color);
        CGColorSpaceRelease(space);
    }
    CTFrameDraw(frame, context);
    CGImageRef words = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (drawn) {
        *drawn = CGRectIntersection(CGRectIntegral(CGRectInset(box, -fontSize, -fontSize)), (CGRect){CGPointZero, size});
        CGImageRef cut = CGImageCreateWithImageInRect(words, CGRectMake(drawn->origin.x, size.height - CGRectGetMaxY(*drawn),
                                                                        drawn->size.width, drawn->size.height));
        CGImageRelease(words);
        words = cut;
    }
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(setter);
    return words;
}

// A frame `phase` of the way through the loop, 0 to 1, into `context`.
static void drawFrame(CGContextRef context, CGImageRef backdrop, CGImageRef words, CGSize size, double phase) {
    CGFloat grow = kBreath * (1 - cos(2 * M_PI * phase)) / 2;
    CGRect bounds = {CGPointZero, size};
    CGContextDrawImage(context, CGRectInset(bounds, -size.width * grow / 2, -size.height * grow / 2), backdrop);
    if (words) CGContextDrawImage(context, bounds, words);
}

CGImageRef SGLyricsClipFrame(CGImageRef backdrop, NSString *line, NSString *next, CGSize size) {
    CGImageRef words = newWords(nil, line, next, size, NULL);
    CGContextRef context = newContext(size, NULL, 0);
    drawFrame(context, backdrop, words, size, 0);
    CGImageRef frame = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(words);
    return frame;
}

BOOL SGLyricsClipWrite(NSURL *file, CGImageRef backdrop, NSString *line, NSString *next, CGSize size, SGLyricsClipStyle style) {
    // Written beside the file and moved over it once whole, so a clip cut off halfway is never found.
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    if (!writer) return NO;
    int32_t frames = style == SGLyricsClipAnimated ? kLoopSeconds * kFPS : 1;
    CMTime length = CMTimeMake(style == SGLyricsClipAnimated ? kLoopSeconds : kStillSeconds, 1);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(size.width),
        AVVideoHeightKey: @(size.height),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(2000000), AVVideoMaxKeyFrameIntervalKey: @(kFPS)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
        sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(size.width),
            (id)kCVPixelBufferHeightKey: @(size.height),
        }];
    if (![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    CGImageRef words = newWords(nil, line, next, size, NULL);
    BOOL ok = YES;
    for (int32_t i = 0; i < frames && ok; i++) {
        while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting) [NSThread sleepForTimeInterval:0.002];
        CVPixelBufferRef buffer = NULL;
        ok = writer.status == AVAssetWriterStatusWriting && adaptor.pixelBufferPool
            && CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer) == kCVReturnSuccess;
        if (!ok) break;
        CVPixelBufferLockBaseAddress(buffer, 0);
        CGContextRef context = newContext(size, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        drawFrame(context, backdrop, words, size, (double)i / frames);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        ok = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, kFPS)];
        CVPixelBufferRelease(buffer);
    }
    CGImageRelease(words);
    if (!ok) {
        [writer cancelWriting];
        return NO;
    }
    [input markAsFinished];
    // The last frame, or a still's only one, is held to the end of the loop.
    [writer endSessionAtSourceTime:length];
    dispatch_semaphore_t written = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(written); }];
    dispatch_semaphore_wait(written, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) return NO;
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}

typedef struct {
    CGSize stored, cut;
    double length;
} Motion;

static AVAssetTrack *motionTrack(AVURLAsset *asset, Motion *motion) {
    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(loaded);
    }];
    dispatch_semaphore_wait(loaded, DISPATCH_TIME_FOREVER);
    if (!track || !CGAffineTransformIsIdentity(track.preferredTransform)) return nil;
    CGSize stored = CGSizeMake(round(track.naturalSize.width), round(track.naturalSize.height));
    double length = CMTimeGetSeconds(track.timeRange.duration);
    if (stored.width < 16 || stored.height < 16 || !(length > 0)) return nil;
    CGSize cut = stored.width / stored.height > 0.75 ? CGSizeMake(stored.height * 0.75, stored.height)
                                                     : CGSizeMake(stored.width, stored.width / 0.75);
    *motion = (Motion){stored, CGSizeMake(floor(cut.width / 2) * 2, floor(cut.height / 2) * 2), length};
    return track;
}

static CGRect cutIn(Motion motion) {
    return CGRectMake(round((motion.stored.width - motion.cut.width) / 2), round((motion.stored.height - motion.cut.height) / 2),
                      motion.cut.width, motion.cut.height);
}

typedef struct {
    CGImageRef words;
    CGRect drawn;
    uint16_t *keep;
    CGRect soft;
    uint8_t *blurred;
    uint16_t *feather;
} Over;

static CGFloat dimAt(size_t y, size_t height) {
    CGFloat reach = height * kBandReach, t = (y - (height * kCentreY - reach)) / (2 * reach);
    if (t <= 0 || t >= 1) return kMotionDim;
    CGFloat edge = MIN(MIN(t, 1 - t) / 0.3, 1);
    return kMotionDim + (kBandDim - kMotionDim) * edge;
}

static Over makeOver(Motion motion, NSString *previous, NSString *line, NSString *next) {
    Over over = {0};
    over.words = newWords(previous, line, next, motion.cut, &over.drawn);
    size_t rows = (size_t)motion.cut.height;
    over.keep = malloc(rows * sizeof(uint16_t));
    for (size_t y = 0; y < rows; y++) over.keep[y] = (uint16_t)round(256 * (1 - dimAt(y, rows)));
    if (!over.words) return over;
    CGRect cut = cutIn(motion);
    over.soft = CGRectMake(cut.origin.x, cut.origin.y + over.drawn.origin.y, cut.size.width, over.drawn.size.height);
    size_t width = (size_t)over.soft.size.width, height = (size_t)over.soft.size.height;
    size_t fade = MAX(MIN((size_t)(motion.cut.width * kFont), height / 2), 1);
    over.blurred = malloc(width * height * 4);
    over.feather = malloc(height * sizeof(uint16_t));
    for (size_t y = 0; y < height; y++) over.feather[y] = (uint16_t)(256 * MIN(1.0, MIN(y, height - 1 - y) / (double)fade));
    return over;
}

static void freeOver(Over over) {
    CGImageRelease(over.words);
    free(over.keep);
    free(over.blurred);
    free(over.feather);
}

static BOOL drawOver(CVPixelBufferRef buffer, Motion motion, Over over) {
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    CGRect cut = cutIn(motion);
    size_t frameWidth = CVPixelBufferGetWidth(buffer), frameHeight = CVPixelBufferGetHeight(buffer);
    CGRect frame = CGRectMake(0, 0, frameWidth, frameHeight);
    if (!base || CVPixelBufferIsPlanar(buffer) || CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA
        || frameWidth != (size_t)motion.stored.width || frameHeight != (size_t)motion.stored.height || bytesPerRow < frameWidth * 4
        || !CGRectContainsRect(frame, cut) || (over.blurred && !CGRectContainsRect(frame, over.soft))) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        return NO;
    }
    if (over.blurred) {
        size_t top = (size_t)(motion.stored.height - CGRectGetMaxY(over.soft)), height = (size_t)over.soft.size.height;
        size_t width = (size_t)over.soft.size.width, rowBytes = width * 4;
        uint8_t *rows = base + top * bytesPerRow + (size_t)over.soft.origin.x * 4;
        vImage_Buffer from = {rows, height, width, bytesPerRow}, to = {over.blurred, height, width, rowBytes};
        uint32_t kernel = (uint32_t)(width * kSoftWidth) | 1;
        if (vImageTentConvolve_ARGB8888(&from, &to, NULL, 0, 0, kernel, kernel, NULL, kvImageEdgeExtend) == kvImageNoError) {
            for (size_t y = 0; y < height; y++) {
                uint8_t *sharp = rows + y * bytesPerRow;
                const uint8_t *soft = over.blurred + y * rowBytes;
                uint16_t share = over.feather[y];
                if (share == 256) memcpy(sharp, soft, rowBytes);
                else if (share) for (size_t i = 0; i < rowBytes; i++) sharp[i] += (uint8_t)(((soft[i] - sharp[i]) * share) >> 8);
            }
        }
    }
    size_t top = (size_t)cut.origin.y, width = (size_t)cut.size.width;
    for (size_t y = 0; y < (size_t)cut.size.height; y++) {
        uint32_t *pixel = (uint32_t *)(base + (top + y) * bytesPerRow) + (size_t)cut.origin.x, keep = over.keep[y];
        for (size_t x = 0; x < width; x++) {
            uint32_t v = pixel[x];
            pixel[x] = (((v & 0x00FF00FFu) * keep >> 8) & 0x00FF00FFu)
                     | (((v & 0x0000FF00u) * keep >> 8) & 0x0000FF00u) | (v & 0xFF000000u);
        }
    }
    if (over.words) {
        CGContextRef context = newContext(motion.stored, base, bytesPerRow);
        CGContextDrawImage(context, CGRectOffset(over.drawn, cut.origin.x, cut.origin.y), over.words);
        CGContextRelease(context);
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return YES;
}

static BOOL eachFrame(AVURLAsset *asset, AVAssetTrack *track, Motion motion, double from, double seconds,
                      BOOL (^each)(CMSampleBufferRef sample)) {
    int32_t scale = 600;
    double at = fmod(MAX(from, 0), motion.length), done = 0, due = 0;
    while (seconds - done > 0.01) {
        double take = MIN(motion.length - at, seconds - done);
        AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        }];
        output.alwaysCopiesSampleData = YES;
        if (!reader || ![reader canAddOutput:output]) return NO;
        [reader addOutput:output];
        reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(at, scale), CMTimeMakeWithSeconds(take, scale));
        if (![reader startReading]) return NO;
        CMSampleBufferRef sample;
        while ((sample = [output copyNextSampleBuffer])) {
            CMTime time = CMTimeMakeWithSeconds(done + MAX(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) - at, 0), scale);
            CMSampleBufferRef timed = NULL;
            CMSampleTimingInfo timing = {kCMTimeInvalid, time, kCMTimeInvalid};
            BOOL keep = CMTimeGetSeconds(time) >= due - 0.002 && CMTimeGetSeconds(time) < done + take
                && CMSampleBufferGetImageBuffer(sample)
                && CMSampleBufferCreateCopyWithNewTiming(NULL, sample, 1, &timing, &timed) == noErr;
            CFRelease(sample);
            if (!keep) continue;
            due = due + 1.0 / kMotionFPS < CMTimeGetSeconds(time)
                ? CMTimeGetSeconds(time) + 0.5 / kMotionFPS : due + 1.0 / kMotionFPS;
            BOOL more = each(timed);
            CFRelease(timed);
            if (!more) {
                [reader cancelReading];
                return YES;
            }
        }
        if (reader.status != AVAssetReaderStatusCompleted) return NO;
        done += take;
        at = 0;
    }
    return YES;
}

CGImageRef SGLyricsClipMotionFrame(NSURL *motionFile, NSString *previous, NSString *line, NSString *next, double from) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionFile options:nil];
    Motion motion;
    AVAssetTrack *track = motionTrack(asset, &motion);
    if (!track) return NULL;
    Over over = makeOver(motion, previous, line, next);
    __block CGImageRef frame = NULL;
    eachFrame(asset, track, motion, from, motion.length, ^BOOL(CMSampleBufferRef sample) {
        CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
        if (!drawOver(buffer, motion, over)) return NO;
        CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        CGContextRef context = newContext(motion.stored, CVPixelBufferGetBaseAddress(buffer), CVPixelBufferGetBytesPerRow(buffer));
        CGImageRef whole = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
        frame = CGImageCreateWithImageInRect(whole, cutIn(motion));
        CGImageRelease(whole);
        return NO;
    });
    freeOver(over);
    return frame;
}

BOOL SGLyricsClipWriteOverMotion(NSURL *file, NSURL *motionFile, NSString *previous, NSString *line, NSString *next,
                                 double from, double seconds) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:motionFile options:nil];
    Motion motion;
    AVAssetTrack *track = motionTrack(asset, &motion);
    if (!track) return NO;
    seconds = MIN(seconds, motion.length);
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(motion.cut.width),
        AVVideoHeightKey: @(motion.cut.height),
        AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(motion.cut.width * motion.cut.height * 3)},
    }];
    if (!writer || ![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];
    Over over = makeOver(motion, previous, line, next);
    __block BOOL ok = YES, any = NO;
    BOOL read = eachFrame(asset, track, motion, from, seconds, ^BOOL(CMSampleBufferRef sample) {
        if (!drawOver(CMSampleBufferGetImageBuffer(sample), motion, over)) {
            ok = NO;
            return NO;
        }
        while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting) [NSThread sleepForTimeInterval:0.002];
        ok = writer.status == AVAssetWriterStatusWriting && [input appendSampleBuffer:sample];
        any = YES;
        return ok;
    });
    freeOver(over);
    if (!read || !ok || !any) {
        [writer cancelWriting];
        return NO;
    }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMakeWithSeconds(seconds, 600)];
    dispatch_semaphore_t written = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(written); }];
    dispatch_semaphore_wait(written, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) return NO;
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}

NSString *SGLyricsClipLook(NSURL *motion, SGLyricsClipStyle style) {
    if (!motion) return [NSString stringWithFormat:@"%ld", (long)style];
    NSString *name = motion.lastPathComponent.stringByDeletingPathExtension;
    return [NSString stringWithFormat:@"m%@s%ld", name.length > 16 ? [name substringToIndex:16] : name, (long)style];
}
