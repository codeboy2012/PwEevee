// Spicy Lyrics, through its Developer Platform (developers.spicylyrics.org) on the user's own key.
// One request by Spotify's track id answers with the best sync there is: a community one made by
// hand, else Apple Music's or Spotify's. Syllable syncs time every syllable and carry duets and
// backing vocals. The key lives in the Keychain, not in the settings, so a settings export never
// carries it; without one the source answers nothing.
//
// The API's terms ask for the provider to be named wherever its lyrics show, and for a community
// sync's maker and uploader to be credited and linked with it: the credit is marked required, so it
// shows under the lyrics whether Show source is on or not, and a tap on it opens their pages.
//
// An app ships its key to every user, so it takes a publishable key (sl_pk_) with the No origin header
// entry allowed, as the API's docs ask; a secret key is for a server. Answers and misses are kept per
// track for the session, a rate limit is waited out, and a refused key is not tried again for a while.
#import <Security/Security.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://api.spicylyrics.org/v1/lyrics/";
static NSString *const kDashboard = @"https://developers.spicylyrics.org/dashboard";
#ifndef SG_VERSION
#define SG_VERSION "dev"
#endif
static NSString *const kAgent = @"PwEevee/" SG_VERSION " (Spotify for iOS lyrics, by track id)";
// A reply for this many tracks is kept; a rate limit is waited out for at most an hour, 60 s when the
// reply does not say; a refused key is tried again after ten minutes.
static const NSUInteger kKeptTracks = 100;
static const NSTimeInterval kMostWait = 3600, kDefaultWait = 60, kRefusedWait = 600;
static NSString *const kService = @"PwEevee.SpicyLyrics", *const kAccount = @"api-key";
// The keychain service the pre-rename builds stored their key under; read once to migrate.
static NSString *const kLegacyService = @"Taurus.SpicyLyrics";
NSString *const SGSpicyLyricsKey = @"spicylyrics";

#pragma mark - the key

static NSDictionary *keyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kService, (__bridge id)kSecAttrAccount: kAccount};
}

static NSDictionary *legacyQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: kLegacyService, (__bridge id)kSecAttrAccount: kAccount};
}

static NSString *keyIn(NSDictionary *query) {
    NSMutableDictionary *ask = [query mutableCopy];
    ask[(__bridge id)kSecReturnData] = @YES;
    ask[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef data = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)ask, &data) != errSecSuccess || !data) return nil;
    NSString *key = [[NSString alloc] initWithData:(__bridge_transfer NSData *)data encoding:NSUTF8StringEncoding];
    return key.length ? key : nil;
}

static void storeKey(NSString *key) {
    SecItemDelete((__bridge CFDictionaryRef)keyQuery());
    if (!key.length) return;
    NSMutableDictionary *item = [keyQuery() mutableCopy];
    item[(__bridge id)kSecValueData] = [key dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status != errSecSuccess) SGLog(@"spicy lyrics: the key could not be kept (%d)", (int)status);
}

// One-time migration: a key kept under the pre-rename service is copied across; the legacy item is
// deleted only after the new item read back the same value, so an upgrade keeps its key.
static NSString *storedKey(void) {
    NSString *key = keyIn(keyQuery());
    if (key) return key;
    NSString *legacy = keyIn(legacyQuery());
    if (!legacy) return nil;
    storeKey(legacy);
    NSString *migrated = keyIn(keyQuery());
    if ([migrated isEqualToString:legacy]) SecItemDelete((__bridge CFDictionaryRef)legacyQuery());
    SGLog(@"spicy lyrics: the key moved to its new keychain place");
    return migrated ?: legacy;
}

BOOL SGSpicyLyricsKeySet(void) {
    return storedKey() != nil;
}

#pragma mark - the response

static NSInteger ms(id seconds) {
    return [seconds respondsToSelector:@selector(doubleValue)] ? (NSInteger)llround([seconds doubleValue] * 1000) : 0;
}

