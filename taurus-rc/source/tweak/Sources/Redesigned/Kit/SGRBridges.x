#import "Core/SGCore.h"
#import "Shared/Player/PlayerEvents.h"
#import "SGRBridges.h"
#import "SGRedesign.h"
#import "SGRRestyle.h"

#pragma mark - now playing artwork

NSNotificationName const SGRNowPlayingArtworkDidChangeNotification = @"spotifyglass.redesign.nowPlayingArtworkDidChange";

// The picture published, the track it was published for, the picture it is (its key) and how it was had.
static UIImage *sg_artwork;
static NSString *sg_artworkURI, *sg_artworkKey;
static SGRArtworkQuality sg_artworkQuality;
static NSUInteger sg_artworkSerial;
// The playing track and the picture its metadata names.
static NSString *sg_wantedURI, *sg_wantedKey;
static NSMapTable<UIImage *, NSString *> *sg_published;
static NSURLSessionDataTask *sg_fetch;

// Retries of a fetch that failed, and how long before each.
static const NSTimeInterval kFetchRetry = 2;
static const NSUInteger kFetchAttempts = 2;

static void artworkLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void artworkLog(NSString *format, ...) {
    static NSUInteger logged;
    if (logged++ >= 40) return;
    va_list args;
    va_start(args, format);
    SGLog(@"redesign kit: artwork %@", [[NSString alloc] initWithFormat:format arguments:args]);
    va_end(args);
}

// The image id in a metadata value: spotify:image:<id>, or an https URL ending in it.
static NSString *imageIDIn(id value) {
    if (![value isKindOfClass:NSString.class] || ![value length]) return nil;
    NSString *string = value;
    if ([string hasPrefix:@"spotify:image:"]) return [string substringFromIndex:@"spotify:image:".length];
    if ([string hasPrefix:@"https://"]) return string.lastPathComponent;
    return nil;
}

// The picture a track names, largest first, and where it can be fetched from.
static NSString *pictureOf(SPTPlayerTrack *track, NSURL **url) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (![metadata isKindOfClass:NSDictionary.class]) return nil;
    for (NSString *field in @[@"image_xlarge_url", @"image_large_url", @"image_url", @"image_small_url"]) {
        NSString *value = metadata[field], *identifier = imageIDIn(value);
        if (!identifier) continue;
        if (url) *url = [value hasPrefix:@"https://"] ? [NSURL URLWithString:value]
                                                     : [NSURL URLWithString:[@"https://i.scdn.co/image/" stringByAppendingString:identifier]];
        // Every size of one picture shares its last 24 digits; the first 16 are the size.
        return identifier.length == 40 ? [identifier substringFromIndex:16] : identifier;
    }
    return nil;
}

static void publish(UIImage *image, NSString *key, SGRArtworkQuality quality) {
    sg_artwork = image;
    sg_artworkURI = sg_wantedURI;
    sg_artworkKey = key;
    sg_artworkQuality = quality;
    sg_artworkSerial++;
    [sg_published setObject:key forKey:image];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRNowPlayingArtworkDidChangeNotification object:nil userInfo:@{
        @"image": image,
        @"trackURI": sg_wantedURI ?: @"",
        @"quality": @(quality),
    }];
}

static NSURLSession *artworkSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
        // An image id is the picture's own digest, so a stored answer never goes stale.
        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        configuration.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:24 * 1024 * 1024
                                                               directoryURL:[caches URLByAppendingPathComponent:@"spotifyglass-artwork"]];
        configuration.requestCachePolicy = NSURLRequestReturnCacheDataElseLoad;
        configuration.timeoutIntervalForRequest = 20;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

static void fetchPicture(NSString *key, NSURL *url, NSUInteger attempt);

