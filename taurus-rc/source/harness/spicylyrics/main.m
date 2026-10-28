// Runs Shared/LyricsSources/SpicyLyrics.m for real against replies packed by Spicy Lyrics' own
// packer (../pack.ts), so the decoder and the line building are checked against the shape the
// server actually sends rather than against my reading of it.
#import "LyricsSources.h"
#import "Shared/Lyrics/Lyrics.h"

extern NSString *sg_token;
extern NSURL *sg_sentTo;
extern NSDictionary *sg_sentHeaders, *sg_sentBody;
extern NSUInteger sg_sentCount;
extern id sg_reply;
extern NSInteger sg_notedFailures;
extern NSArray<NSNumber *> *sg_estimatedStarts;
extern NSArray<NSString *> *sg_estimatedTexts;

static int failures;

static void check(BOOL ok, NSString *what) {
    printf("  %s %s\n", ok ? "ok  " : "FAIL", what.UTF8String);
    if (!ok) failures++;
}

static void checkEqual(id got, id want, NSString *what) {
    check([got isEqual:want], [NSString stringWithFormat:@"%@ (got %@, want %@)", what, got, want]);
}

// The one reply shape the API uses: a 200 envelope with the query's own status inside it.
static id envelope(NSInteger status, id data) {
    return @{@"queries": @[@{@"operation": @"lyrics", @"operationId": @"0",
                             @"result": @{@"httpStatus": @(status), @"format": @"json", @"data": data ?: NSNull.null}}]};
}

static SGLyricsResult *ask(NSString *trackID) {
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = trackID;
    __block SGLyricsResult *answer = nil;
    __block BOOL called = NO;
    SGSpicyLyricsAsk(query, ^(SGLyricsResult *result) {
        answer = result;
        called = YES;
    });
    check(called, @"the source answered");
    return answer;
}