static NSString *stringIn(NSDictionary *object, NSString *name) {
    id value = [object isKindOfClass:NSDictionary.class] ? object[name] : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSArray *arrayIn(NSDictionary *object, NSString *name) {
    id value = [object isKindOfClass:NSDictionary.class] ? object[name] : nil;
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

// A Lead or Background: its syllables as words, read from `field` (Text, or TransliteratedText for
// how they sound). IsPartOfWord says a syllable runs on into the next one, so the next is laid flush
// against it. The line is timed by the part's own start and end where it has them.
static SGKaraokeLine *syllableLine(NSDictionary *part, NSString *field) {
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    BOOL runsOn = NO;
    for (NSDictionary *syllable in arrayIn(part, @"Syllables")) {
        NSString *text = [stringIn(syllable, field) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) continue;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = text;
        word.start = ms(syllable[@"StartTime"]);
        word.end = MAX(ms(syllable[@"EndTime"]), word.start);
        word.joined = words.count && runsOn;
        [words addObject:word];
        runsOn = [syllable[@"IsPartOfWord"] boolValue];
    }
    if (!words.count) return nil;
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = part[@"StartTime"] ? ms(part[@"StartTime"]) : words.firstObject.start;
    line.end = MAX(part[@"EndTime"] ? ms(part[@"EndTime"]) : words.lastObject.end, line.start);
    return line;
}

// How the part sounds: its syllables' own spellings, timed with them, else the part's spelling
// estimated across the line.
static SGKaraokeLine *spokenLine(NSDictionary *part, NSString *spelt, SGKaraokeLine *line) {
    return SGLyricsPronunciation(syllableLine(part, @"TransliteratedText").words, spelt, line);
}

// The translation of the line and its backing, unless it reads the same as them. The API does not say
// what language a TranslatedText is in, so it is taken only while the Lyrics page asks for any. With a
// language chosen, the line is left without one for Musixmatch or Gemini to fill in that language, as an
// Apple Music translation in another language is left out (SGTTML.m).
static NSString *translationOf(NSString *translation, SGKaraokeLine *line) {
    if (!translation.length || SGLyricsTranslationLanguage()) return nil;
    NSString *said = SGKaraokeLineText(line);
    if (line.backing) said = [said stringByAppendingFormat:@" %@", SGKaraokeLineText(line.backing)];
    return [SGLyricsBareText(translation) isEqualToString:SGLyricsBareText(said)] ? nil : translation;
}

static NSArray<SGKaraokeLine *> *syllableLines(NSArray *content) {
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    for (NSDictionary *item in content) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *lead = item[@"Lead"];
        SGKaraokeLine *line = syllableLine(lead, @"Text");
        if (!line) continue;
        line.align = [item[@"OppositeAligned"] boolValue] ? SGKaraokeAlignTrailing : SGKaraokeAlignLeading;
        // A line can have several background phrases; the view has one backing line, so they share it,
        // and their translations join the lead's.
        NSMutableArray *backing = [NSMutableArray array];
        NSMutableArray<NSString *> *spelt = [NSMutableArray array], *translated = [NSMutableArray array];
        if (stringIn(lead, @"TranslatedText")) [translated addObject:stringIn(lead, @"TranslatedText")];
        for (NSDictionary *group in arrayIn(item, @"Background")) {
            [backing addObjectsFromArray:arrayIn(group, @"Syllables")];
            if (stringIn(group, @"TransliteratedText")) [spelt addObject:stringIn(group, @"TransliteratedText")];
            if (stringIn(group, @"TranslatedText")) [translated addObject:stringIn(group, @"TranslatedText")];
        }
        NSDictionary *background = @{@"Syllables": backing};
        line.backing = syllableLine(background, @"Text");
        line.backing.align = line.align;
        line.pronunciation = spokenLine(lead, stringIn(lead, @"TransliteratedText"), line);
        if (line.backing) line.backing.pronunciation = spokenLine(background, [spelt componentsJoinedByString:@" "], line.backing);
        line.translation = translationOf([translated componentsJoinedByString:@" "], line);
        [lines addObject:line];
    }
    return lines.count ? lines : nil;
}

static BOOL isBreak(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return !trimmed.length || [trimmed isEqualToString:@"♪"];
}

// Starts only; the words inside are estimated. A line that ends well before the next begins gets an
// empty line at its end, so the estimate does not stretch it over the pause.
static NSArray<SGKaraokeLine *> *lineLines(NSArray *content) {
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *item in content) {
        if (!isBreak(stringIn(item, @"Text"))) [kept addObject:item];
    }
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSUInteger i = 0; i < kept.count; i++) {
        [starts addObject:@(ms(kept[i][@"StartTime"]))];
        [texts addObject:kept[i][@"Text"]];
        NSInteger end = ms(kept[i][@"EndTime"]);
        if (end > 0 && i + 1 < kept.count && ms(kept[i + 1][@"StartTime"]) > end) {
            [starts addObject:@(end)];
            [texts addObject:@""];
        }
    }
    NSArray<SGKaraokeLine *> *lines = SGKaraokeEstimatedLines(starts, texts);
    // Breaks were left out of kept, so the lines and kept pair up one to one.
    for (NSUInteger i = 0; i < lines.count && i < kept.count; i++) {
        if ([kept[i][@"OppositeAligned"] boolValue]) lines[i].align = SGKaraokeAlignTrailing;
        lines[i].pronunciation = SGLyricsPronunciation(nil, stringIn(kept[i], @"TransliteratedText"), lines[i]);
        lines[i].translation = translationOf(stringIn(kept[i], @"TranslatedText"), lines[i]);
    }
    return lines;
}

