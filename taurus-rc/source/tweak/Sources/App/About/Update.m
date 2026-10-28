// The repo's GitHub Releases, so a build that is already on someone's phone can tell them a newer
// one exists and show what changed in it. Release Please cuts every release from the commits, so
// the release body is the changelog itself: a "### Features" or "### Fixes" heading over a line per
// commit, each ending in a link to it. One request brings the last twenty releases rather than only
// the newest, which is what lets the Updates page show every version between this build and the
// newest one. Asked a few seconds after Spotify comes up (UpdateNotice.m) and when Mod Settings
// opens, at most once every six hours either way, and on demand from the page. This tree asks
// GitHub directly; the site-forwarded check of the SpoTi.pw-lineage build is not part of the
// ported product, so the request goes nowhere else.
//
// Every release is sorted into a channel before anything is stored (SGUpdateChannels.h). The
// channel the user picked keeps its own answer and its own last-checked time, so what Stable
// heard can never pose as what Nightly should see, and switching channels refreshes the page's
// result: the check the switch fires answers for the new channel and the old channel's answer
// stays exactly where it was.
#import "Core/SGCore.h"
#import "About.h"
#import "SGUpdateChannels.h"

static NSString *const kGitHubURL = @"https://api.github.com/repos/codeboy2012/PwEevee/releases?per_page=20";
NSString *const SGUpdateCheckedNotification = @"spotifyglass.update.checked.notification";

static const NSTimeInterval kInterval = 6 * 60 * 60;

static NSString *stringOr(id value, NSString *fallback) {
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

static NSString *sg_failure;
static BOOL sg_running;

BOOL SGUpdateChecking(void)      { return sg_running; }
BOOL SGUpdateLastCheckFailed(void) { return sg_failure != nil; }

@implementation SGUpdateChange
@end

@implementation SGUpdateRelease
@end

#pragma mark - the changelog out of the release's markdown

// "[the text](https://…)" is left as its text, and what release-please writes around a scope --
// "**player:** …" -- loses its stars. Nothing else in a body of its is markup.
static NSString *plainText(NSString *markdown) {
    static NSRegularExpression *link;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]*)\\]\\([^)]*\\)" options:0 error:NULL];
    });
    NSString *text = [link stringByReplacingMatchesInString:markdown options:0
                                                      range:NSMakeRange(0, markdown.length) withTemplate:@"$1"];
    text = [text stringByReplacingOccurrencesOfString:@"**" withString:@""];
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// The commit a line ends with -- " ([4b63f35](https://github.com/…/commit/4b63f35…))" -- taken off the
// text and kept as the line's link. A line written by hand has none and keeps all of itself.
static NSString *takeCommitURL(NSString **line) {
    static NSRegularExpression *trailer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        trailer = [NSRegularExpression regularExpressionWithPattern:@"\\s*\\(\\[[0-9a-f]{6,}\\]\\(([^)]+)\\)\\)\\s*$" options:0 error:NULL];
    });
    NSString *text = *line;
    NSTextCheckingResult *match = [trailer firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    *line = [text substringToIndex:match.range.location];
    return [text substringWithRange:[match rangeAtIndex:1]];
}

// A release body into its lines: "### Features" names what follows, "* …" is a line of it, and a
// line that wraps onto the next one is joined back together. Anything else -- the "## [0.19.0](…)"
// heading release-please leads with, blank lines -- is dropped, the version being known already.
static NSArray<SGUpdateChange *> *changesIn(NSString *body) {
    NSMutableArray<SGUpdateChange *> *changes = [NSMutableArray array];
    NSString *kind = @"Changes";
    SGUpdateChange *open = nil;
    for (NSString *raw in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line hasPrefix:@"###"]) {
            kind = plainText([line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]]);
            open = nil;
        } else if ([line hasPrefix:@"* "] || [line hasPrefix:@"- "]) {
            NSString *text = [line substringFromIndex:2];
            NSString *url = takeCommitURL(&text);
            text = plainText(text);
            if (!text.length) { open = nil; continue; }
            open = [SGUpdateChange new];
            open.kind = kind;
            open.text = text;
            open.url = url;
            [changes addObject:open];
        } else if (line.length && ![line hasPrefix:@"#"] && open) {
            // A line too long for one, wrapped by whoever edited the release by hand.
            NSString *text = line;
            NSString *url = takeCommitURL(&text);
            open.text = [open.text stringByAppendingFormat:@" %@", plainText(text)];
            if (url) open.url = url;
        } else {
            open = nil;
        }
    }
    return changes;
}

