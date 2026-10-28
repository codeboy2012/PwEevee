// The lock screen can show the track's Canvas or Apple Music's animated album cover, or Every song's cover
// over a moving blur of itself (SGFluidClip.h). iOS 26 takes a
// local video through MPMediaItemAnimatedArtwork under one of two now playing keys, 1:1 or 3:4, of those
// the system lists. It rides on Spotify's now playing info as an extra (Shared/Player/NowPlayingExtras.h).
//
// The system turns down a clip of another shape than its key's, and a preview still of another shape with
// it, so a clip that does not fit (a Canvas is mostly 9:16) is cut to the key's shape about its middle, and
// the still is filled to the size the system asks for. The cut, like the cover's clip, is made only when the
// lock screen asks for the video, and kept: the cut by the clip and shape, the cover's clip by the picture
// the track names, so an album's songs share one.
//
// The configured choice is read on every track. When Canvas is unavailable, the next enabled style is used
// for that track only; the configured choice is retried on the next track.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"
#import "SGFluidClip.h"
#import "SGFillClip.h"
#import "SGMotionClip.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LockScreenLyrics/SGLyricsClip.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"

// How far a clip's width over height may be from its key's and still be taken as it is.
static const CGFloat kSameShape = 0.02;

static NSString *sg_title;
static NSString *sg_picture;   // the picture the track names, for the cover's clip
static NSUInteger sg_walk;   // counts the tracks walked, so a poster that comes late is told from the newest
static SGLockArtwork sg_choice;
static dispatch_queue_t sg_queue;   // cuts clips and makes the cover's, one at a time
static SGMotionFollower *sg_follower;
static NSURL *sg_lyricsFile;
static BOOL sg_plain, sg_plainShown;
static SGLockArtwork sg_configuredChoice;

static BOOL motionOn(SGLockArtwork choice) {
    return choice == SGLockArtworkMotion;
}

API_AVAILABLE(ios(26.0))
static void showCover(NSString *picture);
API_AVAILABLE(ios(26.0))
static void showFill(NSString *picture);

API_AVAILABLE(ios(26.0))
static void advanceAfterMissingMotion(void) {
    sg_choice = SGLockScreenSkipUnavailableMotion();
    if (sg_choice == SGLockArtworkFill) showFill(sg_picture);
    else if (sg_choice == SGLockArtworkEverySong) showCover(sg_picture);
    else SGNowPlayingSetExtras(@"motion", nil, nil);
}

// The key a clip shown at `shown` goes under, and the shape it is cut to (width over height): 1:1 for a
// square clip, else 3:4, each where the system lists it, else the other. nil while it lists neither, before
// MediaPlayer has started: the next track asks again.
API_AVAILABLE(ios(26.0))
static NSString *keyFor(CGSize shown, CGFloat *ratio) {
    NSArray<NSString *> *keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys;
    BOOL square = shown.height > 0 && fabs(shown.width / shown.height - 1) <= kSameShape;
    BOOL tall = [keys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork];
    if ([keys containsObject:MPNowPlayingInfoProperty1x1AnimatedArtwork] && (square || !tall)) {
        *ratio = 1;
        return MPNowPlayingInfoProperty1x1AnimatedArtwork;
    }
    *ratio = 0.75;
    return tall ? MPNowPlayingInfoProperty3x4AnimatedArtwork : nil;
}

// `image` filled into `size` about its middle, at scale 1 and opaque, as the preview the system asked for.
static UIImage *filled(UIImage *image, CGSize size) {
    size = CGSizeMake(round(size.width), round(size.height));
    if (!image || size.width < 1 || size.height < 1 || image.size.width <= 0 || image.size.height <= 0) return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    CGFloat scale = MAX(size.width / image.size.width, size.height / image.size.height);
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
    }];
}

API_AVAILABLE(ios(26.0))
static void show(NSURL *file) {
    NSUInteger walk = sg_walk;
    NSString *title = sg_title;
    SGMotionPoster(file, ^(UIImage *poster) {
        if (walk != sg_walk) return;
        if (!poster || poster.size.width <= 0 || poster.size.height <= 0) {
            advanceAfterMissingMotion();
            return;
        }
        CGFloat ratio;
        NSString *key = keyFor(poster.size, &ratio);
        if (!key) {
            SGLog(@"lock motion: the system lists no key yet (%@)", MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys);
            return;
        }
        BOOL fits = fabs(poster.size.width / poster.size.height - ratio) <= kSameShape;
        NSURL *shaped = fits ? file : SGMotionMadeFile([NSString stringWithFormat:@"cut\n%@\n%g", file.lastPathComponent, ratio]);
        MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:shaped.lastPathComponent
            previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) { completion(filled(poster, wanted)); }
            videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
                if (fits) {
                    completion(file);
                    return;
                }
                dispatch_async(sg_queue, ^{
                    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                    BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:shaped.path] || SGMotionClipShape(file, ratio, shaped);
                    SGLog(@"lock motion: %@ cut to %@ %@ in %.0f ms", file.lastPathComponent, ratio == 1 ? @"1:1" : @"3:4",
                          ok ? @"ready" : @"not written", (CFAbsoluteTimeGetCurrent() - start) * 1000);
                    completion(ok ? shaped : nil);
                    if (!ok) dispatch_async(dispatch_get_main_queue(), ^{
                        if (walk == sg_walk) advanceAfterMissingMotion();
                    });
                });
            }];
        SGNowPlayingSetExtras(@"motion", @{key: artwork}, title);
        SGLog(@"lock motion: %@, %.0fx%.0f, as %@%@", file.lastPathComponent, poster.size.width, poster.size.height,
              ratio == 1 ? @"1:1" : @"3:4", fits ? @"" : @", cut to fit");
    });
}