// The lines, each with its translation, and the text for Spotify's page: an empty row between two
// lines is a ♪ there, as a stanza break.
static NSArray<SGKaraokeLine *> *staticLines(NSArray *rows, NSArray<NSString *> **pageTexts) {
    NSMutableArray<NSString *> *texts = [NSMutableArray array], *page = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *row in rows) {
        NSString *text = stringIn(row, @"Text");
        if (isBreak(text)) {
            if (page.count && ![page.lastObject isEqualToString:@"♪"]) [page addObject:@"♪"];
            continue;
        }
        [texts addObject:text];
        [page addObject:text];
        [kept addObject:row];
    }
    if ([page.lastObject isEqualToString:@"♪"]) [page removeLastObject];
    *pageTexts = page;
    NSArray<SGKaraokeLine *> *lines = SGKaraokeStaticLines(texts);
    for (NSUInteger i = 0; i < lines.count && i < kept.count; i++) lines[i].translation = translationOf(stringIn(kept[i], @"TranslatedText"), lines[i]);
    return lines;
}

// What the credit reads, and the pages it links to. A community sync names the people who made it,
// each linked where the API gives an address; a catalog's is named as the provider it is, reached
// through Spicy Lyrics.
static NSString *creditFor(NSDictionary *body, NSArray<SGLyricsLink *> **links) {
    *links = nil;
    NSString *source = stringIn(body, @"source");
    if ([source isEqualToString:@"apple_music"]) return @"Apple Music via Spicy Lyrics";
    if ([source isEqualToString:@"spotify"]) return @"Spotify via Spicy Lyrics";
    if (![source isEqualToString:@"spicy_lyrics"]) return @"Spicy Lyrics, source unknown";
    NSDictionary *people = [body[@"UploadAttribution"] isKindOfClass:NSDictionary.class] ? body[@"UploadAttribution"] : nil;
    NSDictionary *makerInfo = people[@"Maker"], *uploaderInfo = people[@"Uploader"];
    NSString *maker = stringIn(makerInfo, @"username"), *uploader = stringIn(uploaderInfo, @"username");
    NSMutableArray<SGLyricsLink *> *found = [NSMutableArray array];
    for (NSArray *person in @[@[@"Uploader", uploaderInfo ?: @{}], @[@"Maker", makerInfo ?: @{}]]) {
        NSString *name = stringIn(person[1], @"username");
        NSURL *url = [NSURL URLWithString:stringIn(person[1], @"url") ?: @""];
        NSString *scheme = url.scheme.lowercaseString;
        if (!name || !url.host.length || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) continue;
        if ([[found valueForKey:@"url"] containsObject:url]) continue;   // one person both made and uploaded it
        SGLyricsLink *link = [SGLyricsLink new];
        link.title = [NSString stringWithFormat:@"%@: %@", person[0], name];
        link.url = url;
        [found addObject:link];
    }
    *links = found.count ? found : nil;
    if (maker && uploader && ![maker isEqualToString:uploader]) {
        return [NSString stringWithFormat:@"Spicy Lyrics, synced by %@, uploaded by %@", maker, uploader];
    }
    if (maker ?: uploader) return [NSString stringWithFormat:@"Spicy Lyrics, synced by %@", maker ?: uploader];
    return @"Spicy Lyrics";
}

