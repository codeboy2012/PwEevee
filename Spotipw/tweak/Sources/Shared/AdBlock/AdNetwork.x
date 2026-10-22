// Spotify's responses on their way in, through the URLSession delegates it reads them by:
// SPTDataLoaderService and HttpClientURLSession for the app's own requests. With Spoof Premium on,
// the bootstrap and customize bodies are rewritten by Premium.m before the client sees them, the
// endpoints the server would use to log the account out are answered as if they succeeded, and past
// the first thirty seconds the re-fetches that could bring the real state back are canceled before
// they leave. This file carries only the premium spoof: the ad-request blocking, the feed strips and
// the C++ core's ad path stay in upstream Spot.pw/Taurus with the other AdBlock switches.
#import "Core/SGCore.h"
#import "AdBlock.h"

static BOOL premium;
static NSDate *started;
static NSObject *cacheLock;
static NSData *cachedCustomize;   // the last rewritten customize body, for a 304 and the re-fetches
static char kBufferKey, kServedKey, kPassKey;

typedef NS_ENUM(NSInteger, SGNet) { SGNetPass, SGNetBlock, SGNetPatch };

static NSTimeInterval elapsed(void) {
    return -started.timeIntervalSinceNow;
}

static BOOL has(NSString *text, NSString *needle) {
    return [text containsString:needle];
}

static BOOL isBootstrap(NSString *path) { return has(path, @"v1/bootstrap"); }
static BOOL isCustomize(NSString *path) { return has(path, @"v1/customize"); }

static BOOL isLogout(NSString *path) {
    return has(path, @"logout") || has(path, @"sign-out") || has(path, @"session/purge") || has(path, @"token/revoke")
        || has(path, @"auth/expire") || (has(path, @"melody") && has(path, @"check")) || has(path, @"product-state")
        || (has(path, @"license") && has(path, @"check")) || has(path, @"deletetoken");
}

// The first thirty seconds are a fresh login's: signup/public and customize are part of it, and
// answering them broke first launch.
static BOOL isRefetch(NSString *path) {
    return has(path, @"signup/public") || has(path, @"select-ondemand-set") || has(path, @"trials-facade/start-trial")
        || has(path, @"premium-marketing/upselloffer") || (has(path, @"pendragon") && has(path, @"fetchmessagelist"))
        || has(path, @"pushka-tokens") || has(path, @"apresolve") || has(path, @"pses/screenconfig") || isCustomize(path);
}

static SGNet classify(NSURL *url) {
    NSString *path = url.path.lowercaseString ?: @"";
    if (premium && isLogout(path)) return SGNetBlock;
    if (premium && elapsed() > 30 && isRefetch(path)) return SGNetBlock;
    if (premium && (isBootstrap(path) || isCustomize(path))) return SGNetPatch;
    return SGNetPass;
}

static NSData *cached(void) {
    @synchronized (cacheLock) { return cachedCustomize; }
}

