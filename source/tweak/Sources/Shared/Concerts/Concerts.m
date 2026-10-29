// Upcoming concerts, with no account and no key: the artist is found on Songkick's public search page (its slug
// must be this very name), then the events are read from the structured data of its calendar page. If Songkick
// does not answer at all, Bandsintown's events endpoint is tried, which only answers for app ids it approved.
#import "Core/SGCore.h"
#import "Concerts.h"

static NSString *const kBase = @"https://rest.bandsintown.com/artists/";
// External contract, not PwEevee branding: Bandsintown's endpoint answers only app ids it has approved
// (issued to the upstream Taurus project's registration) and denies unknown ones. Kept so the
// events fallback keeps working; a future migration first needs the id registered with Bandsintown.
static NSString *const kAppID = @"taurus-spotify-mod";
static NSString *const kAgent = @"PwEevee/" SG_VERSION " (Spotify for iOS, upcoming concerts)";
static const NSTimeInterval kKept = 6 * 3600, kPastGrace = 6 * 3600, kRefusedWait = 600;

@implementation SGConcert
@end

static NSString *stringIn(id object, NSString *name) {
    id value = [object isKindOfClass:NSDictionary.class] ? object[name] : nil;
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

static NSDictionary *dictIn(id object, NSString *name) {
    id value = [object isKindOfClass:NSDictionary.class] ? object[name] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

// A name as two spellings of one artist compare: no case, accents, spaces or punctuation.
static NSString *normalized(NSString *name) {
    NSString *folded = [name stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch | NSWidthInsensitiveSearch locale:nil];
    NSMutableString *kept = [NSMutableString string];
    [folded enumerateSubstringsInRange:NSMakeRange(0, folded.length) options:NSStringEnumerationByComposedCharacterSequences
                            usingBlock:^(NSString *s, NSRange r, NSRange e, BOOL *stop) {
        if ([s rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location != NSNotFound) [kept appendString:s];
    }];
    return kept;
}

// "2026-11-05T20:00:00" is the venue's own clock with no zone: read as GMT and shown in GMT, it reads as written.
static NSDate *venueClock(NSString *text, BOOL *hasTime) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
    });
    NSString *clean = text.length >= 19 ? [text substringToIndex:19] : text;
    NSDate *date = clean ? [formatter dateFromString:clean] : nil;
    *hasTime = date && ![clean hasSuffix:@"T00:00:00"];
    return date;
}

static SGConcert *concertFrom(NSDictionary *event) {
    if (![event isKindOfClass:NSDictionary.class]) return nil;
    BOOL hasTime = NO;
    NSDate *date = venueClock(stringIn(event, @"starts_at") ?: stringIn(event, @"datetime"), &hasTime);
    if (!date) return nil;
    NSDictionary *venue = dictIn(event, @"venue");
    SGConcert *concert = [SGConcert new];
    id identifier = event[@"id"];
    concert.identifier = [identifier respondsToSelector:@selector(stringValue)] ? [identifier stringValue] : identifier;
    concert.title = stringIn(event, @"title");
    concert.venue = stringIn(venue, @"name");
    concert.city = stringIn(venue, @"city");
    concert.country = stringIn(venue, @"country");
    concert.date = date;
    concert.zone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    concert.hasTime = hasTime;
    // Tickets when there is an offer, else the event's own page.
    NSString *link = nil;
    for (id offer in [event[@"offers"] isKindOfClass:NSArray.class] ? event[@"offers"] : @[]) {
        link = stringIn(offer, @"url");
        if (link) break;
    }
    concert.ticketURL = link ?: stringIn(event, @"url");
    return concert;
}

#pragma mark - state and requests

static NSMutableDictionary<NSString *, NSDictionary *> *sg_kept;            // key -> @{at, list}
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;        // key -> callbacks
static NSTimeInterval sg_refusedUntil;

static NSTimeInterval uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static void getJSON(NSString *name, NSString *path, void (^done)(id root, NSInteger status)) {
    // A slash or a question mark in a name has its own spelling in the path.
    NSString *escaped = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"%252F"]
                         stringByReplacingOccurrencesOfString:@"?" withString:@"%253F"];
    NSString *encoded = [escaped stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~%"]];
    NSString *url = [NSString stringWithFormat:@"%@%@%@?app_id=%@%@", kBase, encoded, path.length ? [@"/" stringByAppendingString:path] : @"",
                     kAppID, path.length ? @"&date=upcoming" : @""];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [request setValue:kAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        done(root, status);
    }] resume];
}

