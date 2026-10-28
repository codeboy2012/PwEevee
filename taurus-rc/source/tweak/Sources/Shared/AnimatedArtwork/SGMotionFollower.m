// SGMotionFollower (AnimatedArtwork.h): one track's walk of the sources at a time, for the lock screen
// (LockScreenMotion.x) and the redesign's player (Redesigned/Player/PlayerMotion.x) alike.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "AnimatedArtwork.h"
#import "SGMotionClip.h"

@interface SGMotionFollower () <SGPlayerStateObserver>
@end

@implementation SGMotionFollower {
    BOOL (^_begin)(NSString *, SPTPlayerState *);
    void (^_found)(NSString *, NSURL *);
    NSString *_track;    // the URI walked last
    BOOL _walked;        // whether `begin` let it be walked
    NSURL *_canvas;      // the Canvas its metadata named as the walk began, nil for none
    NSString *_source;   // where the clip found came from, nil for none or not found yet
    NSUInteger _walk;    // counts the walks, so an overtaken one is told from the newest
    NSString *_ahead;    // the next track whose clip was fetched ahead
    NSArray<NSString *> *_sourceOrder;
    id _preferencesObserver;
}

- (instancetype)initWithBegin:(BOOL (^)(NSString *, SPTPlayerState *))begin found:(void (^)(NSString *, NSURL *))found {
    if (!(self = [super init])) return nil;
    _begin = [begin copy];
    _found = [found copy];
    _sourceOrder = [SGMotionSourceOrder() copy];
    __weak SGMotionFollower *weakSelf = self;
    _preferencesObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SGMotionFollower *follower = weakSelf;
                if (!follower) return;
                NSArray<NSString *> *order = SGMotionSourceOrder();
                if ([follower->_sourceOrder isEqualToArray:order]) return;
                follower->_sourceOrder = [order copy];
                [follower restart];
            });
        }];
    SGAddPlayerStateObserver(self);
    return self;
}

- (void)dealloc {
    if (_preferencesObserver) [NSNotificationCenter.defaultCenter removeObserver:_preferencesObserver];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (!uri) return;
    NSURL *canvas = SGMotionCanvasIn(state.track.metadata);
    if ([uri isEqualToString:_track]) {
        if (!_walked || !canvas || [canvas isEqual:_canvas]) return;
        if (![_source isEqualToString:@"canvas"] && !SGMotionCanvasOutranks(SGMotionSourceOrder(), _source)) return;
        SGLog(@"motion: the Canvas metadata of %@ changed, asked again", uri);
    }
    [self walk:state uri:uri canvas:canvas];
}

- (void)walk:(SPTPlayerState *)state uri:(NSString *)uri canvas:(NSURL *)canvas {
    _track = uri;
    _canvas = canvas;
    _source = nil;
    NSUInteger walk = ++_walk;
    _walked = _begin(uri, state);
    if (!_walked) return;
    NSDictionary *metadata = [state.track.metadata isKindOfClass:NSDictionary.class] ? state.track.metadata : nil;
    __weak SGMotionFollower *weakSelf = self;
    SGMotionClipFor(uri, canvas, state.track.artistName, metadata[@"album_title"], SGMotionTall, SGMotionPixels(), ^(NSURL *file, NSString *source) {
        SGMotionFollower *follower = weakSelf;
        if (!follower || walk != follower->_walk) return;
        follower->_source = source;
        follower->_found(uri, file);
        [follower fetchAhead];
    });
}

// The next track's clip, fetched into the store once, so a skip finds it there.
- (void)fetchAhead {
    SPTPlayerState *state = SGPlayerState();
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
    if (![next isKindOfClass:objc_getClass("SPTPlayerTrack")]) return;
    SPTPlayerTrack *track = next;
    NSString *uri = SGURIString(track.URI);
    if (!uri || [uri isEqualToString:_track] || [uri isEqualToString:_ahead]) return;
    _ahead = uri;
    NSDictionary *metadata = [track.metadata isKindOfClass:NSDictionary.class] ? track.metadata : nil;
    SGMotionClipFor(uri, SGMotionCanvasIn(metadata), track.artistName, metadata[@"album_title"], SGMotionTall, SGMotionPixels(),
                    ^(NSURL *file, NSString *source) {
        SGLog(@"motion: the next track's clip fetched ahead: %@", file ? source : @"none");
    });
}

- (void)restart {
    _track = nil;
    _ahead = nil;
    _walk++;
    SPTPlayerState *state = SGPlayerState();
    if (state) [self playerStateDidChange:state];
}

@end
