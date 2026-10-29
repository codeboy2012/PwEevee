#import "Core/SGCore.h"
#import "Core/SGURLSession.h"
#import "Shared/AdBlock/AdBlock.h"

BOOL SGFlag(NSString *key, BOOL fallback) { return YES; }
void SGLogMessage(NSString *message) {}
void SGRequireClasses(NSArray *names) {}
void SGAdBlockSawOne(NSString *label) {}
void SGAdBlockCountOne(NSString *label) {}
NSData *SGPatchBootstrap(NSData *body) { return [@"bootstrap" dataUsingEncoding:NSUTF8StringEncoding]; }
static BOOL customizeTransformFails;
NSData *SGPatchCustomize(NSData *body) {
    if (customizeTransformFails) return nil;
    return [@"premium" dataUsingEncoding:NSUTF8StringEncoding];
}
NSData *SGStripFeed(NSData *body) { return [@"feed" dataUsingEncoding:NSUTF8StringEncoding]; }

@interface SGRequestTask : NSURLSessionTask
@property(nonatomic) NSURLRequest *current;
@property(nonatomic) NSURLRequest *original;
@property(nonatomic) BOOL throwsCurrent;
@property(nonatomic) BOOL throwsOriginal;
@property(nonatomic) NSUInteger resumes;
@property(nonatomic) NSUInteger cancels;
@end
@implementation SGRequestTask
- (NSURLRequest *)currentRequest {
    if (self.throwsCurrent) [NSException raise:NSInternalInconsistencyException format:@"unsupported currentRequest"];
    return self.current;
}
- (NSURLRequest *)originalRequest {
    if (self.throwsOriginal) [NSException raise:NSInternalInconsistencyException format:@"unsupported originalRequest"];
    return self.original;
}
- (void)cancel { self.cancels++; }
@end

static NSUInteger assetGetterCalls;
@interface SGAggregateTask : AVAggregateAssetDownloadTask @end
@implementation SGAggregateTask
- (NSURLRequest *)currentRequest { assetGetterCalls++; [NSException raise:NSInternalInconsistencyException format:@"aggregate currentRequest"]; return nil; }
- (NSURLRequest *)originalRequest { assetGetterCalls++; [NSException raise:NSInternalInconsistencyException format:@"aggregate originalRequest"]; return nil; }
@end
@interface SGAssetTask : AVAssetDownloadTask @end
@implementation SGAssetTask
- (NSURLRequest *)currentRequest { assetGetterCalls++; [NSException raise:NSInternalInconsistencyException format:@"asset currentRequest"]; return nil; }
- (NSURLRequest *)originalRequest { assetGetterCalls++; [NSException raise:NSInternalInconsistencyException format:@"asset originalRequest"]; return nil; }
@end

@interface SGDelegate : NSObject <NSURLSessionDataDelegate>
@property(nonatomic) NSMutableData *received;
@property(nonatomic) NSUInteger calls;
@end
@implementation SGDelegate
- (instancetype)init { if ((self = [super init])) _received = [NSMutableData data]; return self; }
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    [self.received appendData:data];
    self.calls++;
}
@end

#include "AdNetwork.m"

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void originalResume(id task, SEL selector) { ((SGRequestTask *)task).resumes++; }
static SGRequestTask *requestTask(NSString *address) {
    SGRequestTask *task = class_createInstance(SGRequestTask.class, 0);
    task.current = [NSURLRequest requestWithURL:[NSURL URLWithString:address]];
    task.original = task.current;
    return task;
}

