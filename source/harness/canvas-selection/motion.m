#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/AdBlock/Protobuf.h"
#import "Settings/SGModPage.h"
#import "Settings/SGSourcesPage.h"

static NSDictionary *headers;
static NSMutableArray *headerWaiters;
static NSMutableArray *appleWaiters;
static BOOL deferApple;
static id state;
static atomic_uint requests;
static NSURL *canvasFile(void) { return [NSURL fileURLWithPath:@"/tmp/canvas-test.mp4"]; }
static NSURL *appleFile(void) { return [NSURL fileURLWithPath:@"/tmp/apple-test.mp4"]; }
void SGLogMessage(NSString *message) {}
void SGRequireClasses(NSArray<NSString *> *names) {}
CGFloat SGMotionPixels(void) { return 600; }
void SGMotionFile(NSURL *remote, void (^done)(NSURL *)) { done(canvasFile()); }
void SGMotionAlbumCover(NSString *artist, NSString *album, SGMotionShape shape, CGFloat pixels, void (^done)(NSURL *)) {
    if (deferApple) [appleWaiters addObject:[done copy]];
    else done(appleFile());
}
void SGSpclientHeaders(void (^use)(NSDictionary *)) {
    if (headers) use(headers);
    else [headerWaiters addObject:[use copy]];
}
static void releaseHeaders(void) {
    headers = @{@"authorization": @"Bearer test-fixture"};
    NSArray *waiting = [headerWaiters copy]; [headerWaiters removeAllObjects];
    for (void (^use)(NSDictionary *) in waiting) use(headers);
}
@implementation SGSource
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail { return nil; }
@end
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) { return nil; }
SGModRow *SGWithSymbol(SGModRow *row, NSString *symbol) { return row; }
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray *all, NSArray *(^order)(void), void (^save)(NSArray *)) { return nil; }

@interface CanvasProtocol : NSURLProtocol @end
@implementation CanvasProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    atomic_fetch_add(&requests, 1);
    NSData *canvas = SGPBSerialize(@[SGPBString(2, @"https://video.invalid/canvas.mp4"), SGPBVarint(4, 1)]);
    NSData *body = SGPBSerialize(@[SGPBBytes(1, canvas)]);
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:body];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface TrackFixture : NSObject
@property NSString *URI, *artistName;
@property NSDictionary *metadata;
@end
@implementation TrackFixture @end
@interface StateFixture : NSObject
@property TrackFixture *track;
@property NSArray *future;
@property id contextURI, options;
@property BOOL isPaused, isPlaying, isLoading;
@property double position;
@end
@implementation StateFixture @end

@interface _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation : NSObject
- (void)player:(id)player stateDidChange:(id)state;
@end
@implementation _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation
- (void)player:(id)player stateDidChange:(id)state {}
@end
@interface SPTEsperantoPlayer : NSObject
- (void)addPlayerObserver:(id)observer;
@end
@implementation SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer {}
@end
#include "PlayerState.m"
static void sendState(id next) { @autoreleasepool { publish(next); } }


static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void waitFor(BOOL (^ready)(void), NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!ready() && until.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    require(ready(), @"Asynchronous artwork transition did not complete");
}
static void sourceOrder(NSArray *order) {
    [NSUserDefaults.standardUserDefaults setObject:order forKey:SGKeyMotionSources];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}
