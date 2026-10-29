// SGLastTrack.h says what this is for.
#import "Core/SGCore.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "PlayerState.h"
#import "SGLastTrack.h"

// The cover a track's metadata names, largest first: a local file's cover on the phone, or Spotify's picture on
// i.scdn.co.
static NSString *artworkIn(NSDictionary *metadata) {
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url"]) {
        id value = metadata[field];
        if (![value isKindOfClass:NSString.class] || ![value length]) continue;
        NSString *local = SGLocalFileCoverInURL(value);
        if (local) return [NSURL fileURLWithPath:local].absoluteString;
        if ([value hasPrefix:@"https://"]) return value;
        if ([value hasPrefix:@"spotify:image:"]) return [@"https://i.scdn.co/image/" stringByAppendingString:[value substringFromIndex:14]];
    }
    return nil;
}

// A track as stored: strings only, nil for none or an ad.
static NSDictionary<NSString *, NSString *> *describe(SPTPlayerTrack *track) {
    NSString *uri = SGURIString(track.URI);
    if (!uri.length || [uri hasPrefix:@"spotify:ad:"]) return nil;
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] && [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    NSMutableDictionary *described = [@{@"uri": uri} mutableCopy];
    described[@"title"] = track.trackTitle.length ? track.trackTitle : nil;
    described[@"artist"] = [track.artistName isKindOfClass:NSString.class] ? track.artistName : nil;
    described[@"album"] = [metadata[@"album_title"] isKindOfClass:NSString.class] ? metadata[@"album_title"] : nil;
    described[@"artwork"] = artworkIn(metadata);
    described[@"canvas"] = SGMotionCanvasIn(metadata).absoluteString;
    return described;
}

@implementation SGShownTrack

- (instancetype)initWith:(NSDictionary<NSString *, NSString *> *)described current:(BOOL)current {
    if (!(self = [super init])) return nil;
    _uri = described[@"uri"];
    _title = described[@"title"];
    _artist = described[@"artist"];
    _album = described[@"album"];
    _artworkURL = described[@"artwork"] ? [NSURL URLWithString:described[@"artwork"]] : nil;
    _canvasURL = described[@"canvas"] ? [NSURL URLWithString:described[@"canvas"]] : nil;
    _current = current;
    return self;
}

@end

static NSDictionary *stored(void) {
    NSDictionary *value = [NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyLastTrack];
    return [value[@"uri"] isKindOfClass:NSString.class] && [value[@"title"] isKindOfClass:NSString.class] ? value : nil;
}

SGShownTrack *SGShownTrackNow(void) {
    NSDictionary *now = describe(SGPlayerState().track);
    if (now) return [[SGShownTrack alloc] initWith:now current:YES];
    NSDictionary *last = stored();
    return last ? [[SGShownTrack alloc] initWith:last current:NO] : nil;
}

#pragma mark - the last track, stored

@interface SGLastTrackRecorder : NSObject <SGPlayerStateObserver>
@end

@implementation SGLastTrackRecorder {
    NSDictionary *_last;
}

// Written only when it changes: a new track, or its metadata filled in (a Canvas that came late). A track with no
// title yet (still loading) is not kept.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSDictionary *track = describe(state.track);
    if (!track[@"title"] || [track isEqualToDictionary:_last ?: stored()]) return;
    _last = track;
    [NSUserDefaults.standardUserDefaults setObject:track forKey:SGKeyLastTrack];
}

@end

__attribute__((constructor)) static void sg_recordLastTrack(void) {
    static SGLastTrackRecorder *recorder;   // the observers are held weakly
    recorder = [SGLastTrackRecorder new];
    SGAddPlayerStateObserver(recorder);
}

#pragma mark - the artwork

static NSURL *sg_artworkURL;
static UIImage *sg_artwork;

void SGShownTrackArtwork(SGShownTrack *track, void (^done)(UIImage *image)) {
    NSURL *url = track.artworkURL;
    if (!url) {
        done(nil);
        return;
    }
    if (sg_artwork && [url isEqual:sg_artworkURL]) {
        done(sg_artwork);
        return;
    }
    void (^decode)(NSData *) = ^(NSData *data) {
        UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
        image = image.imageByPreparingForDisplay ?: image;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (image) {
                sg_artworkURL = url;
                sg_artwork = image;
            }
            done(image);
        });
    };
    if (url.isFileURL) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ decode([NSData dataWithContentsOfURL:url]); });
        return;
    }
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        decode(status == 200 ? data : nil);
    }] resume];
}

UIImage *SGPlaceholderArtwork(UIColor *tint) {
    CGFloat side = 240;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        // The tint, muted and dim, at the top left to near black at the bottom right, so the fields made from it (Colors,
        // Fluid) have two calm colors to move between rather than the accent at full strength.
        CGFloat h = 0, s = 0, b = 0, a = 0;
        [tint getHue:&h saturation:&s brightness:&b alpha:&a];
        UIColor *light = [UIColor colorWithHue:h saturation:s * 0.55 brightness:b * 0.5 alpha:1];
        UIColor *dark = [UIColor colorWithHue:fmod(h + 0.06, 1) saturation:s * 0.6 brightness:b * 0.16 alpha:1];
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)@[(id)light.CGColor, (id)dark.CGColor], NULL);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointZero, CGPointMake(side, side), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        UIImageSymbolConfiguration *weight = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.32 weight:UIImageSymbolWeightMedium];
        UIImage *note = [[UIImage systemImageNamed:@"music.note" withConfiguration:weight] imageWithTintColor:[UIColor colorWithWhite:1 alpha:0.45]
                                                                                                 renderingMode:UIImageRenderingModeAlwaysOriginal];
        [note drawAtPoint:CGPointMake((side - note.size.width) / 2, (side - note.size.height) / 2)];
    }];
}
