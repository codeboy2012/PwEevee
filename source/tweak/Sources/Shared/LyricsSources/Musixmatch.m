// Lyrics from Musixmatch. It is the catalog Spotify licenses, and for part of it Musixmatch also
// has the time of every word (richsync), which Spotify never sends. The token is an anonymous one
// asked for as Musixmatch's iOS app, so Musixmatch learns the track's id and nothing of the Spotify
// account. It is the one source that matches by Spotify's own track id, so it never has to guess at
// a title, and what it learns about the track is passed to the sources asked after it. A local file has
// no id, so for one the matcher searches by its names and length (q_track, q_artist, q_album, q_duration).
#import "Core/SGCore.h"
#import "LyricsSources.h"
#import "Shared/LocalFiles/LocalFiles.h"

static NSString *const kAPI = @"https://apic-appmobile.musixmatch.com/ws/1.1/";
static NSString *const kAppID = @"mac-ios-v2.0";
static NSString *const kTokenKey = @"spotifyglass.musixmatch.token";
static const NSTimeInterval kTimeout = 5;
// After Musixmatch refused a token, typically with a captcha, it is not asked again for this long.
static const NSTimeInterval kTokenPause = 600;
// A pause this long between two richsync lines gets a ♪ line, so Spotify's page does not hold the last one.
static const NSInteger kBreakMs = 3000;
static const NSUInteger kKeptTracks = 40;

// Main queue only. NSNull is kept for a track Musixmatch has nothing for.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;
static NSMutableArray<void (^)(NSString *)> *sg_tokenWaiting;
static NSDate *sg_tokenRefused;
// Musixmatch's own id of a track, by Spotify's, as the lyrics call matched it; translations go by it.
static NSMutableDictionary<NSString *, NSString *> *sg_commontracks;
// The community translations, by track and language: those answered, and those still being asked for.
static NSMutableDictionary<NSString *, NSDictionary *> *sg_translations;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_translationsWaiting;

static void setUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_kept = [NSMutableDictionary dictionary];
        sg_waiting = [NSMutableDictionary dictionary];
        sg_tokenWaiting = [NSMutableArray array];
        sg_commontracks = [NSMutableDictionary dictionary];
        sg_translations = [NSMutableDictionary dictionary];
        sg_translationsWaiting = [NSMutableDictionary dictionary];
    });
}

// Keys contain dots ("track.richsync.get"), so the path is split on slashes.
static id dig(id value, NSString *path) {
    for (NSString *key in [path componentsSeparatedByString:@"/"]) {
        if (![value isKindOfClass:NSDictionary.class]) return nil;
        value = value[key];
    }
    return value;
}

static BOOL truthy(id value) {
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

static NSInteger msOf(id seconds) {
    return [seconds respondsToSelector:@selector(doubleValue)] ? (NSInteger)llround([seconds doubleValue] * 1000) : 0;
}

static id jsonOf(id text) {
    if ([text isKindOfClass:NSString.class]) text = [text dataUsingEncoding:NSUTF8StringEncoding];
    return [text isKindOfClass:NSData.class] ? [NSJSONSerialization JSONObjectWithData:text options:0 error:nil] : nil;
}

// token.get answers a request without the app's headers with a captcha.
static NSURLRequest *requestFor(NSString *method, NSDictionary<NSString *, NSString *> *query) {
    NSURLComponents *url = [NSURLComponents componentsWithString:[kAPI stringByAppendingString:method]];
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray arrayWithObjects:
        [NSURLQueryItem queryItemWithName:@"format" value:@"json"],
        [NSURLQueryItem queryItemWithName:@"app_id" value:kAppID], nil];
    [query enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:name value:value]];
    }];
    url.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kTimeout];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"10.1.1" forHTTPHeaderField:@"x-mxm-app-version"];
    [request setValue:@"Musixmatch/2025120901 CFNetwork/3860.300.31 Darwin/25.2.0" forHTTPHeaderField:@"X-User-Agent"];
    return request;
}