int main(void) {
    @autoreleasepool {
        headerWaiters = [NSMutableArray array]; appleWaiters = [NSMutableArray array];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.protocolClasses = @[CanvasProtocol.class];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
        method_setImplementation(class_getClassMethod(NSURLSession.class, @selector(sharedSession)), imp_implementationWithBlock(^NSURLSession *(id cls) { return session; }));
        sourceOrder(@[@"canvas"]);
        __block NSUInteger delivered = 0;
        SGMotionClipFor(@"spotify:track:late-headers", nil, @"Artist", @"Album", SGMotionTall, 600, ^(NSURL *file, NSString *source) {
            require([file isEqual:canvasFile()] && [source isEqual:@"canvas"], @"Canvas must resolve after late headers"); delivered++;
        });
        SGMotionClipFor(@"spotify:track:late-headers", nil, @"Artist", @"Album", SGMotionTall, 600, ^(NSURL *file, NSString *source) { delivered++; });
        require(delivered == 0 && atomic_load(&requests) == 0, @"Canvas must wait for initial headers instead of falling back");
        releaseHeaders();
        waitFor(^BOOL { return delivered == 2; }, 3);
        require(atomic_load(&requests) == 1, @"Concurrent Canvas lookups must share the request");
        headers = nil;
        __block BOOL timedOut = NO;
        SGMotionClipFor(@"spotify:track:header-timeout", nil, @"Artist", @"Album", SGMotionTall, 600, ^(NSURL *file, NSString *source) { require(file == nil, @"Header timeout must return no clip"); timedOut = YES; });
        waitFor(^BOOL { return timedOut; }, 6);
        releaseHeaders();
        __block BOOL retried = NO;
        SGMotionClipFor(@"spotify:track:header-timeout", nil, @"Artist", @"Album", SGMotionTall, 600, ^(NSURL *file, NSString *source) { require([file isEqual:canvasFile()], @"A header timeout must not cache Canvas as missing"); retried = YES; });
        waitFor(^BOOL { return retried; }, 3);
        require(atomic_load(&requests) == 2, @"A late header callback must not start an obsolete request");
        sourceOrder(@[@"applemusic"]);
        TrackFixture *track = [TrackFixture new]; track.URI = @"spotify:track:same-track"; track.artistName = @"Artist";
        track.metadata = @{@"album_title": @"Album", @"canvas.type": @"video", @"canvas.url": @"https://video.invalid/direct.mp4"};
        StateFixture *fixture = [StateFixture new]; fixture.track = track; fixture.isPlaying = YES; state = fixture;
        sendState(state);
        __block NSURL *shown;
        __block NSString *shownURI;
        __block NSUInteger found = 0, began = 0;
        SGMotionFollower *follower = [[SGMotionFollower alloc] initWithBegin:^BOOL(NSString *uri, SPTPlayerState *playing) { began++; return YES; }
            found:^(NSString *uri, NSURL *file) { shown = file; shownURI = uri; found++; }];
        [(id<SGPlayerStateObserver>)follower playerStateDidChange:state];
        require([shown isEqual:appleFile()], @"Apple Music must be used while it is the enabled source");
        dispatch_semaphore_t changed = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ sourceOrder(@[@"canvas"]); dispatch_semaphore_signal(changed); });
        require(dispatch_semaphore_wait(changed, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"Background defaults writes must not wait for the main queue");
        waitFor(^BOOL { return found >= 2 && [shown isEqual:canvasFile()]; }, 2);
        NSUInteger before = began;
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.canvas-test.unrelated"];
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        require(began == before, @"Unrelated settings must not restart artwork lookups");
        deferApple = YES; sourceOrder(@[@"applemusic"]);
        waitFor(^BOOL { return appleWaiters.count > 0; }, 2);
        sourceOrder(@[@"canvas"]);
        waitFor(^BOOL { return [shown isEqual:canvasFile()] && began > before + 1; }, 2);
        NSUInteger current = found;
        NSArray *waiting = [appleWaiters copy]; [appleWaiters removeAllObjects];
        for (void (^done)(NSURL *) in waiting) done(appleFile());
        require(found == current && [shown isEqual:canvasFile()], @"An obsolete disabled-source result must not replace Canvas");
        headers = nil;
        TrackFixture *skipped = [TrackFixture new]; skipped.URI = @"spotify:track:skip-late-canvas"; skipped.artistName = @"Artist"; skipped.metadata = @{};
        StateFixture *skippedState = [StateFixture new]; skippedState.track = skipped; skippedState.isPlaying = YES;
        state = skippedState; sendState(state);
        require(headerWaiters.count == 1, @"A skip before Canvas metadata must start one pending source lookup");
        before = began;
        skippedState.position = 1; sendState(state);
        require(began == before, @"Position-only updates must not restart Canvas lookups");
        skipped.metadata = @{@"canvas.type": @"video", @"canvas.url": @"https://video.invalid/skip.mp4"};
        sendState(state);
        require(began == before + 1 && [shownURI isEqual:skipped.URI] && [shown isEqual:canvasFile()],
                @"Canvas arriving after a skip must be published and replace the temporary fallback");
        before = began;
        skipped.metadata = @{@"canvas.type": @"video", @"canvas.url": @"https://video.invalid/updated-skip.mp4"};
        sendState(state);
        require(began == before + 1, @"An updated Canvas URL for the same track must be used");
        current = found;
        releaseHeaders();
        waitFor(^BOOL { return atomic_load(&requests) == 3; }, 3);
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        require(found == current && [shownURI isEqual:skipped.URI], @"A lookup overtaken by late Canvas metadata must stay obsolete");
        deferApple = YES; sourceOrder(@[@"applemusic"]);
        waitFor(^BOOL { return appleWaiters.count == 1; }, 2);
        for (NSString *uri in @[@"spotify:track:skip-next", @"spotify:track:skip-latest"]) {
            TrackFixture *next = [TrackFixture new]; next.URI = uri; next.artistName = @"Artist"; next.metadata = @{};
            StateFixture *nextState = [StateFixture new]; nextState.track = next; nextState.isPlaying = YES;
            state = nextState; sendState(state);
        }
        require(appleWaiters.count == 3, @"Rapid skips must keep independent in-flight lookups");
        current = found;
        waiting = [appleWaiters copy]; [appleWaiters removeAllObjects];
        ((void (^)(NSURL *))waiting[0])(appleFile());
        ((void (^)(NSURL *))waiting[1])(appleFile());
        require(found == current, @"Previous tracks must not overwrite artwork after rapid skips");
        ((void (^)(NSURL *))waiting[2])(appleFile());
        require(found == current + 1 && [shownURI isEqual:@"spotify:track:skip-latest"], @"Only the latest skipped track may publish artwork");
        __weak SGMotionFollower *weak = follower; follower = nil;
        require(weak == nil, @"Preferences observation must not retain the follower");
        puts("PASS: late request headers, shared requests, timeout recovery, same-track source changes, background writes, late Canvas metadata after skips and stale-track rejection");
    }
    return 0;
}