static void finishPicture(NSString *key, NSURL *url, NSUInteger attempt, NSInteger status, NSError *error,
                          UIImage *image, CFTimeInterval started) {
    if (![key isEqualToString:sg_wantedKey]) {
        artworkLog(@"%@ came after the track moved on to %@, dropped", key, sg_wantedKey);
        return;
    }
    if (!image) {
        artworkLog(@"%@ not fetched (%ld, %@), attempt %lu", key, (long)status, error.localizedDescription, (unsigned long)attempt + 1);
        if (attempt + 1 >= kFetchAttempts) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFetchRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if ([key isEqualToString:sg_wantedKey] && !([sg_artworkKey isEqualToString:key] && sg_artworkQuality == SGRArtworkQualityExact)) {
                fetchPicture(key, url, attempt + 1);
            }
        });
        return;
    }
    artworkLog(@"%@ fetched %.0fx%.0f in %.0f ms", key, image.size.width, image.size.height, (CACurrentMediaTime() - started) * 1000);
    publish(image, key, SGRArtworkQualityExact);
}

static void fetchPicture(NSString *key, NSURL *url, NSUInteger attempt) {
    CFTimeInterval started = CACurrentMediaTime();
    sg_fetch = [artworkSession() dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error.code == NSURLErrorCancelled) return;
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![key isEqualToString:sg_wantedKey]) {
                artworkLog(@"%@ came after the track moved on to %@, dropped", key, sg_wantedKey);
                return;
            }
            if (!data.length || status != 200) {
                finishPicture(key, url, attempt, status, error, nil, started);
                return;
            }
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                UIImage *image = [UIImage imageWithData:data];
                // Skip decoding stale downloads before they consume memory and CPU.
                image = image.imageByPreparingForDisplay ?: image;
                dispatch_async(dispatch_get_main_queue(), ^{
                    finishPicture(key, url, attempt, status, error, image, started);
                });
            });
        });
    }];
    [sg_fetch resume];
}

static void followPlayer(void) {
    SPTPlayerTrack *track = SGPlayerState().track;
    NSString *uri = SGURIString(track.URI);
    if (!uri) return;
    // The same track is looked at again only while its metadata has named no picture yet.
    if ([uri isEqualToString:sg_wantedURI] && ![sg_wantedKey hasPrefix:@"track:"]) return;
    sg_wantedURI = uri;
    NSURL *url = nil;
    // A track whose metadata names no picture is its own key: only the screens can show it then.
    NSString *key = pictureOf(track, &url) ?: [@"track:" stringByAppendingString:uri];
    if ([key isEqualToString:sg_wantedKey]) return;
    sg_wantedKey = key;
    [sg_fetch cancel];
    sg_fetch = nil;
    if ([key isEqualToString:sg_artworkKey] && sg_artworkQuality == SGRArtworkQualityExact) return;
    if (url) fetchPicture(key, url, 0);
}

void SGRSetNowPlayingArtwork(UIImage *image, NSString *trackURI, SGRArtworkQuality quality) {
    if (!image || !trackURI) return;
    followPlayer();
    // Read for a track that is no longer playing.
    if (![trackURI isEqualToString:sg_wantedURI]) return;
    NSString *key = sg_wantedKey;
    NSString *publishedAs = [sg_published objectForKey:image];
    // The screen still shows a picture published for another one.
    if (publishedAs && ![publishedAs isEqualToString:key]) {
        artworkLog(@"%@ still on screen while %@ is wanted, not believed", publishedAs, key);
        return;
    }
    if ([key isEqualToString:sg_artworkKey] && (image == sg_artwork || quality < sg_artworkQuality)) return;
    publish(image, key, MIN(quality, SGRArtworkQualityHigh));
}

UIImage *SGRNowPlayingArtwork(NSString **trackURI, NSString **identity) {
    if (trackURI) *trackURI = sg_artworkURI;
    if (identity) {
        *identity = !sg_artwork ? nil : sg_artworkQuality == SGRArtworkQualityExact
            ? [sg_artworkKey stringByAppendingString:@"#exact"]
            : [NSString stringWithFormat:@"%@#%lu", sg_artworkKey, (unsigned long)sg_artworkSerial];
    }
    return sg_artwork;
}