#pragma mark - what the upgrade from the pre-channel builds left behind

// The pre-channel builds cached the newest release under one flat key (pweevee.update.latest,
// itself migrated from the pre-rename spotifyglass.update.taurus.latest). One-time migration: a
// release cached there, still readable, moves into the Stable channel's own list -- the channel a
// pre-channel install was effectively listening to -- and the flat keys are removed only after the
// new storage read back the same version. An install that has channels already leaves it alone.
static void migrateLegacyCachedRelease(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (SGUpdateChannelCheckedAt(SGUpdateChannelStable) > 0) {
        // Channels have answered before; nothing under the flat keys may speak for Stable now.
        // Stale flat keys are swept so Reset all settings and the disk agree on what is stored.
        [store removeObjectForKey:@"pweevee.update.latest"];
        [store removeObjectForKey:@"spotifyglass.update.taurus.latest"];
        return;
    }
    NSDictionary *legacy = [store dictionaryForKey:@"pweevee.update.latest"]
                        ?: [store dictionaryForKey:@"spotifyglass.update.taurus.latest"];
    if (![legacy isKindOfClass:NSDictionary.class]) return;
    NSString *version = stringOr(legacy[@"version"], nil);
    if (!version.length) return;
    NSArray *entry = @[ @{
        @"version": version,
        @"notes": stringOr(legacy[@"notes"], @""),
        @"date": stringOr(legacy[@"date"], @""),
        @"url": stringOr(legacy[@"url"], @""),
    } ];
    SGUpdateChannelStoreList(SGUpdateChannelStable, entry);
    if ([SGUpdateChannelStoredList(SGUpdateChannelStable) isEqualToArray:entry]) {
        [store removeObjectForKey:@"pweevee.update.latest"];
        [store removeObjectForKey:@"spotifyglass.update.taurus.latest"];
        SGUpdateChannelNoteChecked(SGUpdateChannelStable);
        SGLog(@"update: the release cached before the channels moved into Stable");
    }
}

#pragma mark - what the last check left

NSArray<SGUpdateRelease *> *SGUpdateReleases(void) {
    migrateLegacyCachedRelease();
    NSArray *stored = SGUpdateChannelStoredList(SGUpdateChannelNow());
    NSMutableArray<SGUpdateRelease *> *releases = [NSMutableArray array];
    for (id entry in stored) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *version = stringOr(entry[@"version"], nil);
        if (!version.length) continue;
        SGUpdateRelease *release = [SGUpdateRelease new];
        release.version = version;
        release.date = stringOr(entry[@"date"], @"");
        release.url = stringOr(entry[@"url"], nil);
        release.changes = changesIn(stringOr(entry[@"notes"], @""));
        [releases addObject:release];
    }
    return releases;
}

SGUpdateRelease *SGUpdateNewestRelease(void) {
    return SGUpdateReleases().firstObject;
}

BOOL SGUpdateIsNewer(NSString *version) {
    return version.length && SGVersionCompare(version, @(SG_VERSION)) == NSOrderedDescending;
}

NSString *SGUpdateVersion(void) {
    NSString *newest = SGUpdateNewestRelease().version;
    return SGUpdateIsNewer(newest) ? newest : nil;
}