static void call(NSString *method, NSDictionary<NSString *, NSString *> *query, void (^done)(NSDictionary *message)) {
    [[NSURLSession.sharedSession dataTaskWithRequest:requestFor(method, query) completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        SGLyricsNoteReply(response, error);
        id message = dig(jsonOf(data), @"message");
        if (error || !message) SGLog(@"musixmatch: %@ failed: status %ld, error %@", method, (long)[(NSHTTPURLResponse *)response statusCode], error);
        dispatch_async(dispatch_get_main_queue(), ^{ done([message isKindOfClass:NSDictionary.class] ? message : nil); });
    }] resume];
}

static void withToken(void (^use)(NSString *token)) {
    NSString *token = [NSUserDefaults.standardUserDefaults stringForKey:kTokenKey];
    if (token.length) {
        use(token);
        return;
    }
    if (sg_tokenRefused && -sg_tokenRefused.timeIntervalSinceNow < kTokenPause) {
        use(nil);
        return;
    }
    [sg_tokenWaiting addObject:use];
    if (sg_tokenWaiting.count > 1) return;
    call(@"token.get", @{}, ^(NSDictionary *message) {
        id fresh = dig(message, @"body/user_token");
        BOOL usable = [fresh isKindOfClass:NSString.class] && [fresh length] && ![fresh isEqualToString:@"UpgradeRequired"];
        SGLog(@"musixmatch: token %@ (status %@, hint %@)", usable ? @"received" : @"refused", dig(message, @"header/status_code"), dig(message, @"header/hint"));
        if (usable) [NSUserDefaults.standardUserDefaults setObject:fresh forKey:kTokenKey];
        else sg_tokenRefused = NSDate.date;
        NSArray<void (^)(NSString *)> *waiting = [sg_tokenWaiting copy];
        [sg_tokenWaiting removeAllObjects];
        for (void (^waiter)(NSString *) in waiting) waiter(usable ? fresh : nil);
    });
}

#pragma mark - the three shapes Musixmatch has lyrics in

// [{ "ts": 27.16, "te": 28.25, "x": "I've been tryna call", "l": [{ "c": "I've", "o": 0.03 }, { "c": " ", "o": 0.41 }, …] }]
// o is from the line's start. A space entry ends the word before it; a word can come in more than
// one entry ("Milion", "+", ","), so everything between two spaces is one word.
static SGKaraokeLine *richsyncLine(NSDictionary *entry, NSInteger start, NSInteger end) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    BOOL open = NO;     // the word last added may still take further entries
    BOOL spaced = YES;  // a space has gone by since the last word, so the next one is not joined
    id parts = entry[@"l"];
    for (NSDictionary *part in [parts isKindOfClass:NSArray.class] ? parts : @[]) {
        id text = dig(part, @"c");
        if (![text isKindOfClass:NSString.class]) continue;
        NSInteger at = start + msOf(part[@"o"]);
        NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        SGKaraokeWord *last = words.lastObject;
        if (!trimmed.length) {
            last.end = MAX(at, last.start);
            open = NO;
            spaced = YES;
            continue;
        }
        if (open && !SGKaraokeUnspacedScript(trimmed)) {
            last.text = [last.text stringByAppendingString:trimmed];
            continue;
        }
        // A syllable of an unspaced script stands as a word of its own. Musixmatch times each one,
        // but sends no space to end it, so running them together is what left a Japanese or Chinese
        // line lighting up whole instead of sweeping.
        last.end = MAX(at, last.start);
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = trimmed;
        word.start = at;
        word.end = MAX(end, at);
        word.joined = !spaced;
        [words addObject:word];
        open = !SGKaraokeUnspacedScript(trimmed);
        spaced = NO;
    }
    if (!words.count) return nil;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = start;
    line.end = MAX(end, words.lastObject.end);
    return line;
}