int main(void) {
    @autoreleasepool {
        NSData *raw = [NSData dataWithContentsOfFile:@"fixtures.json"];
        NSDictionary *packed = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
        NSCAssert(packed.count, @"no fixtures; run pack.ts first");

        printf("syllable lyrics\n");
        sg_reply = envelope(200, packed[@"syllable"]);
        SGLyricsResult *result = ask(@"0VjIjW4GlUZAMYd2vXMi3b");
        check(result != nil, @"there is a result");
        check(result.synced && result.wordTimed, @"synced and word timed");
        checkEqual(@(result.karaokeLines.count), @2, @"two lines");
        SGKaraokeLine *first = result.karaokeLines.firstObject;
        checkEqual(@(first.start), @1500, @"the line starts at its own StartTime, in ms");
        checkEqual(@(first.end), @4250, @"the line ends at its own EndTime, in ms");
        checkEqual(@(first.words.count), @3, @"three syllables are three words");
        checkEqual(@(first.words[0].start), @1500, @"the first syllable's start");
        checkEqual(@(first.words[1].end), @2400, @"a fractional second lands on the right ms");
        check(!first.words[0].joined, @"the first word of a line is never joined");
        check(first.words[1].joined, @"a syllable after IsPartOfWord is laid flush");
        check(!first.words[2].joined, @"a syllable after a whole word is not");
        checkEqual(@(first.align), @(SGKaraokeAlignLeading), @"the first voice leads");
        check(first.backing != nil, @"the line has its backing vocals");
        checkEqual(SGKaraokeLineText(first.backing), @"echo", @"the backing words");
        checkEqual(@(first.backing.start), @3000, @"the backing starts with its own first word");
        SGKaraokeLine *second = result.karaokeLines[1];
        checkEqual(@(second.align), @(SGKaraokeAlignTrailing), @"OppositeAligned puts the line on the far side");
        check(second.backing == nil, @"a line with no Background has no backing line");
        checkEqual(@(result.texts.count), @2, @"the page gets a line for each");

        printf("the request itself\n");
        checkEqual(sg_sentTo.absoluteString, @"https://api.spicylyrics.org/query", @"the address");
        checkEqual(sg_sentHeaders[@"SpicyLyrics-WebAuth"], sg_token, @"the token goes in the header it names");
        checkEqual(sg_sentHeaders[@"X-mode"], @"2", @"the packed shape is asked for");
        check([sg_sentHeaders[@"SpicyLyrics-Version"] length] > 0, @"a client version is sent");
        // The server reads the identity Spotify's desktop client's Chromium puts on every request,
        // and answers a caller without it with plain text instead of syllables.
        checkEqual(sg_sentHeaders[@"Origin"], @"https://xpui.app.spotify.com", @"the desktop client's origin");
        check([sg_sentHeaders[@"User-Agent"] containsString:@"Chrome/"], @"a Chromium user agent");
        check([sg_sentHeaders[@"sec-ch-ua-platform"] length] > 0, @"the client hints go with it");
        check(sg_sentHeaders[@"Accept-Encoding"] == nil, @"encoding is left to URLSession, which can decode what it asks for");
        NSDictionary *sent = [sg_sentBody[@"queries"] firstObject];
        checkEqual(sent[@"operation"], @"lyrics", @"the operation");
        checkEqual(sent[@"variables"][@"id"], @"0VjIjW4GlUZAMYd2vXMi3b", @"the track id, not a name");
        checkEqual(sent[@"variables"][@"auth"], @"SpicyLyrics-WebAuth", @"the header the token is in is named");

        printf("line timed lyrics\n");
        sg_reply = envelope(200, packed[@"line"]);
        result = ask(@"track2");
        check(result.synced && !result.wordTimed, @"synced but not word timed");
        checkEqual(sg_estimatedStarts, (@[@2000, @4500]), @"the estimator gets the line starts in ms");
        checkEqual(sg_estimatedTexts, (@[@"delta foxtrot", @"golf hotel"]), @"and their text");

        printf("static lyrics\n");
        sg_reply = envelope(200, packed[@"static"]);
        result = ask(@"track3");
        check(!result.synced, @"not synced");
        checkEqual(@(result.karaokeLines.count), @0, @"nothing to sweep");
        checkEqual(result.texts, (@[@"india", @"♪", @"juliett"]), @"the words, a break for the empty line");
        checkEqual(result.starts, (@[@0, @0, @0]), @"every start is zero");

        printf("what goes wrong\n");
        NSInteger before = sg_notedFailures;
        sg_reply = envelope(503, nil);
        check(ask(@"track4") == nil, @"a queued track has no lyrics yet");
        checkEqual(@(sg_notedFailures), @(before + 1), @"and the walk is told, so it is not kept as having none");
        before = sg_notedFailures;
        sg_reply = envelope(404, nil);
        check(ask(@"track5") == nil, @"a track it does not have");
        checkEqual(@(sg_notedFailures), @(before), @"which is an answer, not a failure");
        sg_reply = envelope(200, @[@[@"Type"], @[@0, @0, @0]]);
        check(ask(@"track6") == nil, @"a stream that does not hold together");
        sg_reply = envelope(200, @[packed[@"static"][0], [packed[@"static"][1] arrayByAddingObject:@0]]);
        check(ask(@"track7") == nil, @"a document with something tacked on the end");
        sg_reply = @{@"queries": @[]};
        check(ask(@"track8") == nil, @"an envelope with no answer in it");

        printf("with no token to borrow\n");
        NSUInteger sentBefore = sg_sentCount;
        sg_token = nil;
        sg_reply = envelope(200, packed[@"syllable"]);
        check(ask(@"track9") == nil, @"nothing is answered");
        checkEqual(@(sg_sentCount), @(sentBefore), @"and nothing is sent");

        printf("\n%s\n", failures ? [NSString stringWithFormat:@"%d failed", failures].UTF8String : "all passed");
        return failures ? 1 : 0;
    }
}