// What the Updates row shows on the right; the page's own ticker reads it while the page is open,
// so the async check lands in the cell without anything having to be told about it. A channel the
// last check heard from but that carried no eligible release says so plainly, rather than posing
// as "up to date" -- there was no release to be up to date against. And when the channel's newest
// is older than this build (the standing case after a Stable-to-edge-channel move), that is said
// too: nothing older is presented as an update here.
NSString *SGUpdateStatus(void) {
    if (sg_running) return @"checking…";
    if (sg_failure) return sg_failure;
    SGUpdateChannel channel = SGUpdateChannelNow();
    if (SGUpdateChannelCheckedAt(channel) <= 0) return @"not checked";
    NSString *latest = SGUpdateVersion();
    if (latest) return [latest stringByAppendingString:@" is out"];
    NSArray *stored = SGUpdateReleases();
    if (!stored.count) return @"no releases on this channel yet";
    NSString *newest = SGUpdateNewestRelease().version;
    if (newest && SGVersionCompare(newest, @(SG_VERSION)) == NSOrderedAscending)
        return @"no newer release on this channel";
    return @"up to date";
}

#pragma mark - the check

// The reply is bucketed into the three channels by SGUpdateChannels; whatever shape the
// reply is, a nil buckets means nothing is stored and the failure the status names is kept
// for the row to read.
static void ask(NSString *url, void (^done)(NSDictionary *buckets, NSInteger status, NSError *error)) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 10;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    NSURLSessionDataTask *task = [[NSURLSession sessionWithConfiguration:configuration]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        done(status == 200 ? SGUpdateChannelsFromReleasesJSON(data) : nil, status, error);
    }];
    [task resume];
}

void SGCheckForUpdate(BOOL force) {
    SGUpdateChannel channel = SGUpdateChannelNow();
    NSTimeInterval last = SGUpdateChannelCheckedAt(channel);
    if (sg_running) return;
    if (!force && last > 0 && NSDate.date.timeIntervalSince1970 - last < kInterval) return;

    migrateLegacyCachedRelease();
    sg_running = YES;
    sg_failure = nil;
    void (^finish)(NSDictionary *, NSInteger, NSError *) = ^(NSDictionary *buckets, NSInteger status, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_running = NO;
            if (!buckets) {
                // Unauthenticated GitHub allows sixty requests an hour per address; a phone behind a
                // carrier NAT can be told to wait, and that is worth reading apart from a dead network.
                sg_failure = status == 403 || status == 429 ? @"asked too often" : @"check failed";
                SGLog(@"update check failed: HTTP %ld, %@", (long)status,
                      error.localizedDescription ?: @"no release in the reply");
            } else {
                // Every channel's answer goes home under its own key, whatever channel the user is
                // on while the reply lands: a channel nobody was watching still gets its result,
                // and the one being watched never borrows another's.
                for (NSUInteger c = 0; c < 3; c++) {
                    SGUpdateChannel stored = (SGUpdateChannel)c;
                    NSArray *bucket = buckets[SGUpdateChannelBucketNames()[c]];
                    SGUpdateChannelStoreList(stored, bucket);
                    // The check completed, so every channel counts as heard from even
                    // when its bucket came back empty: an empty channel says so instead
                    // of sitting at "not checked" forever.
                    SGUpdateChannelNoteChecked(stored);
                }
                id newestOnChannel = [buckets[SGUpdateChannelBucketNames()[(NSUInteger)channel]] firstObject];
                SGLog(@"update check: the newest for %@ is %@, this build is %s",
                      SGUpdateChannelTitle(channel),
                      newestOnChannel[@"version"] ?: @"none", SG_VERSION);
            }
            [NSNotificationCenter.defaultCenter postNotificationName:SGUpdateCheckedNotification object:nil];
        });
    };
    SGLog(@"update check: asking PwEevee GitHub Releases, channel %@", SGUpdateChannelTitle(channel));
    ask(kGitHubURL, finish);
}