static void finish(NSString *cacheKey, NSArray<SGConcert *> *list, BOOL keep) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (keep) {
            if (!sg_kept) sg_kept = [NSMutableDictionary dictionary];
            sg_kept[cacheKey] = @{@"at": @(uptime()), @"list": list};
        }
        NSArray *callbacks = sg_waiting[cacheKey];
        [sg_waiting removeObjectForKey:cacheKey];
        for (void (^callback)(NSArray<SGConcert *> *) in callbacks) callback(list);
    });
}


#pragma mark - Songkick (public pages, no key)

static NSString *const kSKBase = @"https://www.songkick.com";
// Songkick's pages answer a browser; a bare app agent is often turned away.
static NSString *const kBrowser = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

static NSString *queryEscape(NSString *text) {
    return [text stringByAddingPercentEncodingWithAllowedCharacters:
            [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"]];
}

static void getHTML(NSString *url, void (^done)(NSString *html, NSInteger status)) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [request setValue:kBrowser forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];
    [request setValue:@"en" forHTTPHeaderField:@"Accept-Language"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSString *html = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        done(html, status);
    }] resume];
}

// The artist page's path ("/artists/1234-rosalia") whose slug is this very name: found in the search results by
// the slug alone, so no markup but the links is relied on. A namesake or a tribute act has another slug.
static NSString *artistPath(NSString *html, NSString *cacheKey) {
    NSRegularExpression *links = [NSRegularExpression regularExpressionWithPattern:@"/artists/(\\d+)-([A-Za-z0-9%_\\-]+)" options:0 error:nil];
    for (NSTextCheckingResult *m in [links matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *slug = [[html substringWithRange:[m rangeAtIndex:2]] stringByRemovingPercentEncoding] ?: @"";
        if ([normalized(slug) isEqualToString:cacheKey]) {
            return [NSString stringWithFormat:@"/artists/%@-%@", [html substringWithRange:[m rangeAtIndex:1]], [html substringWithRange:[m rangeAtIndex:2]]];
        }
    }
    return nil;
}

// Every event the page describes in its structured data (JSON-LD), however the blocks are nested.
static void collectEvents(id node, NSMutableArray *out) {
    if ([node isKindOfClass:NSArray.class]) {
        for (id item in node) collectEvents(item, out);
    } else if ([node isKindOfClass:NSDictionary.class]) {
        id type = node[@"@type"];
        NSString *kind = [type isKindOfClass:NSArray.class] ? [type componentsJoinedByString:@" "] : [type isKindOfClass:NSString.class] ? type : @"";
        if ([kind containsString:@"Event"]) [out addObject:node];
        if ([node[@"@graph"] isKindOfClass:NSArray.class]) collectEvents(node[@"@graph"], out);
    }
}

static NSArray *eventsIn(NSString *html) {
    NSMutableArray *events = [NSMutableArray array];
    NSRegularExpression *blocks = [NSRegularExpression regularExpressionWithPattern:@"<script[^>]*application/ld\\+json[^>]*>(.*?)</script>"
                                                                            options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    for (NSTextCheckingResult *m in [blocks matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSData *json = [[html substringWithRange:[m rangeAtIndex:1]] dataUsingEncoding:NSUTF8StringEncoding];
        id root = json.length ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
        collectEvents(root, events);
    }
    return events;
}

static SGConcert *concertFromLD(NSDictionary *event) {
    if (![event isKindOfClass:NSDictionary.class]) return nil;
    if ([stringIn(event, @"eventStatus") containsString:@"Cancel"]) return nil;
    NSString *start = stringIn(event, @"startDate");
    if (start.length == 10) start = [start stringByAppendingString:@"T00:00:00"];
    BOOL hasTime = NO;
    NSDate *date = venueClock(start, &hasTime);
    if (!date) return nil;
    id place = event[@"location"];
    NSDictionary *venue = [place isKindOfClass:NSArray.class] ? [place firstObject] : place;
    NSDictionary *address = dictIn(venue, @"address");
    id country = address[@"addressCountry"];
    SGConcert *concert = [SGConcert new];
    NSString *link = stringIn(event, @"url");
    concert.identifier = link ?: [NSString stringWithFormat:@"%@|%@", stringIn(event, @"name") ?: @"", start];
    concert.title = stringIn(event, @"name");
    concert.venue = stringIn(venue, @"name");
    concert.city = stringIn(address, @"addressLocality");
    concert.country = [country isKindOfClass:NSString.class] ? country : stringIn(country, @"name");
    concert.date = date;
    concert.zone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    concert.hasTime = hasTime;
    NSString *ticket = nil;
    id offers = event[@"offers"];
    for (id offer in [offers isKindOfClass:NSArray.class] ? offers : (offers ? @[offers] : @[])) {
        ticket = stringIn(offer, @"url");
        if (ticket) break;
    }
    concert.ticketURL = ticket ?: link;
    return concert;
}

// Past events out, repeats out, soonest first.
static NSArray<SGConcert *> *tidy(NSArray *events, SGConcert *(^convert)(NSDictionary *)) {
    NSDate *oldest = [NSDate dateWithTimeIntervalSinceNow:-kPastGrace];
    NSMutableArray<SGConcert *> *list = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *event in events) {
        SGConcert *concert = convert(event);
        if (!concert || [concert.date compare:oldest] == NSOrderedAscending) continue;
        if (concert.identifier && [seen containsObject:concert.identifier]) continue;
        if (concert.identifier) [seen addObject:concert.identifier];
        [list addObject:concert];
    }
    [list sortUsingComparator:^NSComparisonResult(SGConcert *a, SGConcert *b) { return [a.date compare:b.date]; }];
    return list;
}

static void fetchBandsintown(NSString *artistName, NSString *cacheKey);

static void fetchSongkick(NSString *artistName, NSString *cacheKey) {
    NSString *search = [NSString stringWithFormat:@"%@/search?query=%@&type=artists", kSKBase, queryEscape(artistName)];
    getHTML(search, ^(NSString *html, NSInteger status) {
        if (status == 429) {
            dispatch_async(dispatch_get_main_queue(), ^{ sg_refusedUntil = uptime() + kRefusedWait; });
            finish(cacheKey, @[], NO);
            return;
        }
        if (status != 200 || !html) {
            SGLog(@"concerts: songkick search for %@ answered %ld, trying bandsintown", artistName, (long)status);
            fetchBandsintown(artistName, cacheKey);
            return;
        }
        NSString *path = artistPath(html, cacheKey);
        if (!path) {
            SGLog(@"concerts: no artist %@ on songkick", artistName);
            finish(cacheKey, @[], YES);
            return;
        }
        getHTML([NSString stringWithFormat:@"%@%@/calendar", kSKBase, path], ^(NSString *page, NSInteger code) {
            if (code != 200 || !page) {
                SGLog(@"concerts: songkick calendar for %@ answered %ld", artistName, (long)code);
                finish(cacheKey, @[], NO);
                return;
            }
            NSArray<SGConcert *> *list = tidy(eventsIn(page), ^SGConcert *(NSDictionary *e) { return concertFromLD(e); });
            SGLog(@"concerts: %@ has %lu upcoming on songkick", artistName, (unsigned long)list.count);
            finish(cacheKey, list, YES);
        });
    });
}

#pragma mark - Bandsintown (only if Songkick does not answer)

static void fetchBandsintown(NSString *artistName, NSString *cacheKey) {
    getJSON(artistName, @"", ^(id artist, NSInteger status) {
        if (status == 401 || status == 403 || status == 429) {
            dispatch_async(dispatch_get_main_queue(), ^{ sg_refusedUntil = uptime() + kRefusedWait; });
            SGLog(@"concerts: bandsintown answered %ld, not asking for %.0fs", (long)status, kRefusedWait);
            finish(cacheKey, @[], NO);
            return;
        }
        // A different artist with a similar name is not this one.
        NSString *found = stringIn(artist, @"name");
        if (status != 200 || !found || ![normalized(found) isEqualToString:cacheKey]) {
            SGLog(@"concerts: no artist %@ on bandsintown (%ld)", artistName, (long)status);
            finish(cacheKey, @[], status == 200 || status == 404);
            return;
        }
        getJSON(artistName, @"events", ^(id events, NSInteger code) {
            if (code != 200 || ![events isKindOfClass:NSArray.class]) {
                SGLog(@"concerts: events for %@ answered %ld", artistName, (long)code);
                finish(cacheKey, @[], NO);
                return;
            }
            NSArray<SGConcert *> *list = tidy(events, ^SGConcert *(NSDictionary *e) { return concertFrom(e); });
            SGLog(@"concerts: %@ has %lu upcoming", artistName, (unsigned long)list.count);
            finish(cacheKey, list, YES);
        });
    });
}

#pragma mark - asking

void SGConcertsFetch(NSString *artistName, NSString *artistID, void (^done)(NSArray<SGConcert *> *concerts)) {
    NSString *cacheKey = normalized(artistName ?: @"");
    if (!done) return;
    if (!cacheKey.length || uptime() < sg_refusedUntil) {
        done(@[]);
        return;
    }
    NSDictionary *kept = sg_kept[cacheKey];
    if (kept && uptime() - [kept[@"at"] doubleValue] < kKept) {
        done(kept[@"list"]);
        return;
    }
    if (!sg_waiting) sg_waiting = [NSMutableDictionary dictionary];
    NSMutableArray *callbacks = sg_waiting[cacheKey];
    if (callbacks) {
        [callbacks addObject:[done copy]];
        return;
    }
    sg_waiting[cacheKey] = [NSMutableArray arrayWithObject:[done copy]];

    fetchSongkick(artistName, cacheKey);
}