// The cover Spotify handed the system for `title`, read on the main thread as LyricsArtwork.x reads it,
// then `then` on sg_queue with it, or with NULL when the info is another song's or has none.
static void withCover(NSString *title, void (^then)(CGImageRef cover)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
        MPMediaItemArtwork *artwork = info[MPMediaItemPropertyArtwork];
        UIImage *cover = SGNowPlayingTitlesMatch(info[MPMediaItemPropertyTitle], title)
            && [artwork isKindOfClass:MPMediaItemArtwork.class]
            ? [artwork imageWithSize:CGSizeMake(600, 600)] : nil;
        dispatch_async(sg_queue, ^{ then(cover.CGImage); });
    });
}

// The picture the track names, so the songs of an album share a clip; the track itself when it names none.
static NSString *pictureOf(SPTPlayerTrack *track, NSDictionary *metadata) {
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
        id value = metadata[field];
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return SGURIString(track.URI);
}

// The cover's clip is 3:4 (SGLyricsClipSize), so it goes only where the system lists that key.
API_AVAILABLE(ios(26.0))
static void showCover(NSString *picture) {
    if (![MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork]) return;
    CGFloat coverScale = SGLockScreenCoverArtworkScale();
    NSString *clipID = [NSString stringWithFormat:@"fluid\n%@\ncover %.2f", picture, coverScale];
    NSURL *file = SGMotionMadeFile(clipID);
    NSString *title = sg_title;
    CGSize size = SGLyricsClipSize(SGMotionPixels());
    MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:file.lastPathComponent
        previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
            withCover(title, ^(CGImageRef cover) {
                CGImageRef frame = SGFluidClipFrame(cover, size, coverScale);
                completion(frame ? filled([UIImage imageWithCGImage:frame], wanted) : nil);
                CGImageRelease(frame);
            });
        }
        videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
            withCover(title, ^(CGImageRef cover) {
                CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:file.path]
                    || SGFluidClipWrite(file, cover, size, coverScale);
                SGLog(@"lock motion: the cover's clip %@ %@ in %.0f ms", file.lastPathComponent, ok ? @"ready" : @"not written",
                      (CFAbsoluteTimeGetCurrent() - start) * 1000);
                completion(ok ? file : nil);
            });
        }];
    SGNowPlayingSetExtras(@"motion", @{MPNowPlayingInfoProperty3x4AnimatedArtwork: artwork}, title);
    SGLog(@"lock motion: no moving artwork, the cover's clip offered as %@", file.lastPathComponent);
}

API_AVAILABLE(ios(26.0))
static void showFill(NSString *picture) {
    if (![MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys containsObject:MPNowPlayingInfoProperty3x4AnimatedArtwork]) return;
    NSString *title = sg_title;
    CGSize size = SGLyricsClipSize(SGMotionPixels());
    NSURL *file = SGMotionMadeFile([NSString stringWithFormat:@"fill\nv11\n%@\n%.0fx%.0f", picture, size.width, size.height]);
    __block UIImage *renderedFrame;
    MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:file.lastPathComponent
        previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) {
            withCover(title, ^(CGImageRef cover) {
                if (!renderedFrame) {
                    CGImageRef frame = SGFillClipFrame(cover, size);
                    if (frame) renderedFrame = [UIImage imageWithCGImage:frame];
                    if (frame) CGImageRelease(frame);
                }
                completion(renderedFrame ? filled(renderedFrame, wanted) : nil);
            });
        }
        videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
            withCover(title, ^(CGImageRef cover) {
                if (!renderedFrame) {
                    CGImageRef frame = SGFillClipFrame(cover, size);
                    if (frame) renderedFrame = [UIImage imageWithCGImage:frame];
                    if (frame) CGImageRelease(frame);
                }
                CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:file.path]
                    || (renderedFrame && SGFillClipWriteFrame(file, renderedFrame.CGImage, size));
                SGLog(@"lock motion: Fill clip %@ %@ in %.0f ms", file.lastPathComponent,
                      ok ? @"ready" : @"not written", (CFAbsoluteTimeGetCurrent() - start) * 1000);
                completion(ok ? file : nil);
            });
        }];
    SGNowPlayingSetExtras(@"motion", @{MPNowPlayingInfoProperty3x4AnimatedArtwork: artwork}, title);
    SGLog(@"lock motion: Fill cover offered as %@", file.lastPathComponent);
}

