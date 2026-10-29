#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <stdint.h>
#import "SGFillClip.h"

// The cover is drawn aspect-fill across the whole frame — the zoom the system's own full-screen
// artwork uses, cropping the sides — and dissolves into a blur of the same cover drawn with the same
// fill, so both layers stay one picture at one zoom and the fade only reads as the blur
// strengthening in from the frame's edges, with no square stopping short of the frame.
static const CGFloat kBackdropBlurRadius = 34.0, kEdgeFade = 0.2;
static const int32_t kLoopSeconds = 4, kFramesPerSecond = 24;

static CGColorSpaceRef fillColorSpace(void) {
    static CGColorSpaceRef colorSpace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    });
    return colorSpace;
}

static CIContext *fillCIContext(void) {
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        context = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @YES,
            kCIContextCacheIntermediates: @NO,
        }];
    });
    return context;
}

static CGContextRef bitmapContext(CGSize size) {
    size_t width = (size_t)round(size.width), height = (size_t)round(size.height);
    if (!width || !height) return NULL;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, fillColorSpace(),
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (context) CGContextClearRect(context, CGRectMake(0, 0, width, height));
    return context;
}

static UIColor *fillBackgroundColor(CGImageRef cover) {
    size_t width = CGImageGetWidth(cover), height = CGImageGetHeight(cover);
    if (width < 8 || height < 8) return UIColor.blackColor;
    CGRect sampleRect = CGRectMake(floor(width * 0.13), floor(height * 0.92),
                                   floor(width * 0.74), height - floor(height * 0.92));
    CGImageRef sample = CGImageCreateWithImageInRect(cover, sampleRect);
    if (!sample) return UIColor.blackColor;

    enum { kSampleSide = 8 };
    uint8_t pixels[kSampleSide * kSampleSide * 4] = {0};
    CGContextRef context = CGBitmapContextCreate(pixels, kSampleSide, kSampleSide, 8, kSampleSide * 4,
        fillColorSpace(), kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    if (!context) {
        CGImageRelease(sample);
        return UIColor.blackColor;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, kSampleSide, kSampleSide), sample);
    CGContextRelease(context);
    CGImageRelease(sample);

    double red = 0, green = 0, blue = 0;
    for (NSUInteger index = 0; index < kSampleSide * kSampleSide; index++) {
        red += pixels[index * 4];
        green += pixels[index * 4 + 1];
        blue += pixels[index * 4 + 2];
    }
    CGFloat r = red / (kSampleSide * kSampleSide * 255.0);
    CGFloat g = green / (kSampleSide * kSampleSide * 255.0);
    CGFloat b = blue / (kSampleSide * kSampleSide * 255.0);
    UIColor *average = [UIColor colorWithRed:r green:g blue:b alpha:1];
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
    if (![average getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) return UIColor.blackColor;
    brightness = MIN(0.42, MAX(0.03, 0.9 * pow(brightness, 1.6)));
    saturation = MIN(saturation * 1.05, 1.0);
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];
}

// The blur is taken straight from the raw cover and left at its own size, so the backdrop can be
// drawn over the frame with exactly the fill the sharp layer uses and the two stay one picture.
// CoreImage hands back a picture that already sits upright, so it is drawn plainly, the way
// Redesigned/Kit's SGRFluid.m draws its blur.
static CGImageRef blurredCoverForFrame(CGImageRef cover, CGFloat radius) CF_RETURNS_RETAINED {
    CIImage *input = [CIImage imageWithCGImage:cover];
    CIImage *output = [[input imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:radius];
    return [fillCIContext() createCGImage:output fromRect:input.extent];
}

static void drawFilling(CGContextRef context, CGImageRef image, CGRect rect) {
    CGFloat imageWidth = CGImageGetWidth(image), imageHeight = CGImageGetHeight(image);
    if (imageWidth <= 0 || imageHeight <= 0) return;
    CGFloat scale = MAX(rect.size.width / imageWidth, rect.size.height / imageHeight);
    CGSize drawn = CGSizeMake(imageWidth * scale, imageHeight * scale);
    CGRect destination = CGRectMake(rect.origin.x + (rect.size.width - drawn.width) / 2,
                                    rect.origin.y + (rect.size.height - drawn.height) / 2,
                                    drawn.width, drawn.height);
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, destination, image);
}

static void addRampStop(CGFloat *components, CGFloat *locations, NSUInteger *count, CGFloat location, CGFloat alpha) {
    locations[*count] = location;
    components[*count * 4] = 1;
    components[*count * 4 + 1] = 1;
    components[*count * 4 + 2] = 1;
    components[*count * 4 + 3] = alpha;
    (*count)++;
}