static SGLyricsResult *fromRichsync(id body) {
    if (![body isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSMutableArray<SGKaraokeLine *> *karaoke = [NSMutableArray array];
    for (NSDictionary *entry in body) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        SGKaraokeLine *line = richsyncLine(entry, msOf(entry[@"ts"]), msOf(entry[@"te"]));
        if (!line) continue;
        if (karaoke.count && line.start - karaoke.lastObject.end >= kBreakMs) {
            [starts addObject:@(karaoke.lastObject.end)];
            [texts addObject:@"♪"];
        }
        id text = entry[@"x"];
        [starts addObject:@(line.start)];
        [texts addObject:[text isKindOfClass:NSString.class] ? text : SGKaraokeLineText(line)];
        [karaoke addObject:line];
    }
    if (!karaoke.count) return nil;
    [starts addObject:@(karaoke.lastObject.end)];
    [texts addObject:@""];
    SGLyricsResult *lyrics = [SGLyricsResult new];
    lyrics.synced = lyrics.wordTimed = YES;
    lyrics.starts = starts;
    lyrics.texts = texts;
    lyrics.karaokeLines = karaoke;
    return lyrics;
}

// [{ "text": "Yeah, yeah", "time": { "total": 3.32 } }, …, { "text": "", "time": { "total": 241.15 } }]
// An empty text is a break, and the last one marks the end.
static SGLyricsResult *fromSubtitles(id body) {
    if (![body isKindOfClass:NSArray.class] || ![body count]) return nil;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    NSArray *lines = body;
    for (NSUInteger i = 0; i < lines.count; i++) {
        id text = dig(lines[i], @"text");
        BOOL last = i + 1 == lines.count;
        if (![text isKindOfClass:NSString.class]) text = @"";
        [starts addObject:@(msOf(dig(lines[i], @"time/total")))];
        [texts addObject:last ? @"" : ([text length] ? text : @"♪")];
    }
    SGLyricsResult *lyrics = [SGLyricsResult new];
    lyrics.synced = YES;
    lyrics.starts = starts;
    lyrics.texts = texts;
    lyrics.karaokeLines = SGKaraokeEstimatedLines(starts, texts);
    return lyrics.karaokeLines ? lyrics : nil;
}

static SGLyricsResult *fromPlain(id body) {
    if (![body isKindOfClass:NSString.class] || ![body length]) return nil;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
        [starts addObject:@0];
        [texts addObject:line.length ? line : @"♪"];
    }
    SGLyricsResult *lyrics = [SGLyricsResult new];
    lyrics.starts = starts;
    lyrics.texts = texts;
    lyrics.karaokeLines = SGKaraokeStaticLines(texts);
    return lyrics;
}

// macro.subtitles.get runs the matcher and every lookup in one call; the best shape it has wins.
static SGLyricsResult *fromCalls(NSDictionary *calls) {
    if (truthy(dig(calls, @"matcher.track.get/message/body/track/instrumental"))) return nil;
    id richsync = dig(calls, @"track.richsync.get/message/body/richsync");
    SGLyricsResult *lyrics = nil;
    if (richsync && !truthy(dig(richsync, @"restricted"))) lyrics = fromRichsync(jsonOf(dig(richsync, @"richsync_body")));
    if (lyrics) return lyrics;
    id list = dig(calls, @"track.subtitles.get/message/body/subtitle_list");
    id subtitle = [list isKindOfClass:NSArray.class] && [list count] ? dig([list firstObject], @"subtitle") : nil;
    if (subtitle && !truthy(dig(subtitle, @"restricted"))) lyrics = fromSubtitles(jsonOf(dig(subtitle, @"subtitle_body")));
    if (lyrics) return lyrics;
    id plain = dig(calls, @"track.lyrics.get/message/body/lyrics");
    return plain && !truthy(dig(plain, @"restricted")) ? fromPlain(dig(plain, @"lyrics_body")) : nil;
}

#pragma mark - asking

static void noteCommontrack(NSString *trackID, id commontrack) {
    if ([commontrack respondsToSelector:@selector(stringValue)]) commontrack = [commontrack stringValue];
    if (![commontrack isKindOfClass:NSString.class] || ![commontrack length] || [commontrack isEqualToString:@"0"]) return;
    if (sg_commontracks.count >= kKeptTracks) [sg_commontracks removeAllObjects];
    sg_commontracks[trackID] = commontrack;
}

static void finish(NSString *trackID, SGLyricsResult *lyrics, BOOL answered) {
    if (answered) {
        if (sg_kept.count >= kKeptTracks) [sg_kept removeAllObjects];
        sg_kept[trackID] = lyrics ?: NSNull.null;
    }
    NSArray *waiting = sg_waiting[trackID];
    [sg_waiting removeObjectForKey:trackID];
    for (void (^done)(SGLyricsResult *) in waiting) done(lyrics);
}