void SGLockMotionShowPlain(BOOL plain) {
    if (@available(iOS 26.0, *)) {
        sg_plain = plain;
        BOOL want = plain && SGLockScreenCanvasLyricsEnabled() && motionOn(sg_choice) && sg_lyricsFile;
        if (want == sg_plainShown) return;
        sg_plainShown = want;
        if (want) show(sg_lyricsFile);
        else SGNowPlayingSetExtras(@"motion", nil, nil);
    }
}

%ctor {
    if (@available(iOS 26.0, *)) {
        sg_choice = SGLockScreenArtwork();
        sg_configuredChoice = sg_choice;
        sg_queue = dispatch_queue_create("spotifyglass.lockscreen.motion", DISPATCH_QUEUE_SERIAL);
        __block BOOL canvasLyrics = SGLockScreenCanvasLyricsEnabled();
        __block NSArray<NSString *> *starViews = SGLockScreenAvailableStarViews();
        __block BOOL starEnabled = SGHidden(SGKeyLockScreenStar);
        __block CGFloat coverScale = SGLockScreenCoverArtworkScale();
        __block NSUInteger coverScaleRequest = 0;
        // Each walk takes the last one's clip off first, so the lock screen falls back to the still cover.
        sg_follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *state) {
            SGLockScreenStarEnsureView();
            sg_walk++;
            SGNowPlayingSetExtras(@"motion", nil, nil);
            sg_lyricsFile = nil;
            sg_plainShown = NO;
            NSDictionary *metadata = [state.track.metadata isKindOfClass:NSDictionary.class] ? state.track.metadata : nil;
            sg_title = state.track.trackTitle;
            sg_picture = pictureOf(state.track, metadata);
            sg_choice = SGLockScreenArtwork();
            sg_configuredChoice = sg_choice;
            SGLockScreenSetEffectiveArtwork(sg_choice);
            if (sg_choice == SGLockArtworkFill) {
                showFill(sg_picture);
                return NO;
            }
            if (sg_choice == SGLockArtworkEverySong) {
                showCover(sg_picture);
                return NO;
            }
            return motionOn(sg_choice);
        } found:^(NSString *uri, NSURL *file) {
            if (file && SGLockScreenCanvasLyricsEnabled() && motionOn(sg_choice)) {
                sg_lyricsFile = file;
                SGLyricsArtworkSetMotion(uri, file);
                SGLockMotionShowPlain(sg_plain);
            } else if (file) {
                show(file);
            } else if (motionOn(sg_choice)) {
                advanceAfterMissingMotion();
            }
        }];
        // Heard on the writing thread and handed to main without waiting: a main-queue observer makes every
        // background defaults write wait for main, which deadlocks launch while main waits on Spotify's CoreThread.
        [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGLockScreenStarEnsureView();
                SGLockArtwork choice = SGLockScreenArtwork();
                BOOL lyrics = SGLockScreenCanvasLyricsEnabled();
                NSArray<NSString *> *newStarViews = SGLockScreenAvailableStarViews();
                BOOL newStarEnabled = SGHidden(SGKeyLockScreenStar);
                CGFloat newCoverScale = SGLockScreenCoverArtworkScale();
                BOOL modeChanged = choice != sg_configuredChoice || lyrics != canvasLyrics
                    || ![starViews isEqualToArray:newStarViews] || starEnabled != newStarEnabled;
                BOOL scaleChanged = newCoverScale != coverScale;
                if (!modeChanged && !scaleChanged) return;
                SGLog(@"lock motion: artwork mode, lock-screen lyrics or fallback cover size changed");
                sg_choice = choice;
                sg_configuredChoice = choice;
                canvasLyrics = lyrics;
                starViews = newStarViews;
                starEnabled = newStarEnabled;
                coverScale = newCoverScale;
                if (modeChanged) {
                    coverScaleRequest++;
                    [sg_follower restart];
                } else {
                    NSUInteger request = ++coverScaleRequest;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        if (request == coverScaleRequest && coverScale == SGLockScreenCoverArtworkScale())
                            [sg_follower restart];
                    });
                }
            });
        }];
        SGLog(@"lock motion: %@, the lock screen takes %@", motionOn(sg_choice) ? @"on" : @"off",
              MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys);
    }
}
