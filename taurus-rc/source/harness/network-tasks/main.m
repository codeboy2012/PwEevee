#import "Core/SGCore.h"
#import "Core/SGURLSession.h"
#import "Shared/AdBlock/AdBlock.h"

BOOL SGFlag(NSString *key, BOOL fallback) { return YES; }
void SGLogMessage(NSString *message) {}
void SGRequireClasses(NSArray *names) {}
void SGAdBlockSawOne(NSString *label) {}
void SGAdBlockCountOne(NSString *label) {}
NSData *SGPatchBootstrap(NSData *body) { return [@"bootstrap" dataUsingEncoding:NSUTF8StringEncoding]; }
NSData *SGPatchCustomize(NSData *body) { return [@"premium" dataUsingEncoding:NSUTF8StringEncoding]; }
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
@end
@implementation SGDelegate
- (instancetype)init { if ((self = [super init])) _received = [NSMutableData data]; return self; }
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    [self.received appendData:data];
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

        SGRequestTask *refetch = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        [refetch resume];
        require(refetch.cancels == 1 && refetch.resumes == 0, @"Premium refetch protection still cancels after login");
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

        started = NSDate.date;
        SGRequestTask *customize = requestTask(@"https://spclient.wg.spotify.com/v1/customize");
        require(holds(customize, [@"original" dataUsingEncoding:NSUTF8StringEncoding]), @"Config body is buffered");
        complete(delegate, nil, customize, nil, ^(NSError *error) {});
        require([delegate.received isEqual:json(@"premium")], @"Buffered config still reaches the Premium transform");
        NSHTTPURLResponse *notModified = [[NSHTTPURLResponse alloc] initWithURL:customize.current.URL statusCode:304 HTTPVersion:nil headerFields:nil];
        require(replayFor(customize, notModified).statusCode == 200, @"Cached Premium config still replays for 304");
        puts("PASS: unsupported and aggregate task passthrough; media resume; login/refetch rules; ad blocking; config rewrite and 304 replay");
    }
    return 0;
}
