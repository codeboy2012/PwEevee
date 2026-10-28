// Remote videos kept as local files in Caches/spoti.pw/Motion, named by a hash of their address, and the
// videos the mod makes, named by a hash of their key. A video asked for again while it downloads joins the
// download in flight. The folder keeps the newest kFiles.
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"

static const NSUInteger kFiles = 40;

static NSURL *folder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *url = [caches URLByAppendingPathComponent:@"spoti.pw/Motion" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

static NSURL *localFor(NSString *key) {
    NSData *address = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(address.bytes, (CC_LONG)address.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [name appendFormat:@"%02x", digest[i]];
    return [folder() URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"mp4"]];
}

static void trim(void) {
    NSArray<NSURLResourceKey> *keys = @[NSURLContentModificationDateKey];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder() includingPropertiesForKeys:keys
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    if (files.count <= kFiles) return;
    NSArray<NSURL *> *oldestFirst = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *left = nil, *right = nil;
        [a getResourceValue:&left forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&right forKey:NSURLContentModificationDateKey error:nil];
        return [left compare:right];
    }];
    for (NSUInteger i = 0; i + kFiles < oldestFirst.count; i++) [NSFileManager.defaultManager removeItemAtURL:oldestFirst[i] error:nil];
}

CGFloat SGMotionPixels(void) {
    return round(UIScreen.mainScreen.nativeBounds.size.width * 0.75);
}

NSURL *SGMotionMadeFile(NSString *key) {
    trim();
    return localFor([@"made\n" stringByAppendingString:key]);
}

static NSMutableDictionary<NSURL *, NSMutableArray *> *sg_waiting;

// A download that failed on the way (the lock screen and the player can share one, and iOS can cancel it with
// the lock screen's request) or met a busy server is tried `retries` more times before its waiters hear nil;
// an answer that says the file is not there is final.
static void download(NSURL *remote, NSURL *local, NSUInteger retries) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:remote];
    request.allowsConstrainedNetworkAccess = SGFlag(SGKeyMotionLowData, NO);
    [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *temporary, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        // The temporary file is gone once this handler returns, so it moves before the hop to main.
        BOOL kept = temporary && status == 200 && [NSFileManager.defaultManager moveItemAtURL:temporary toURL:local error:nil];
        BOOL again = !kept && retries > 0 && (error || status == 0 || status == 408 || status == 429 || status >= 500);
        if (kept) {
            trim();
            NSNumber *bytes = nil;
            [local getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
            SGLog(@"motion: %@ kept, %.1f MB", local.lastPathComponent, bytes.doubleValue / 1e6);
        }
        else SGLog(@"motion: %@ not downloaded (%ld, %@)%@", remote.lastPathComponent, (long)status, error.localizedDescription,
                   again ? @", tried again" : @"");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (again) {
                download(remote, local, retries - 1);
                return;
            }
            NSArray *waiting = sg_waiting[remote];
            [sg_waiting removeObjectForKey:remote];
            for (void (^waiter)(NSURL *) in waiting) waiter(kept ? local : nil);
        });
    }] resume];
}

void SGMotionFile(NSURL *remote, void (^done)(NSURL *file)) {
    if (!remote) {
        done(nil);
        return;
    }
    NSURL *local = localFor(remote.absoluteString);
    if ([NSFileManager.defaultManager fileExistsAtPath:local.path]) {
        done(local);
        return;
    }
    if (!sg_waiting) sg_waiting = [NSMutableDictionary dictionary];
    if (sg_waiting[remote]) {
        [sg_waiting[remote] addObject:[done copy]];
        return;
    }
    sg_waiting[remote] = [NSMutableArray arrayWithObject:[done copy]];
    download(remote, local, 1);
}

void SGMotionPoster(NSURL *file, void (^done)(UIImage *poster)) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:[AVURLAsset assetWithURL:file]];
    generator.appliesPreferredTrackTransform = YES;
    [generator generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
        UIImage *poster = image ? [UIImage imageWithCGImage:image] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(poster); });
    }];
}