static NSData *json(NSString *text) {
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

// The body a blocked request is answered with: what its reader parses for, so that nothing is
// retried and no logout path taken.
static NSData *blockedReply(NSString *path) {
    if (has(path, @"signup/public")) return json(@"{\"status\":1,\"country\":\"US\",\"is_country_launched\":true}");
    if (has(path, @"trials-facade")) return json(@"{\"result\":\"NOT_ELIGIBLE\"}");
    if (has(path, @"premium-marketing") || has(path, @"pses/screenconfig")) return json(@"{}");
    if (isLogout(path) || has(path, @"apresolve")) return json(@"{\"status\":\"OK\"}");
    if (isCustomize(path) && cached()) return cached();
    return [NSData data];
}

static NSData *patched(NSURL *url, NSData *body) {
    NSString *path = url.path.lowercaseString ?: @"";
    NSData *result = isBootstrap(path) ? SGPatchBootstrap(body) : SGPatchCustomize(body);
    if (!result) {
        SGLog(@"could not rewrite %@, passed through", path);
        return nil;
    }
    if (isCustomize(path)) {
        @synchronized (cacheLock) { cachedCustomize = result; }
    }
    SGLog(@"rewrote %@, %lu -> %lu bytes", path, (unsigned long)body.length, (unsigned long)result.length);
    return result;
}

#pragma mark - the delegate's three calls

// Data handed to the delegate by the mod goes through its hooked didReceiveData like Spotify's own,
// with the pass mark on the task so the hook lets it by.
static void deliver(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSData *data) {
    objc_setAssociatedObject(task, &kPassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [delegate URLSession:session dataTask:(NSURLSessionDataTask *)task didReceiveData:data];
    objc_setAssociatedObject(task, &kPassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A customize the server says has not changed, answered with the rewritten one from last time.
static NSHTTPURLResponse *replayFor(NSURLSessionTask *task, NSURLResponse *response) {
    if (!premium || ![response isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)response).statusCode != 304) return nil;
    NSURL *url = task.currentRequest.URL;
    if (!isCustomize(url.path.lowercaseString ?: @"") || !cached()) return nil;
    objc_setAssociatedObject(task, &kServedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/2.0" headerFields:@{}];
}

// YES when the data is not the delegate's to see yet: dropped for a blocked request, kept back for
// one whose reply is rewritten when it finishes.
static BOOL holds(NSURLSessionTask *task, NSData *data) {
    if (objc_getAssociatedObject(task, &kPassKey)) return NO;
    switch (classify(task.currentRequest.URL)) {
        case SGNetBlock:
            return YES;
        case SGNetPatch: {
            NSMutableData *buffer = objc_getAssociatedObject(task, &kBufferKey);
            if (!buffer) objc_setAssociatedObject(task, &kBufferKey, (buffer = [NSMutableData data]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [buffer appendData:data];
            return YES;
        }
        default:
            return NO;
    }
}

static void complete(id<NSURLSessionDataDelegate> delegate, NSURLSession *session, NSURLSessionTask *task, NSError *error, void (^finish)(NSError *)) {
    NSURL *url = task.currentRequest.URL;
    NSString *path = url.path.lowercaseString ?: @"";
    NSMutableData *buffer = objc_getAssociatedObject(task, &kBufferKey);
    objc_setAssociatedObject(task, &kBufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (objc_getAssociatedObject(task, &kServedKey)) {
        finish(nil);
        return;
    }
    switch (classify(url)) {
        case SGNetBlock:
            SGLog(@"answered %@ empty", path);
            deliver(delegate, session, task, blockedReply(path));
            finish(nil);
            return;
        case SGNetPatch:
            if (error) {
                finish(error);
                return;
            }
            // Nothing to rewrite: a 304, or a body of no bytes. The delegate is told of a body either
            // way, since a completion with none hangs some readers.
            if (!buffer) {
                deliver(delegate, session, task, (isCustomize(path) ? cached() : nil) ?: [NSData data]);
                finish(nil);
                return;
            }
            deliver(delegate, session, task, patched(url, buffer) ?: buffer);
            finish(nil);
            return;
        default:
            finish(error);
    }
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    NSHTTPURLResponse *replay = replayFor(task, response);
    %orig(session, task, replay ?: response, handler);
    if (replay) deliver((id)self, session, task, cached());
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holds(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    complete((id)self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))handler {
    NSHTTPURLResponse *replay = replayFor(task, response);
    %orig(session, task, replay ?: response, handler);
    if (replay) deliver((id)self, session, task, cached());
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (!holds(task, data)) %orig;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    complete((id)self, session, task, error, ^(NSError *passed) { %orig(session, task, passed); });
}
%end

#pragma mark - before a request leaves

// The re-fetches that could put the real product state back, or drop the push token, use sessions
// of their own that the delegate hooks do not see; they are canceled at the task. login5 and the
// Google token stay: blocking those was a crash loop.
%group Premium
%hook NSURLSessionTask
- (void)resume {
    NSURL *url = self.currentRequest.URL ?: self.originalRequest.URL;
    NSString *host = url.host.lowercaseString ?: @"", *path = url.path.lowercaseString ?: @"";
    BOOL spotify = has(host, @"spotify") || has(host, @"spclient");
    if (spotify && elapsed() > 30 && (has(path, @"deletetoken") || has(path, @"signup/public") || has(path, @"pses/screenconfig")
                                      || isCustomize(path) || has(host, @"apresolve"))) {
        SGLog(@"canceled %@%@ before it left", host, path);
        [self cancel];
        return;
    }
    %orig;
}
%end
%end

// The config comes back 304 with no body when the app holds a copy of it and asks whether that is still
// current, and a copy taken while Spoof Premium was off is the server's own: the mod then has nothing to
// rewrite, and the account stays free until the server changes the config (device 2026-09-21). So the two
// go out without the question, and the server always answers in full.
static NSURLRequest *unconditional(NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString ?: @"", *path = request.URL.path.lowercaseString ?: @"";
    if (!(has(host, @"spotify") || has(host, @"spclient")) || !(isBootstrap(path) || isCustomize(path))) return nil;
    if (![request valueForHTTPHeaderField:@"If-None-Match"] && ![request valueForHTTPHeaderField:@"If-Modified-Since"]) return nil;
    NSMutableURLRequest *plain = [request mutableCopy];
    [plain setValue:nil forHTTPHeaderField:@"If-None-Match"];
    [plain setValue:nil forHTTPHeaderField:@"If-Modified-Since"];
    plain.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    SGLog(@"premium: %@ sent without its validators", path);
    return plain;
}

%group PremiumRequests
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(unconditional(request) ?: request);
}
%end
%end

// The sessions Spotify makes are __NSURLSessionLocal; hooked as well only when that class answers
// dataTaskWithRequest: itself, since a hook on an inherited method would sit on NSURLSession's twice.
%group PremiumLocalRequests
%hook __NSURLSessionLocal
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(unconditional(request) ?: request);
}
%end
%end

%ctor {
    // The exclusivity resolver runs before the flags are read, so the hooks see the resolved state
    // and never a stored both-on pair.
    SGPremiumResolveConflict();
    premium = SGFlag(SGKeyFakePremium, YES);
    if (!premium) return;
    started = NSDate.date;
    cacheLock = [NSObject new];
    %init;
    %init(Premium);
    %init(PremiumRequests);
    SEL selector = @selector(dataTaskWithRequest:);
    Class local = objc_getClass("__NSURLSessionLocal");
    Method own = local ? class_getInstanceMethod(local, selector) : NULL;
    if (own && own != class_getInstanceMethod(NSURLSession.class, selector)) %init(PremiumLocalRequests);
    SGRequireClasses(@[@"SPTDataLoaderService", @"_TtC26Connectivity_HttpClientKit20HttpClientURLSession"]);
}
