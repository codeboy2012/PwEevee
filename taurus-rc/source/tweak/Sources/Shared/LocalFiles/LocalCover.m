// A local file's own cover for where Spotify's player shows its placeholder (LocalFiles.h). The lock
// screen and the queue show the cover of such a file, so it is there to find: first in the image fields
// of the track's metadata, read as a picture or a readable file, then in the system's now playing info,
// taken only while its title and artist agree with the track's.
//
// Threading: main thread. A picture found is kept per track; a miss is tried again after a second, since
// the now playing info may not have caught up with the track yet.
#import <MediaPlayer/MediaPlayer.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"

static const NSUInteger kKept = 8;
static const NSTimeInterval kRetry = 1;
static const CGFloat kSide = 1200;

static NSMutableDictionary<NSString *, UIImage *> *sg_found;
static NSMutableDictionary<NSString *, NSDate *> *sg_missed;

// A file URL, an absolute path, or Spotify's own reading of a value (-[NSURL spt_localFileImagePath],
// asked only when the object answers it as a getter of an object).
static NSString *pathIn(id value) {
    if ([value isKindOfClass:NSString.class] && [value hasPrefix:@"/"]) return value;
    NSURL *url = [value isKindOfClass:NSURL.class] ? value : [value isKindOfClass:NSString.class] ? [NSURL URLWithString:value] : nil;
    if (url.isFileURL) return url.path;
    SEL getter = NSSelectorFromString(@"spt_localFileImagePath");
    if (![url respondsToSelector:getter]) return nil;
    NSMethodSignature *signature = [url methodSignatureForSelector:getter];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    id path = ((id (*)(id, SEL))objc_msgSend)(url, getter);
    return [path isKindOfClass:NSString.class] && [path length] ? path : nil;
}

static UIImage *fromMetadata(NSDictionary *metadata) {
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        id value = metadata[field];
        if ([value isKindOfClass:UIImage.class]) return value;
        NSString *path = pathIn(value);
        if (!path || ![NSFileManager.defaultManager isReadableFileAtPath:path]) continue;
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (image) return image;
    }
    return nil;
}

// Case, diacritics and width ignored; a side with no value agrees with anything.
static BOOL agrees(id mine, id theirs) {
    if (![mine isKindOfClass:NSString.class] || ![theirs isKindOfClass:NSString.class] || ![mine length] || ![theirs length]) return YES;
    return [mine compare:theirs options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch] == NSOrderedSame;
}

static UIImage *fromNowPlaying(SPTPlayerTrack *track) {
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    MPMediaItemArtwork *artwork = info[MPMediaItemPropertyArtwork];
    if (![artwork isKindOfClass:MPMediaItemArtwork.class]) return nil;
    if (!agrees(track.trackTitle, info[MPMediaItemPropertyTitle]) || !agrees(track.artistName, info[MPMediaItemPropertyArtist])) return nil;
    return [artwork imageWithSize:CGSizeMake(kSide, kSide)];
}

UIImage *SGLocalFileFallbackCover(SPTPlayerTrack *track) {
    NSString *uri = SGURIString(track.URI);
    // A cover picked in Edit info comes through Spotify's own loader and wins.
    if (!SGLocalFileIs(uri) || SGLocalFileCoverPath(SGLocalFileEditFor(uri))) return nil;
    if (!sg_found) {
        sg_found = [NSMutableDictionary dictionary];
        sg_missed = [NSMutableDictionary dictionary];
    }
    UIImage *image = sg_found[uri];
    if (image) return image;
    NSDate *missed = sg_missed[uri];
    if (missed && -missed.timeIntervalSinceNow < kRetry) return nil;
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    image = fromMetadata(metadata);
    NSString *source = @"its metadata";
    if (!image) {
        image = fromNowPlaying(track);
        source = @"the system's now playing";
    }
    if (!image.CGImage && !image.CIImage) {
        if (sg_missed.count >= kKept * 4) [sg_missed removeAllObjects];
        sg_missed[uri] = NSDate.date;
        return nil;
    }
    if (sg_found.count >= kKept) [sg_found removeAllObjects];
    sg_found[uri] = image;
    [sg_missed removeObjectForKey:uri];
    SGLog(@"local files: %@ has its cover from %@", uri, source);
    return image;
}
