#import "Core/SGCore.h"
#import "Privacy.h"

typedef struct { const char *host, *path, *label; } SGBlockRule;

// host matched on the domain and its subdomains, path as a substring; no path means the whole host.
static const SGBlockRule kRules[] = {
    {"app-measurement.com",               NULL,                      "Firebase"},
    {"crashlytics.com",                   NULL,                      "Crashlytics"},
    {"facebook.com",                      "/activities",             "Facebook"},
    {"ep1.facebook.com",                  NULL,                      "Facebook"},
    {"ep2.facebook.com",                  NULL,                      "Facebook"},
    {"branch.io",                         "/v1/event",               "Branch"},
    {"scorecardresearch.com",             NULL,                      "Comscore"},
    {"segment.io",                        NULL,                      "Segment"},
    {"zqtk.net",                          NULL,                      "Segment"},
    {"google-analytics.com",              NULL,                      "Google"},
    {"googleadservices.com",              NULL,                      "Google"},
    {"doubleclick.net",                   NULL,                      "Google"},
};
static const size_t kRuleCount = sizeof(kRules) / sizeof(kRules[0]);

static NSString *const kCounts = @"spotifyglass.privacy.counts";
static NSMutableDictionary<NSString *, NSNumber *> *sg_counts;
static BOOL sg_unsaved;   // counts counted since the counts were last written

@interface SGBlockProtocol : NSURLProtocol
@end

static NSMutableDictionary<NSString *, NSNumber *> *countsLocked(void) {
    if (!sg_counts) {
        sg_counts = [[NSUserDefaults.standardUserDefaults dictionaryForKey:kCounts] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSSet<NSString *> *current = [NSSet setWithArray:SGBlockedLabels()];
        for (NSString *label in sg_counts.allKeys) {
            if (![current containsObject:label]) sg_counts[label] = nil;
        }
    }
    return sg_counts;
}

static void countOne(NSString *label) {
    @synchronized (SGBlockProtocol.class) {
        NSMutableDictionary<NSString *, NSNumber *> *counts = countsLocked();
        counts[label] = @(counts[label].unsignedIntegerValue + 1);
        // Counting runs on the CFNetwork protocol thread: writing here synchronously deadlocks the app
        // (a defaults write posts its observer relays on this thread while the main thread waits on it;
        // hang 2026-10-23 15:24). The counts keep in memory and the leaving observer writes them once.
        sg_unsaved = YES;
    }
}

// Persists the protocol-hook counts as the app leaves the screen, so they write on the main thread once
// instead of synchronously from every blocked request (see countOne).
__attribute__((constructor)) static void saveBlockedOnLeaving(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        @synchronized (SGBlockProtocol.class) {
            if (!sg_unsaved) return;
            [NSUserDefaults.standardUserDefaults setObject:countsLocked() forKey:kCounts];
            sg_unsaved = NO;
        }
    }];
}

static NSString *labelFor(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (!host) return nil;
    NSString *path = url.path ?: @"";
    for (size_t i = 0; i < kRuleCount; i++) {
        NSString *domain = @(kRules[i].host);
        if (![host isEqualToString:domain] && ![host hasSuffix:[@"." stringByAppendingString:domain]]) continue;
        if (kRules[i].path && ![path containsString:@(kRules[i].path)]) continue;
        return @(kRules[i].label);
    }
    return nil;
}

NSArray<NSString *> *SGBlockedLabels(void) {
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (size_t i = 0; i < kRuleCount; i++) {
        NSString *label = @(kRules[i].label);
        if (![labels containsObject:label]) [labels addObject:label];
    }
    return labels;
}

NSUInteger SGBlockedCount(NSString *label) {
    @synchronized (SGBlockProtocol.class) {
        NSDictionary<NSString *, NSNumber *> *counts = countsLocked();
        if (label) return counts[label].unsignedIntegerValue;
        NSUInteger total = 0;
        for (NSNumber *count in counts.allValues) total += count.unsignedIntegerValue;
        return total;
    }
}

void SGResetBlocked(void) {
    @synchronized (SGBlockProtocol.class) {
        sg_counts = [NSMutableDictionary dictionary];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCounts];
    }
}

@implementation SGBlockProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    return labelFor(request.URL) != nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSString *label = labelFor(self.request.URL);
    if (label) countOne(label);
    // 204 rather than an error: the sender takes it for delivered and queues no retry behind it.
    NSHTTPURLResponse *answer = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:204 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:answer cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
}

@end

static NSURLSessionConfiguration *carryingProtocol(NSURLSessionConfiguration *configuration) {
    if (!configuration || [configuration.protocolClasses containsObject:SGBlockProtocol.class]) return configuration;
    NSMutableArray *classes = [configuration.protocolClasses mutableCopy] ?: [NSMutableArray array];
    [classes insertObject:SGBlockProtocol.class atIndex:0];
    configuration.protocolClasses = classes;
    return configuration;
}

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    return carryingProtocol(configuration);
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    return carryingProtocol(configuration);
}

%end

%ctor {
    if (SGEnabled(SGKeyBlockTelemetry)) {
        [NSURLProtocol registerClass:SGBlockProtocol.class];
        %init;
    }
}