static CGGradientRef alphaRamp(CGFloat start, CGFloat end, BOOL rising) {
    enum { kSteps = 14 };
    CGFloat components[(kSteps + 3) * 4], locations[kSteps + 3];
    NSUInteger count = 0;
    addRampStop(components, locations, &count, 0, rising ? 0 : 1);
    for (NSUInteger index = 0; index <= kSteps; index++) {
        CGFloat progress = (CGFloat)index / kSteps;
        CGFloat smooth = progress * progress * (3 - 2 * progress);
        addRampStop(components, locations, &count, start + (end - start) * progress, rising ? smooth : 1 - smooth);
    }
    addRampStop(components, locations, &count, 1, rising ? 1 : 0);
    return CGGradientCreateWithColorComponents(fillColorSpace(), components, locations, count);
}

static void applyRamp(CGContextRef context, CGFloat originY, CGFloat height, CGFloat start, CGFloat end, BOOL rising) {
    CGGradientRef gradient = alphaRamp(start, end, rising);
    if (!gradient) return;
    CGContextSaveGState(context);
    CGContextSetBlendMode(context, kCGBlendModeDestinationIn);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, originY + start * height), CGPointMake(0, originY + end * height),
                                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
}

static CGImageRef maskedLayer(CGImageRef cover, CGSize size) CF_RETURNS_RETAINED {
    CGContextRef context = bitmapContext(size);
    if (!context) return NULL;
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
    drawFilling(context, cover, CGRectMake(0, 0, size.width, size.height));
    applyRamp(context, 0, size.height, 0, kEdgeFade, YES);
    applyRamp(context, 0, size.height, 1 - kEdgeFade, 1, NO);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

CGImageRef SGFillClipFrame(CGImageRef cover, CGSize size) {
    if (!cover || size.width < 1 || size.height < 1) return NULL;
    // The blur is made in the cover's own pixels; its sigma is scaled so the blur the clip shows stays
    // the same strength whatever the cover's size is against the frame.
    CGFloat fillScale = MAX(size.width / (CGFloat)CGImageGetWidth(cover), size.height / (CGFloat)CGImageGetHeight(cover));
    if (!(fillScale > 0)) fillScale = 1.0;

    CGImageRef backdrop = blurredCoverForFrame(cover, kBackdropBlurRadius / fillScale);
    CGImageRef foreground = maskedLayer(cover, size);
    if (!backdrop || !foreground) {
        if (backdrop) CGImageRelease(backdrop);
        if (foreground) CGImageRelease(foreground);
        return NULL;
    }

    CGContextRef context = bitmapContext(size);
    if (!context) {
        CGImageRelease(backdrop);
        CGImageRelease(foreground);
        return NULL;
    }
    CGContextSetFillColorWithColor(context, fillBackgroundColor(cover).CGColor);
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
    // CoreImage's output already sits the right way up, so the blur is drawn plainly, the way
    // Redesigned/Kit's SGRFluid.m draws its blur; only the cover's sharp layer above goes through the
    // cover's own recipe, which is what has always stood it upright on the phone.
    drawFilling(context, backdrop, CGRectMake(0, 0, size.width, size.height));
    CGImageRelease(backdrop);
    CGContextTranslateCTM(context, 0, size.height);
    CGContextScaleCTM(context, 1, -1);
    drawFilling(context, foreground, CGRectMake(0, 0, size.width, size.height));
    CGImageRelease(foreground);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

BOOL SGFillClipWriteFrame(NSURL *file, CGImageRef frame, CGSize size) {
    if (!file || !frame || size.width < 1 || size.height < 1) return NO;
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    if (!writer) {
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    int32_t width = (int32_t)round(size.width), height = (int32_t)round(size.height);
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(width),
        AVVideoHeightKey: @(height),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(2000000),
                                           AVVideoMaxKeyFrameIntervalKey: @(kFramesPerSecond)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
        }];
    if (![writer canAddInput:input]) {
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];

    BOOL ok = YES;
    int32_t frameCount = kLoopSeconds * kFramesPerSecond;
    for (int32_t index = 0; index < frameCount && ok; index++) {
        while (!input.readyForMoreMediaData && writer.status == AVAssetWriterStatusWriting) {
            [NSThread sleepForTimeInterval:0.002];
        }
        CVPixelBufferRef buffer = NULL;
        ok = writer.status == AVAssetWriterStatusWriting && adaptor.pixelBufferPool
            && CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer) == kCVReturnSuccess;
        if (!ok) break;
        CVPixelBufferLockBaseAddress(buffer, 0);
        CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), (size_t)width, (size_t)height,
            8, CVPixelBufferGetBytesPerRow(buffer), fillColorSpace(),
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        ok = context != NULL;
        if (context) {
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), frame);
            CGContextRelease(context);
        }
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        if (ok) ok = [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(index, kFramesPerSecond)];
        CVPixelBufferRelease(buffer);
    }
    if (!ok) {
        [writer cancelWriting];
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMake(kLoopSeconds, 1)];
    dispatch_semaphore_t written = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(written); }];
    dispatch_semaphore_wait(written, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) {
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}