// What the matcher settled on, kept even when Musixmatch may show no lyrics: the sources asked after
// this one search by name, and this is the best name anyone has.
static SGLyricsResult *withTrack(SGLyricsResult *lyrics, id track) {
    if (![track isKindOfClass:NSDictionary.class]) return lyrics;
    SGLyricsResult *result = lyrics ?: [SGLyricsResult new];
    id title = track[@"track_name"], artist = track[@"artist_name"], album = track[@"album_name"];
    if ([title isKindOfClass:NSString.class]) result.title = title;
    if ([artist isKindOfClass:NSString.class]) result.artist = artist;
    if ([album isKindOfClass:NSString.class]) result.album = album;
    result.seconds = SGLyricsNumber(track[@"track_length"]);
    result.instrumental = truthy(track[@"instrumental"]);
    return result;
}

// `match` is what the matcher goes by: Spotify's id, or a local file's names.
static void ask(NSString *trackID, NSDictionary<NSString *, NSString *> *match, BOOL renewToken) {
    withToken(^(NSString *token) {
        if (!token) {
            finish(trackID, nil, NO);
            return;
        }
        NSMutableDictionary<NSString *, NSString *> *query = [@{
            @"usertoken": token,
            @"namespace": @"lyrics_richsynched",
            @"subtitle_format": @"mxm",
            @"optional_calls": @"track.richsync",
            @"richsync_compact_type": @"words",
        } mutableCopy];
        [query addEntriesFromDictionary:match];
        call(@"macro.subtitles.get", query, ^(NSDictionary *message) {
            NSInteger status = [dig(message, @"header/status_code") integerValue];
            if (status == 401 && renewToken) {
                SGLog(@"musixmatch: token no longer accepted (hint %@), asking for a new one", dig(message, @"header/hint"));
                [NSUserDefaults.standardUserDefaults removeObjectForKey:kTokenKey];
                ask(trackID, match, NO);
                return;
            }
            id calls = dig(message, @"body/macro_calls");
            if (status != 200 || ![calls isKindOfClass:NSDictionary.class]) {
                finish(trackID, nil, NO);
                return;
            }
            noteCommontrack(trackID, dig(calls, @"matcher.track.get/message/body/track/commontrack_id"));
            SGLyricsResult *lyrics = fromCalls(calls);
            SGLog(@"musixmatch: %@ has %@", trackID, !lyrics ? @"no lyrics it may show"
                  : lyrics.wordTimed ? [NSString stringWithFormat:@"%lu word timed lines", (unsigned long)lyrics.karaokeLines.count]
                  : lyrics.synced ? [NSString stringWithFormat:@"%lu line timed lines", (unsigned long)lyrics.karaokeLines.count]
                  : [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)lyrics.texts.count]);
            finish(trackID, withTrack(lyrics, dig(calls, @"matcher.track.get/message/body/track")), YES);
        });
    });
}

// What the matcher goes by: Spotify's id, or for a local file, which has none, its names and length to
// search by. nil when there is nothing to go by.
static NSDictionary<NSString *, NSString *> *matchFor(NSString *trackID, NSString *title, NSString *artist, NSString *album, NSInteger seconds) {
    if (!trackID.length) return nil;
    if (!SGLocalFileIs(trackID)) return @{@"track_spotify_id": trackID};
    if (!title.length) return nil;
    NSMutableDictionary<NSString *, NSString *> *match = [NSMutableDictionary dictionaryWithObject:title forKey:@"q_track"];
    match[@"q_artist"] = artist;
    match[@"q_album"] = album;
    if (seconds > 0) match[@"q_duration"] = [NSString stringWithFormat:@"%ld", (long)seconds];
    return match;
}

