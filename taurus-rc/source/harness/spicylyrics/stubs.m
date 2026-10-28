// Just enough of the mod around SpicyLyrics.m for it to run on the Mac: the lyrics value types as
// they really are, and the two things the source reaches out through — the borrowed Spotify token
// and the POST — replaced by ones the test drives.
#import "LyricsSources.h"
#import "Shared/Lyrics/Lyrics.h"

@implementation SGKaraokeWord @end
@implementation SGKaraokeLine @end
@implementation SGLyricsResult @end
@implementation SGLyricsQuery @end
@implementation SGLyricsProvider @end

NSString *sg_token = @"Bearer test-token";
NSString *SGKaraokeSpotifyAuthorization(void) { return sg_token; }

// What the last request carried, and what the next one is answered with.
NSURL *sg_sentTo;
NSDictionary *sg_sentHeaders, *sg_sentBody;
NSUInteger sg_sentCount;
id sg_reply;
NSInteger sg_notedFailures;

void SGLyricsNoteReply(NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    if (error || status == 429 || status >= 500) sg_notedFailures++;
}

void SGLyricsPostJSON(NSURL *url, NSDictionary<NSString *, NSString *> *headers, id body, void (^done)(id root)) {
    sg_sentTo = url;
    sg_sentHeaders = headers;
    sg_sentBody = body;
    sg_sentCount++;
    // The real one refuses a body it cannot write, so hold this one to the same bar.
    NSCAssert([NSJSONSerialization isValidJSONObject:body], @"the body is not JSON");
    done(sg_reply);
}

// The page lines are LyricsSources.m's own, proven work; here they only need to be countable.
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    NSMutableArray<NSNumber *> *at = [NSMutableArray array];
    NSMutableArray<NSString *> *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}

// The estimator is Shared/Lyrics' own; what matters here is what the source hands it.
NSArray<NSNumber *> *sg_estimatedStarts;
NSArray<NSString *> *sg_estimatedTexts;

NSArray<SGKaraokeLine *> *SGKaraokeEstimatedLines(NSArray<NSNumber *> *starts, NSArray<NSString *> *texts) {
    sg_estimatedStarts = starts;
    sg_estimatedTexts = texts;
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < texts.count; i++) {
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = texts[i];
        word.start = starts[i].integerValue;
        SGKaraokeLine *line = [SGKaraokeLine new];
        line.words = @[word];
        line.start = word.start;
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

NSString *SGKaraokeLineText(SGKaraokeLine *line) {
    NSMutableString *text = [NSMutableString string];
    for (SGKaraokeWord *word in line.words) {
        if (text.length && !word.joined) [text appendString:@" "];
        [text appendString:word.text];
    }
    return text;
}