int main(void) {
    @autoreleasepool {
        method_setImplementation(class_getInstanceMethod(NSURLSessionTask.class, @selector(resume)), (IMP)originalResume);
        SGTestInstallHooks();
        started = [NSDate dateWithTimeIntervalSinceNow:-60];

        SGRequestTask *media = requestTask(@"https://audio.example.test/song");
        [media resume];
        require(media.resumes == 1 && media.cancels == 0, @"Media tasks still resume");

        // Customize is interceptable only while a rewritten body is available to answer with. On a
        // cold cache there is nothing to replay, so the fetch goes out and is rewritten on arrival.
        SGRequestTask *coldRefetch = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        [coldRefetch resume];
        require(coldRefetch.resumes == 1 && coldRefetch.cancels == 0, @"A cold-cache customize still goes out");
        @synchronized (cacheLock) { cachedCustomize = json(@"premium"); }
        SGRequestTask *refetch = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        [refetch resume];
        require(refetch.cancels == 1 && refetch.resumes == 0, @"Premium refetch protection still cancels once a body can be replayed");
        @synchronized (cacheLock) { cachedCustomize = nil; }
        started = NSDate.date;
        SGRequestTask *login = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        [login resume];
        require(login.resumes == 1 && login.cancels == 0, @"Initial login stays allowed");

        SGRequestTask *unsupported = class_createInstance(SGRequestTask.class, 0);
        unsupported.throwsCurrent = unsupported.throwsOriginal = YES;
        [unsupported resume];
        require(unsupported.resumes == 1, @"Tasks with unsupported request getters still resume");
        SGRequestTask *fallback = requestTask(@"https://audio.example.test/original");
        fallback.current = nil;
        require([SGURLSessionTaskURL(fallback) isEqual:fallback.original.URL], @"Original request remains the fallback");
        fallback.throwsCurrent = YES;
        require([SGURLSessionTaskURL(fallback) isEqual:fallback.original.URL], @"A throwing current getter does not hide a valid original");

        NSArray *assets = @[class_createInstance(SGAggregateTask.class, 0),
                            class_createInstance(SGAssetTask.class, 0), unsupported];
        for (NSURLSessionTask *task in assets) {
            require(!SGURLSessionTaskURL(task), @"Asset tasks are not classified as HTTP config");
            require(!holds(task, [NSData data]), @"Asset data is passed through");
            NSError *failure = [NSError errorWithDomain:@"fixture" code:7 userInfo:nil];
            __block BOOL forwarded = NO;
            complete(nil, nil, task, failure, ^(NSError *error) { forwarded = error == failure; });
            require(forwarded, @"Asset completion preserves the original error");
        }
        require(assetGetterCalls == 0, @"AVFoundation request getters are never invoked");

        SGDelegate *delegate = [SGDelegate new];
        SGRequestTask *ad = requestTask(@"https://spclient.wg.spotify.com/ads/v2/config");
        require(holds(ad, [@"ad" dataUsingEncoding:NSUTF8StringEncoding]), @"Ad response remains blocked");
        __block BOOL ended = NO;
        complete(delegate, nil, ad, nil, ^(NSError *error) { ended = !error; });
        require(ended && delegate.received.length == 0, @"Ad requests still finish with an empty successful reply");

        // Past the login window with nothing cached: the body is buffered and rewritten on arrival,
        // so the delegate gets the config rather than a zero-byte 200.
        started = [NSDate dateWithTimeIntervalSinceNow:-60];
        @synchronized (cacheLock) { cachedCustomize = nil; }
        SGRequestTask *cold = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(holds(cold, [@"original" dataUsingEncoding:NSUTF8StringEncoding]), @"Cold-cache config body is held back");
        delegate.received = [NSMutableData data];
        __block BOOL coldEnded = NO;
        complete(delegate, nil, cold, nil, ^(NSError *error) { coldEnded = !error; });
        require(coldEnded && [delegate.received isEqual:json(@"premium")],
                @"Cold-cache config is rewritten on arrival, not answered empty");
        require(replayable().length > 0, @"The rewrite becomes the replayable cache");

        // A genuine transport failure on that path keeps its error; nothing is fabricated.
        @synchronized (cacheLock) { cachedCustomize = nil; }
        SGRequestTask *broken = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        NSError *transport = [NSError errorWithDomain:@"fixture" code:53 userInfo:nil];
        __block BOOL keptError = NO;
        complete(nil, nil, broken, transport, ^(NSError *error) { keptError = error == transport; });
        require(keptError, @"A failed cold-cache customize keeps its error");

        // A body the transform cannot rewrite is passed through untouched, never replaced by empty.
        customizeTransformFails = YES;
        NSData *raw = [@"unparsed" dataUsingEncoding:NSUTF8StringEncoding];
        SGRequestTask *unpatched = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(holds(unpatched, raw), @"Unrewritable config body is held back");
        delegate.received = [NSMutableData data];
        complete(delegate, nil, unpatched, nil, ^(NSError *error) {});
        require([delegate.received isEqual:raw], @"An unrewritable config passes through rather than empty");
        customizeTransformFails = NO;

        started = NSDate.date;
        delegate.received = [NSMutableData data];
        SGRequestTask *customize = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(holds(customize, [@"original" dataUsingEncoding:NSUTF8StringEncoding]), @"Config body is buffered");
        complete(delegate, nil, customize, nil, ^(NSError *error) {});
        require([delegate.received isEqual:json(@"premium")], @"Buffered config still reaches the Premium transform");
        NSHTTPURLResponse *notModified = [[NSHTTPURLResponse alloc] initWithURL:customize.current.URL statusCode:304 HTTPVersion:nil headerFields:nil];
        NSData *replayed = nil;
        NSHTTPURLResponse *replay = replayFor(customize, notModified, &replayed);
        require(replay.statusCode == 200, @"Cached Premium config still replays for 304");
        require([replayed isEqual:json(@"premium")], @"The 304 replay delivers the body that was validated");

        // An empty cache is a failed rewrite, not a config: a 304 must pass through with its own
        // headers rather than become a 200 that carries zero bytes.
        @synchronized (cacheLock) { cachedCustomize = [NSData data]; }
        require(replayFor(customize, notModified, NULL) == nil, @"A 304 over an empty cache is not answered with a fabricated 200");
        @synchronized (cacheLock) { cachedCustomize = nil; }
        require(replayFor(customize, notModified, NULL) == nil, @"A 304 with no cache is not answered either");
        require(canReplayCustomize(@"/v1/customize") == NO, @"The gate refuses an empty cache");

        // The completion half of the same case: a 304 that had nothing to replay reaches the delegate
        // as Spotify sent it. Inventing a body here is the zero-byte 200 one layer down.
        SGRequestTask *unchanged = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(replayFor(unchanged, notModified, NULL) == nil, @"The 304 is not answered");
        delegate.received = [NSMutableData data];
        delegate.calls = 0;
        __block BOOL unchangedEnded = NO;
        complete(delegate, nil, unchanged, nil, ^(NSError *error) { unchangedEnded = !error; });
        require(unchangedEnded && delegate.calls == 0,
                @"A 304 with no replay completes untouched rather than with an empty body");

        SGRequestTask *failedUnchanged = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(replayFor(failedUnchanged, notModified, NULL) == nil, @"The second 304 is not answered");
        __block BOOL unchangedKept = NO;
        complete(nil, nil, failedUnchanged, transport, ^(NSError *error) { unchangedKept = error == transport; });
        require(unchangedKept, @"A passed-through 304 keeps its own error");

        // Non-customize control: the gate and the 304 synthesis are customize-only, while a
        // bootstrap body still goes through its own transform on completion.
        SGRequestTask *bootstrap = requestTask(@"https://spclient.wg.spotify.com/v1/bootstrap");
        require(canReplayCustomize(@"/v1/bootstrap") == NO,
                @"The customize gate never answers another endpoint");
        NSHTTPURLResponse *bootstrap304 = [[NSHTTPURLResponse alloc] initWithURL:bootstrap.current.URL
                                                                       statusCode:304 HTTPVersion:nil headerFields:nil];
        require(replayFor(bootstrap, bootstrap304, NULL) == nil,
                @"A bootstrap 304 is not synthesised from the customize cache");
        require(holds(bootstrap, [@"boot-original" dataUsingEncoding:NSUTF8StringEncoding]),
                @"A bootstrap body is still buffered");
        delegate.received = [NSMutableData data];
        complete(delegate, nil, bootstrap, nil, ^(NSError *error) {});
        require([delegate.received isEqual:[@"bootstrap" dataUsingEncoding:NSUTF8StringEncoding]],
                @"A bootstrap body still reaches its own transform");

        // Two customize refetches in flight at once: each task keeps its own buffer, so the one that
        // finishes first cannot deliver the other's bytes, nor be left with an empty buffer.
        started = [NSDate dateWithTimeIntervalSinceNow:-60];
        @synchronized (cacheLock) { cachedCustomize = nil; }
        SGRequestTask *firstInFlight = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        SGRequestTask *secondInFlight = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(holds(firstInFlight, [@"alpha" dataUsingEncoding:NSUTF8StringEncoding]),
                @"The first concurrent customize body is buffered");
        require(holds(secondInFlight, [@"beta" dataUsingEncoding:NSUTF8StringEncoding]),
                @"The second concurrent customize body is buffered");
        customizeTransformFails = YES;
        delegate.received = [NSMutableData data];
        complete(delegate, nil, firstInFlight, nil, ^(NSError *error) {});
        require([delegate.received isEqual:[@"alpha" dataUsingEncoding:NSUTF8StringEncoding]],
                @"The first completion delivers only its own bytes");
        customizeTransformFails = NO;
        delegate.received = [NSMutableData data];
        complete(delegate, nil, secondInFlight, nil, ^(NSError *error) {});
        require([delegate.received isEqual:json(@"premium")],
                @"The second completion still has its own buffered body");

        puts("PASS: unsupported and aggregate task passthrough; media resume; login/refetch rules; ad blocking; cold-cache config passthrough and rewrite on arrival; 304 replay of a validated body only; concurrent customize tasks keep separate buffers; a non-customize endpoint still uses its own transform");
    }
    return 0;
}
