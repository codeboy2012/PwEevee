#import "Core/SGCore.h"
#import "Shared/Haptics/Haptics.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://lyrics-api.binimum.org/";
static NSString *const kByISRC = @"https://lrc.red/s/%@.ttml";
static const NSInteger kLengthSlack = 4;

// The best of what the search found: word timing wins over line timing, then the closest length.
static NSDictionary *bestOf(id results, NSInteger seconds) {
    NSDictionary *best = nil;
    BOOL bestWordTimed = NO;
    NSInteger bestOff = NSIntegerMax;
    for (NSDictionary *found in [results isKindOfClass:NSArray.class] ? results : @[]) {
        if (![found isKindOfClass:NSDictionary.class] || ![found[@"lyricsUrl"] isKindOfClass:NSString.class]) continue;
        NSInteger length = SGLyricsNumber(found[@"duration"]);
        NSInteger off = seconds > 0 && length > 0 ? labs(length - seconds) : 0;
        if (off > kLengthSlack) continue;
        BOOL wordTimed = [found[@"timing_type"] isEqual:@"word"];
        if (best && !(wordTimed && !bestWordTimed) && (bestWordTimed != wordTimed || off >= bestOff)) continue;
        best = found;
        bestWordTimed = wordTimed;
        bestOff = off;
    }
    return best;
}

// The result for a TTML, nil when it has no lines the page can show.
static SGLyricsResult *resultFor(NSString *ttml, BOOL wordTimed) {
    NSArray<SGKaraokeLine *> *lines = SGTTMLLines(ttml);
    if (!lines) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    result.synced = YES;
    result.wordTimed = wordTimed;
    result.karaokeLines = lines;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(lines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    return result;
}

static void search(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length || !query.artist.length) {
        SGLog(@"binilyrics: nothing to search with for %@", query.trackID);
        done(nil);
        return;
    }
    NSMutableDictionary<NSString *, NSString *> *search = [NSMutableDictionary dictionaryWithDictionary:@{
        @"track": query.title,
        @"artist": query.artist,
    }];
    if (query.seconds > 0) search[@"duration"] = @(query.seconds).stringValue;
    if (query.album.length) search[@"album"] = query.album;
    SGLyricsGetJSON(SGLyricsURL(kAPI, search), nil, ^(id root) {
        NSDictionary *found = bestOf([root isKindOfClass:NSDictionary.class] ? root[@"results"] : nil, query.seconds);
        if (!found) {
            SGLog(@"binilyrics: nothing within %lds of %@ by %@", (long)kLengthSlack, query.title, query.artist);
            done(nil);
            return;
        }
        SGLyricsGetText([NSURL URLWithString:found[@"lyricsUrl"]], ^(NSString *ttml) {
            SGLyricsResult *result = resultFor(ttml, [found[@"timing_type"] isEqual:@"word"]);
            if (!result) SGLog(@"binilyrics: %@ gave nothing the page could show", found[@"lyricsUrl"]);
            else SGLog(@"binilyrics: %@ by %@ has %lu %@ lines", query.title, query.artist,
                       (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"line timed");
            done(result);
        });
    });
}

SGLyricsAsk SGBiniLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (query.trackID.length != 22) {
        search(query, done);
        return;
    }
    SGSpotifyISRC([@"spotify:track:" stringByAppendingString:query.trackID], 1, ^(NSString *isrc) {
        if (!isrc) {
            search(query, done);
            return;
        }
        SGLyricsGetText([NSURL URLWithString:[NSString stringWithFormat:kByISRC, isrc]], ^(NSString *ttml) {
            SGLyricsResult *result = resultFor(ttml, [ttml containsString:@"timing=\"Word\""]);
            if (!result) {
                SGLog(@"binilyrics: nothing filed under %@, searched by name", isrc);
                search(query, done);
                return;
            }
            SGLog(@"binilyrics: %@ (%@) has %lu %@ lines", query.title ?: query.trackID, isrc,
                  (unsigned long)result.karaokeLines.count, result.wordTimed ? @"word timed" : @"line timed");
            done(result);
        });
    });
};