SGLyricsResult *SGSpicyLyricsResult(id root) {
    NSDictionary *body = [root isKindOfClass:NSDictionary.class] ? root[@"Body"] : nil;
    if (![body isKindOfClass:NSDictionary.class]) return nil;
    NSString *type = stringIn(body, @"Type");
    NSArray<NSString *> *pageTexts = nil;
    NSArray<SGKaraokeLine *> *lines = [type isEqualToString:@"Syllable"] ? syllableLines(arrayIn(body, @"Content"))
        : [type isEqualToString:@"Line"] ? lineLines(arrayIn(body, @"Content"))
        : [type isEqualToString:@"Static"] ? staticLines(arrayIn(body, @"Lines"), &pageTexts)
        : nil;
    if (!lines.count) return nil;
    SGLyricsResult *result = [SGLyricsResult new];
    NSArray<SGLyricsLink *> *links;
    result.provider = creditFor(body, &links);
    result.creditLinks = links;
    result.creditRequired = YES;
    result.karaokeLines = lines;
    result.wordTimed = SGKaraokeLinesTiming(lines) == SGKaraokeTimingWords;
    result.synced = SGKaraokeLinesTiming(lines) != SGKaraokeTimingNone;
    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    if (result.synced) {
        SGLyricsPageLines(lines, &starts, &texts);
    } else {
        NSMutableArray<NSNumber *> *zeros = [NSMutableArray array];
        NSMutableArray<NSString *> *plain = [NSMutableArray array];
        for (SGKaraokeLine *line in lines) {
            [zeros addObject:@0];
            [plain addObject:SGKaraokeLineText(line)];
        }
        starts = zeros;
        texts = pageTexts ?: plain;
        if (pageTexts) {
            [zeros removeAllObjects];
            for (NSUInteger i = 0; i < pageTexts.count; i++) [zeros addObject:@0];
        }
    }
    result.starts = starts;
    result.texts = texts;
    return result;
}

#pragma mark - asking

// Main queue only, as the walk asks and the reply calls back there.
static NSMutableDictionary<NSString *, id> *sg_answers;   // a result, or NSNull for "none"
static NSTimeInterval sg_waitUntil;   // a rate limit's end, by the system's uptime
static NSString *sg_refused;          // the error code of the last 401 or 403, "" when it gave none
static NSTimeInterval sg_refusedUntil;

static NSTimeInterval uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

