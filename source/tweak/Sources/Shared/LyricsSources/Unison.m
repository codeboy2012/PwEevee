#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://unison.boidu.dev/lyrics";
static const NSInteger kLengthSlack = 4;

SGLyricsAsk SGUnisonAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    if (!query.title.length || !query.artist.length) {
        SGLog(@"unison: nothing to search with for %@", query.trackID);
        done(nil);
        return;
    }
    // song and artist alone answer with the highest scored match; album and duration narrow it.
    NSMutableDictionary<NSString *, NSString *> *search = [NSMutableDictionary dictionaryWithDictionary:@{
        @"song": query.title,
        @"artist": query.artist,
    }];
    if (query.seconds > 0) search[@"duration"] = @(query.seconds).stringValue;
    if (query.album.length) search[@"album"] = query.album;
    SGLyricsGetJSON(SGLyricsURL(kAPI, search), nil, ^(id root) {
        id data = [root isKindOfClass:NSDictionary.class] ? root[@"data"] : nil;
        if (![data isKindOfClass:NSDictionary.class]) {
            SGLog(@"unison: no lyrics for %@ by %@", query.title, query.artist);
            done(nil);
            return;
        }
        // Unison also keeps LRC and plain text, which carry nothing the other sources do not.
        if (![data[@"format"] isEqual:@"ttml"]) {
            SGLog(@"unison: %@ by %@ is %@, not ttml", query.title, query.artist, data[@"format"]);
            done(nil);
            return;
        }
        NSInteger length = SGLyricsNumber(data[@"duration"]);
        if (query.seconds > 0 && length > 0 && labs(length - query.seconds) > kLengthSlack) {
            SGLog(@"unison: %@ is %lds against the track's %lds", query.title, (long)length, (long)query.seconds);
            done(nil);
            return;
        }
        NSArray<SGKaraokeLine *> *lines = SGTTMLLines(data[@"lyrics"]);
        if (!lines) {
            done(nil);
            return;
        }
        SGLyricsResult *result = [SGLyricsResult new];
        result.synced = YES;
        result.wordTimed = [data[@"syncType"] isEqual:@"richsync"];
        result.karaokeLines = lines;
        NSArray<NSNumber *> *starts;
        NSArray<NSString *> *texts;
        SGLyricsPageLines(lines, &starts, &texts);
        result.starts = starts;
        result.texts = texts;
        SGLog(@"unison: %@ by %@ has %lu %@ lines (%@ confidence)", query.title, query.artist,
              (unsigned long)lines.count, result.wordTimed ? @"word timed" : @"line timed", data[@"confidence"]);
        done(result);
    });
};