SGLyricsAsk SGMusixmatchAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *lyrics)) {
    setUp();
    NSString *trackID = query.trackID;
    NSDictionary<NSString *, NSString *> *match = matchFor(trackID, query.title, query.artist, query.album, query.seconds);
    if (!match) {
        done(nil);
        return;
    }
    id kept = sg_kept[trackID];
    if (kept) {
        done(kept == NSNull.null ? nil : kept);
        return;
    }
    NSMutableArray *waiting = sg_waiting[trackID];
    if (waiting) {
        [waiting addObject:[done copy]];
        return;
    }
    sg_waiting[trackID] = [NSMutableArray arrayWithObject:[done copy]];
    ask(trackID, match, YES);
};

#pragma mark - translations

// The community's translations of a track's lines, by the line's text as SGMusixmatchLineKey makes it.
// Musixmatch pages them; a page that brings no line not seen yet ends the paging, whatever the API
// does with the page number.
static const NSInteger kTranslationPage = 100, kTranslationPages = 5;

// Musixmatch's codes for the Lyrics page's languages where they differ, tried in turn until one has
// lines. Asked on 5 October 2026: zh-Hans and zh-Hant had no lines where zh (Simplified) and z1
// (Traditional) had, and Norwegian is kept under nb on some tracks and no on others.
static NSArray<NSString *> *codesFor(NSString *language) {
    NSDictionary<NSString *, NSArray<NSString *> *> *codes = @{@"zh-Hans": @[@"zh"], @"zh-Hant": @[@"z1"], @"nb": @[@"nb", @"no"]};
    return codes[language] ?: @[language];
}

// What a page's status says about the answer: lost on the way or to a busy server is asked again later.
static BOOL lostStatus(NSInteger status) {
    return status == 0 || status == 429 || status >= 500;
}

NSString *SGMusixmatchLineKey(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *folded = [text stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in [folded componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]) {
        if (word.length) [words addObject:word];
    }
    return [words componentsJoinedByString:@" "];
}

// done gets Musixmatch's status for the paging: 200 once it is over, the first other one where it stopped,
// 0 for a page that never came.
static void translationPage(NSString *token, NSString *commontrack, NSString *code, NSInteger page,
                            NSMutableDictionary<NSString *, NSString *> *found, void (^done)(NSInteger status)) {
    call(@"crowd.track.translations.get", @{
        @"usertoken": token, @"commontrack_id": commontrack, @"selected_language": code,
        @"comment_format": @"text", @"part": @"user", @"translation_fields_set": @"minimal",
        @"page": @(page).stringValue, @"page_size": @(kTranslationPage).stringValue,
    }, ^(NSDictionary *message) {
        NSInteger status = [dig(message, @"header/status_code") integerValue];
        if (status != 200) {
            done(status);
            return;
        }
        id list = dig(message, @"body/translations_list");
        NSUInteger before = found.count;
        for (id entry in [list isKindOfClass:NSArray.class] ? list : @[]) {
            id snippet = dig(entry, @"translation/snippet"), text = dig(entry, @"translation/description");
            if (![snippet isKindOfClass:NSString.class] || ![text isKindOfClass:NSString.class] || ![text length]) continue;
            NSString *key = SGMusixmatchLineKey(snippet);
            if (key.length && ![text isEqualToString:snippet]) found[key] = text;
        }
        BOOL more = found.count > before && [list count] >= 20 && page < kTranslationPages;
        if (more) translationPage(token, commontrack, code, page + 1, found, done);
        else done(200);
    });
}

// Each of the language's codes in turn, until one has lines.
static void translationsIn(NSString *token, NSString *commontrack, NSArray<NSString *> *codes,
                           NSMutableDictionary<NSString *, NSString *> *found, void (^done)(NSInteger status)) {
    translationPage(token, commontrack, codes.firstObject, 1, found, ^(NSInteger status) {
        if (status == 200 && !found.count && codes.count > 1) {
            translationsIn(token, commontrack, [codes subarrayWithRange:NSMakeRange(1, codes.count - 1)], found, done);
            return;
        }
        done(status);
    });
}