// Spotify's 22 character base62 id, the only thing the API takes.
static BOOL isTrackID(NSString *trackID) {
    if (trackID.length != 22) return NO;
    NSCharacterSet *base62 = [NSCharacterSet characterSetWithCharactersInString:
        @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    return [trackID rangeOfCharacterFromSet:base62.invertedSet].location == NSNotFound;
}

// A header's wait in seconds: a number of seconds, a Unix time (a RateLimit-Reset some servers send),
// or an HTTP date; 0 when it says none.
static NSTimeInterval secondsIn(NSString *value, NSDate *now) {
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!value.length) return 0;
    if ([value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789."].invertedSet].location == NSNotFound) {
        double seconds = value.doubleValue;
        return seconds > 1e9 ? seconds - now.timeIntervalSince1970 : seconds;
    }
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    format.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
    NSDate *date = [format dateFromString:value];
    return date ? [date timeIntervalSinceDate:now] : 0;
}

// How long to leave the API alone after this reply: a 429 or 503 for its Retry-After, else its
// RateLimit-Reset, else a minute; any reply with no requests left until its RateLimit-Reset. Never more
// than an hour.
NSTimeInterval SGSpicyLyricsWait(NSHTTPURLResponse *reply, NSDate *now);
NSTimeInterval SGSpicyLyricsWait(NSHTTPURLResponse *reply, NSDate *now) {
    NSString *reset = [reply valueForHTTPHeaderField:@"RateLimit-Reset"];
    NSTimeInterval wait = 0;
    if (reply.statusCode == 429 || reply.statusCode == 503) {
        wait = secondsIn([reply valueForHTTPHeaderField:@"Retry-After"], now);
        if (wait <= 0) wait = secondsIn(reset, now);
        if (wait <= 0) wait = kDefaultWait;
    } else {
        NSString *left = [[reply valueForHTTPHeaderField:@"RateLimit-Remaining"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([left isEqualToString:@"0"]) wait = secondsIn(reset, now);
    }
    return MIN(MAX(wait, 0), kMostWait);
}

// What a refusal's error code means, short enough for the source's row.
static NSString *refusalReason(NSString *code) {
    if ([code isEqualToString:@"origin_not_allowed"] || [code isEqualToString:@"origins_not_configured"]) return @"Key rejected: allow No origin header";
    if ([code isEqualToString:@"application_paused"]) return @"Key rejected: paused";
    if ([code isEqualToString:@"key_revoked"]) return @"Key rejected: revoked";
    if ([code isEqualToString:@"key_not_found"] || [code isEqualToString:@"key_malformed"] || [code isEqualToString:@"malformed_authorization"]) return @"Key rejected: not found";
    for (NSString *word in @[@"suspended", @"disabled", @"deleted"]) {
        if ([code containsString:word]) return @"Key rejected: disabled";
    }
    return @"Key rejected";
}

NSString *SGSpicyLyricsStatus(void) {
    if (!SGSpicyLyricsKeySet()) return @"Needs a key";
    return sg_refused ? refusalReason(sg_refused) : nil;
}

static NSString *errorCodeIn(id root) {
    NSDictionary *body = [root isKindOfClass:NSDictionary.class] ? root[@"Body"] : nil;
    return stringIn(body, @"error") ?: stringIn(root, @"error");
}

static void keepAnswer(NSString *trackID, id answer) {
    if (!sg_answers) sg_answers = [NSMutableDictionary dictionary];
    if (sg_answers.count >= kKeptTracks) [sg_answers removeAllObjects];
    sg_answers[trackID] = answer;
}

// The ask with the key passed in, which harness/spicy-lyrics/ drives without a Keychain.
void SGSpicyLyricsAskWith(NSString *key, SGLyricsQuery *query, void (^done)(SGLyricsResult *result));
void SGSpicyLyricsAskWith(NSString *key, SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSString *trackID = query.trackID;
    if (!key.length || !isTrackID(trackID)) {
        done(nil);
        return;
    }
    id kept = sg_answers[trackID];
    if (kept) {
        done(kept == NSNull.null ? nil : kept);
        return;
    }
    NSTimeInterval now = uptime();
    if (sg_refused && now < sg_refusedUntil) {
        done(nil);
        return;
    }
    if (now < sg_waitUntil) {
        // Lost rather than "no lyrics", so the walk is not kept and asks again once the wait is over.
        SGLog(@"spicy lyrics: %@ skipped, rate limited for %.0fs more", trackID, sg_waitUntil - now);
        SGLyricsNoteReply(nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]);
        done(nil);
        return;
    }
    NSURL *url = [NSURL URLWithString:[kAPI stringByAppendingString:trackID]];
    NSDictionary *headers = @{@"Authorization": [@"Bearer " stringByAppendingString:key], @"Accept": @"application/json", @"User-Agent": kAgent};
    SGLyricsGetJSONReply(url, headers, ^(id root, NSHTTPURLResponse *reply) {
        NSInteger status = reply.statusCode;
        NSTimeInterval wait = SGSpicyLyricsWait(reply, NSDate.date);
        if (wait > 0) {
            sg_waitUntil = uptime() + wait;
            SGLog(@"spicy lyrics: rate limited (%ld), leaving it alone for %.0fs", (long)status, wait);
        }
        if (status == 401 || status == 403) {
            sg_refused = errorCodeIn(root) ?: @"";
            sg_refusedUntil = uptime() + kRefusedWait;
            SGLog(@"spicy lyrics: the key was refused (%ld, %@), not asking for %.0fs", (long)status, sg_refused, kRefusedWait);
            done(nil);
            return;
        }
        if (status == 200 || status == 404) sg_refused = nil;
        SGLyricsResult *result = status == 200 ? SGSpicyLyricsResult(root) : nil;
        if (status == 200 || status == 404 || status == 400) keepAnswer(trackID, result ?: NSNull.null);
        SGLog(@"spicy lyrics: %@ %@", trackID, result
              ? [NSString stringWithFormat:@"has %lu %@ lines, credited to %@", (unsigned long)result.karaokeLines.count,
                 result.wordTimed ? @"word timed" : result.synced ? @"line timed" : @"untimed", result.provider]
              : [NSString stringWithFormat:@"has nothing (%ld)", (long)status]);
        done(result);
    });
}

SGLyricsAsk SGSpicyLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    SGSpicyLyricsAskWith(storedKey(), query, done);
};

#pragma mark - the row

// What is wrong with a pasted key, nil when it looks like a publishable one: sl_pk_, then printable
// ASCII, 12 characters at the least.
NSString *SGSpicyLyricsKeyProblem(NSString *key);
NSString *SGSpicyLyricsKeyProblem(NSString *key) {
    if ([key hasPrefix:@"sl_sk_"]) return @"That is a secret key, which belongs on a server, not in an app.";
    NSCharacterSet *printable = [NSCharacterSet characterSetWithRange:NSMakeRange(0x21, 0x7E - 0x21 + 1)];
    if (![key hasPrefix:@"sl_pk_"] || key.length < 12 || [key rangeOfCharacterFromSet:printable.invertedSet].location != NSNotFound) {
        return @"That is not a publishable key.";
    }
    return nil;
}

// A key saved puts the source at the top of the order, since it was set to be used; a key removed
// takes it out, as it can answer nothing without one. Either way a refusal of the old key is forgotten.
static void setKey(NSString *key) {
    storeKey(key);
    sg_refused = nil;
    sg_refusedUntil = 0;
    NSMutableArray<NSString *> *order = [SGLyricsOrder() mutableCopy];
    [order removeObject:SGSpicyLyricsKey];
    if (key.length) [order insertObject:SGSpicyLyricsKey atIndex:0];
    SGLyricsSetOrder(order);
}

static void askForKey(NSString *problem) {
    NSString *how = @"Sign up at Spicy Lyrics for Developers, create an application, turn on client access with "
                    @"No origin header allowed, and paste its publishable key (sl_pk_). The key stays on this iPhone.";
    NSString *refused = SGSpicyLyricsKeySet() ? SGSpicyLyricsStatus() : nil;
    NSString *lead = problem ?: refused ? [refused stringByAppendingString:@"."] : nil;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Spicy Lyrics Key"
        message:lead ? [NSString stringWithFormat:@"%@\n\n%@", lead, how] : how
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"sl_pk_...";
        field.keyboardType = UIKeyboardTypeASCIICapable;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.spellCheckingType = UITextSpellCheckingTypeNo;
    }];
    UIAlertAction *save = [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!key.length) return;
        NSString *wrong = SGSpicyLyricsKeyProblem(key);
        // Asked again, saying what was wrong, rather than kept and failing on every track.
        if (wrong) dispatch_async(dispatch_get_main_queue(), ^{ askForKey(wrong); });
        else setKey(key);
    }];
    [alert addAction:save];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Dashboard" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:kDashboard] options:@{} completionHandler:nil];
    }]];
    if (SGSpicyLyricsKeySet()) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            setKey(nil);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.preferredAction = save;
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

SGModRow *SGSpicyLyricsKeyRow(void) {
    return SGStatActionRow(@"Spicy Lyrics key", @"Community word syncs, with your own key",
                           ^NSString *{ return !SGSpicyLyricsKeySet() ? @"Off" : sg_refused ? @"Rejected" : @"Set"; }, ^{ askForKey(nil); });
}