// The player's reports, in the order they come.
@interface SGRArtworkFollower : NSObject <SGPlayerStateObserver>
@end

@implementation SGRArtworkFollower
- (void)playerStateDidChange:(SPTPlayerState *)state {
    followPlayer();
}
@end

static SGRArtworkFollower *sg_follower;

static char kBarCardKey, kBarImageKey;
static __weak UIView *sg_barView;

static void publishBarArtwork(NSString *expectedURI) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    if (!uri || (expectedURI && ![expectedURI isEqualToString:uri])) return;
    UIView *card = SGRFindByIdentifier(sg_barView, @"SPTNowPlayingBar", &kBarCardKey);
    UIView *holder = SGRFindByIdentifier(card, @"Encore.ImageView", &kBarImageKey);
    UIImageView *cover = nil;
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) cover = (UIImageView *)sub;
    }
    UIImage *image = cover.image;
    if (!image) return;
    SGRSetNowPlayingArtwork(image, uri, SGRArtworkQualityLow);
}

@interface SGRBarArtworkWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRBarArtworkWatcher {
    NSString *_track;
    NSUInteger _generation;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *track = SGURIString(state.track.URI);
    if (!track || [track isEqualToString:_track]) return;
    _track = track;
    NSUInteger generation = ++_generation;
    for (NSNumber *delay in @[@0, @0.3, @1, @2.5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation == self->_generation) publishBarArtwork(track);
        });
    }
}

@end

static SGRBarArtworkWatcher *sg_barWatcher;

%group SGRBarArtworkHooks
%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    sg_barView = ((UIViewController *)self).viewIfLoaded;
    publishBarArtwork(nil);
}
%end
%end

#pragma mark - the player's open and close

BOOL SGRPlayerIsTransitioning(void) {
    return SGPlayerTransitionEnds() > 0;
}

@interface SGRTransitionObservation : NSObject
@property (nonatomic, strong) NSArray *tokens;
@end

@implementation SGRTransitionObservation
- (void)dealloc {
    for (id token in self.tokens) [NSNotificationCenter.defaultCenter removeObserver:token];
}
@end

static char kTransitionKey;

void SGRObservePlayerTransition(id owner, void (^began)(id owner), void (^ended)(id owner)) {
    if (!owner) return;
    __weak id weakOwner = owner;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    NSMutableArray *tokens = [NSMutableArray array];
    if (began) {
        [tokens addObject:[center addObserverForName:SGPlayerTransitionNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            id strongOwner = weakOwner;
            if (strongOwner) began(strongOwner);
        }]];
    }
    if (ended) {
        [tokens addObject:[center addObserverForName:SGPlayerTransitionEndedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            id strongOwner = weakOwner;
            if (strongOwner) ended(strongOwner);
        }]];
    }
    SGRTransitionObservation *observation = [SGRTransitionObservation new];
    observation.tokens = tokens;
    NSMutableArray *kept = objc_getAssociatedObject(owner, &kTransitionKey);
    if (!kept) {
        kept = [NSMutableArray array];
        objc_setAssociatedObject(owner, &kTransitionKey, kept, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [kept addObject:observation];
}

%ctor {
    if (!SGRedesignedUI()) return;
    // By pointer: two images of one picture are still two reads.
    sg_published = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                             valueOptions:NSPointerFunctionsStrongMemory capacity:16];
    // Ahead of the watchers, so the picture a track wants is known before any screen is read for it.
    sg_follower = [SGRArtworkFollower new];
    SGAddPlayerStateObserver(sg_follower);
    sg_barWatcher = [SGRBarArtworkWatcher new];
    SGAddPlayerStateObserver(sg_barWatcher);
    %init(SGRBarArtworkHooks);
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
}