// done gets what was found, and whether it is Musixmatch's whole answer rather than one cut short.
static void askTranslations(NSString *trackID, NSString *language, BOOL renewToken,
                            void (^done)(NSDictionary<NSString *, NSString *> *found, BOOL answered)) {
    // A local file is matched by the names it goes by, its key's edit over its tags, as its lyrics were.
    NSDictionary *local = SGLocalFileInfo(trackID);
    NSDictionary<NSString *, NSString *> *match = matchFor(trackID, local[@"title"], local[@"artist"], local[@"album"], [local[@"seconds"] integerValue]);
    if (!match) {
        done(nil, YES);
        return;
    }
    withToken(^(NSString *token) {
        if (!token) {
            done(nil, NO);
            return;
        }
        // As ask() does: a token Musixmatch no longer takes is dropped and a new one asked for, once.
        void (^ended)(NSInteger, NSDictionary *) = ^(NSInteger status, NSDictionary *found) {
            if (status == 401 && renewToken) {
                SGLog(@"musixmatch: token no longer accepted for translations, asking for a new one");
                [NSUserDefaults.standardUserDefaults removeObjectForKey:kTokenKey];
                askTranslations(trackID, language, NO, done);
                return;
            }
            done(found, !lostStatus(status) && status != 401);
        };
        void (^translate)(NSString *) = ^(NSString *commontrack) {
            NSMutableDictionary<NSString *, NSString *> *found = [NSMutableDictionary dictionary];
            translationsIn(token, commontrack, codesFor(language), found, ^(NSInteger status) { ended(status, found); });
        };
        // The lyrics call has usually matched the track already; the matcher is asked only when it has not.
        NSString *known = sg_commontracks[trackID];
        if (known) {
            translate(known);
            return;
        }
        NSMutableDictionary<NSString *, NSString *> *query = [match mutableCopy];
        query[@"usertoken"] = token;
        call(@"matcher.track.get", query, ^(NSDictionary *message) {
            NSInteger status = [dig(message, @"header/status_code") integerValue];
            noteCommontrack(trackID, dig(message, @"body/track/commontrack_id"));
            NSString *commontrack = status == 200 ? sg_commontracks[trackID] : nil;
            if (commontrack) translate(commontrack);
            else ended(status, nil);
        });
    });
}

void SGMusixmatchTranslations(NSString *trackID, NSString *language, void (^done)(NSDictionary<NSString *, NSString *> *byLine)) {
    setUp();
    if (!trackID.length || !language.length) {
        done(nil);
        return;
    }
    NSString *memo = [NSString stringWithFormat:@"%@|%@", trackID, language];
    NSDictionary *known = sg_translations[memo];
    if (known) {
        done(known.count ? known : nil);
        return;
    }
    NSMutableArray *waiting = sg_translationsWaiting[memo];
    if (waiting) {
        [waiting addObject:[done copy]];
        return;
    }
    sg_translationsWaiting[memo] = [NSMutableArray arrayWithObject:[done copy]];
    askTranslations(trackID, language, YES, ^(NSDictionary<NSString *, NSString *> *found, BOOL answered) {
        // Only a whole answer is kept: a page lost on the way leaves the track to be asked again.
        if (answered) {
            if (sg_translations.count >= kKeptTracks) [sg_translations removeAllObjects];
            sg_translations[memo] = [found copy] ?: @{};
        }
        SGLog(@"musixmatch: %lu translated lines in %@ for %@%@", (unsigned long)found.count, language, trackID,
              answered ? @"" : @", cut short; not kept, so the next lines ask again");
        NSArray *waiters = sg_translationsWaiting[memo];
        [sg_translationsWaiting removeObjectForKey:memo];
        for (void (^waiter)(NSDictionary *) in waiters) waiter(found.count ? found : nil);
    });
}

NSArray<SGKaraokeLine *> *SGMusixmatchTranslatedLines(NSArray<SGKaraokeLine *> *lines, NSDictionary<NSString *, NSString *> *byLine) {
    NSMutableArray<SGKaraokeLine *> *translated = nil;
    for (NSUInteger i = 0; i < lines.count; i++) {
        SGKaraokeLine *line = lines[i];
        NSString *text = byLine[SGMusixmatchLineKey(SGKaraokeLineText(line))];
        if (!text.length || line.translation.length) continue;
        if (!translated) translated = [lines mutableCopy];
        SGKaraokeLine *copy = [line copy];
        copy.translation = text;
        translated[i] = copy;
    }
    return translated;
}
