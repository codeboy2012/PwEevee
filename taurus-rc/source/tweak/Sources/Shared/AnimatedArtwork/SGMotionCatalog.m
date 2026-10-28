// Animated album covers, artist logos and songs by ISRC from Apple Music's catalog. The catalog takes the developer
// token Apple Music's web player carries, so the token is read out of the web player's script and
// kept until it is about to expire. Answers are kept for the launch, and an album's for a week on disk.
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"

static NSString *const kTokenKey = @"spotifyglass.motion.token";
static NSString *const kBrowse = @"https://music.apple.com/us/browse";
static NSString *const kSearch = @"https://amp-api.music.apple.com/v1/catalog/us/search";
static NSString *const kSafari = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15";
// A token this close to its expiry is read again rather than used.
static const NSTimeInterval kTokenMargin = 3600;

// Main queue only. NSNull is kept for an album or artist that has nothing.
static NSMutableDictionary<NSString *, id> *sg_kept;
static NSMutableDictionary<NSString *, NSMutableArray *> *sg_waiting;
static NSMutableArray<void (^)(NSString *)> *sg_tokenWaiting;

// An album's answer, its clip's address or that it has none, kept on disk so that an album opened before starts at
// once after a relaunch, without the token and the search. Older answers are asked again.
static const NSTimeInterval kAlbumAnswerLife = 7 * 24 * 3600;

static NSURL *albumAnswersFile(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [caches URLByAppendingPathComponent:@"spoti.pw/Motion/album answers.plist"];
}

// Key to {url: the address, "" for none; at: when it was asked}.
static NSMutableDictionary<NSString *, NSDictionary *> *sg_albumAnswers;

static void keepAlbumAnswer(NSString *key, NSURL *remote) {
    sg_albumAnswers[key] = @{@"url": remote.absoluteString ?: @"", @"at": NSDate.date};
    NSURL *file = albumAnswersFile();
    [NSFileManager.defaultManager createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [sg_albumAnswers writeToURL:file atomically:YES];
}

static void setUp(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_kept = [NSMutableDictionary dictionary];
        sg_albumAnswers = [NSMutableDictionary dictionary];
        NSDictionary *stored = [NSDictionary dictionaryWithContentsOfURL:albumAnswersFile()];
        for (NSString *key in stored) {
            NSDictionary *answer = stored[key];
            NSDate *at = [answer isKindOfClass:NSDictionary.class] ? answer[@"at"] : nil;
            NSString *url = [at isKindOfClass:NSDate.class] ? answer[@"url"] : nil;
            if (![url isKindOfClass:NSString.class] || -at.timeIntervalSinceNow > kAlbumAnswerLife) continue;
            sg_albumAnswers[key] = answer;
            sg_kept[key] = url.length ? ([NSURL URLWithString:url] ?: NSNull.null) : NSNull.null;
        }
        sg_waiting = [NSMutableDictionary dictionary];
        sg_tokenWaiting = [NSMutableArray array];
    });
}

static id dig(id value, NSString *path) {
    for (NSString *key in [path componentsSeparatedByString:@"/"]) {
        if (![value isKindOfClass:NSDictionary.class]) return nil;
        value = value[key];
    }
    return value;
}

static NSString *textOf(NSData *data) {
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

#pragma mark - names

static NSString *plain(NSString *name) {
    NSString *key = [name stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
                                              locale:nil].lowercaseString;
    // Punctuation goes without leaving a gap, so "n’" and "n'" both become "n".
    key = [key stringByReplacingOccurrencesOfString:@"[^\\p{L}\\p{N}\\s]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, key.length)];
    key = [key stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, key.length)];
    return [key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

NSString *SGMotionNameKey(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return @"";
    // Apple Music adds " - Single" and " - EP" to names Spotify gives bare.
    NSRange dash = [name rangeOfString:@" - "];
    if (dash.location != NSNotFound) name = [name substringToIndex:dash.location];
    NSString *edition = @"\\([^)]*\\)|\\[[^\\]]*\\]";
    NSString *bare = plain([name stringByReplacingOccurrencesOfString:edition withString:@" " options:NSRegularExpressionSearch
                                                                range:NSMakeRange(0, name.length)]);
    // A name that is all brackets keeps them, so it still has a key.
    return bare.length ? bare : plain(name);
}

// The name as it is searched for: without what Spotify adds for an edition ("(Deluxe)", "[Remastered]",
// " - 2011 Remaster"), so a search for an edition finds the standard album too, whose cover may be the one
// that moves. A name that is all edition is searched as it is.
NSString *SGMotionSearchName(NSString *name) {
    if (![name isKindOfClass:NSString.class]) return @"";
    NSString *bare = name;
    NSRange dash = [bare rangeOfString:@" - "];
    if (dash.location != NSNotFound) bare = [bare substringToIndex:dash.location];
    bare = [bare stringByReplacingOccurrencesOfString:@"\\([^)]*\\)|\\[[^\\]]*\\]" withString:@" " options:NSRegularExpressionSearch
                                               range:NSMakeRange(0, bare.length)];
    bare = [bare stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, bare.length)];
    bare = [bare stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return bare.length ? bare : name;
}

// Apple Music may credit several artists where Spotify names the lead, so either name may hold the
// other as a run of whole words.
static BOOL sameArtist(NSString *a, NSString *b) {
    if (!a.length || !b.length) return NO;
    NSString *x = [NSString stringWithFormat:@" %@ ", a], *y = [NSString stringWithFormat:@" %@ ", b];
    return [x containsString:y] || [y containsString:x];
}

#pragma mark - playlists

static NSArray<NSString *> *linesOf(NSString *playlist) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [playlist componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length) [lines addObject:trimmed];
    }
    return lines;
}

static NSString *firstGroup(NSString *pattern, NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match ? [text substringWithRange:[match rangeAtIndex:1]] : nil;
}

NSString *SGMotionStreamIn(NSString *master, CGFloat pixels) {
    if (![master isKindOfClass:NSString.class]) return nil;
    NSArray<NSString *> *lines = linesOf(master);
    NSString *best = nil;
    NSInteger bestWidth = 0;
    BOOL bestHEVC = NO;
    for (NSUInteger i = 0; i + 1 < lines.count; i++) {
        if (![lines[i] hasPrefix:@"#EXT-X-STREAM-INF:"] || [lines[i + 1] hasPrefix:@"#"]) continue;
        NSInteger width = [firstGroup(@"RESOLUTION=(\\d+)x\\d+", lines[i]) integerValue];
        if (width <= 0) continue;
        NSString *codecs = firstGroup(@"CODECS=\"([^\"]*)\"", lines[i]);
        BOOL hevc = [codecs hasPrefix:@"hvc1"] || [codecs hasPrefix:@"hev1"];
        BOOL wide = width >= pixels, bestWide = bestWidth >= pixels;
        BOOL better = !best || (wide != bestWide ? wide
                              : width != bestWidth ? (wide ? width < bestWidth : width > bestWidth)
                              : hevc && !bestHEVC);
        if (!better) continue;
        best = lines[i + 1];
        bestWidth = width;
        bestHEVC = hevc;
    }
    return best;
}

NSString *SGMotionWholeFileIn(NSString *media) {
    if (![media isKindOfClass:NSString.class]) return nil;
    NSMutableSet<NSString *> *uris = [NSMutableSet set];
    for (NSString *line in linesOf(media)) {
        NSString *uri = [line hasPrefix:@"#"] ? firstGroup(@"URI=\"([^\"]*)\"", line) : line;
        if (uri) [uris addObject:uri];
    }
    return uris.count == 1 ? uris.anyObject : nil;
}

#pragma mark - requests

static NSMutableURLRequest *requestFor(NSURL *url) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.allowsConstrainedNetworkAccess = SGFlag(SGKeyMotionLowData, NO);
    if ([url.host isEqualToString:@"music.apple.com"]) [request setValue:kSafari forHTTPHeaderField:@"User-Agent"];
    return request;
}

// `parse` runs off the main queue on a 200 answer. `done` gets what it made and the status, 0 for no
// answer at all, on the main queue.
static void fetch(NSURLRequest *request, id (^parse)(NSData *data), void (^done)(id result, NSInteger status)) {
    if (!request.URL) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, 0); });
        return;
    }
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = !error && [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        id result = status == 200 && data ? parse(data) : nil;
        if (status != 200) SGLog(@"motion: %@%@ failed (%ld, %@)", request.URL.host, request.URL.path, (long)status, error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{ done(result, status); });
    }] resume];
}

#pragma mark - token

static NSDictionary *claimsOf(NSString *jwt) {
    NSArray<NSString *> *parts = [jwt isKindOfClass:NSString.class] ? [jwt componentsSeparatedByString:@"."] : nil;
    if (parts.count != 3) return nil;
    NSMutableString *payload = [[[parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                                 stringByReplacingOccurrencesOfString:@"_" withString:@"/"] mutableCopy];
    while (payload.length % 4) [payload appendString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:payload options:0];
    id claims = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [claims isKindOfClass:NSDictionary.class] ? claims : nil;
}

static BOOL usable(NSString *jwt) {
    id expiry = claimsOf(jwt)[@"exp"];
    return [expiry isKindOfClass:NSNumber.class] && [expiry doubleValue] - NSDate.date.timeIntervalSince1970 > kTokenMargin;
}

// The script holds several JWTs; the web player's own is the one the catalog takes.
static NSString *tokenIn(NSData *script) {
    NSString *text = textOf(script);
    if (!text) return nil;
    NSRegularExpression *jwt = [NSRegularExpression regularExpressionWithPattern:@"eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+" options:0 error:nil];
    for (NSTextCheckingResult *match in [jwt matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSString *candidate = [text substringWithRange:match.range];
        if ([claimsOf(candidate)[@"iss"] isEqual:@"AMPWebPlay"]) return candidate;
    }
    return nil;
}

// The script's name carries a hash that changes with every web player release, so the page names it.
static void readToken(void (^done)(NSString *token)) {
    NSURL *browse = [NSURL URLWithString:kBrowse];
    fetch(requestFor(browse), ^id(NSData *data) {
        NSString *html = textOf(data);
        if (!html) return nil;
        NSRange path = [html rangeOfString:@"/assets/index[^\"'\\s>]*\\.js" options:NSRegularExpressionSearch];
        return path.location == NSNotFound ? nil : [NSURL URLWithString:[html substringWithRange:path] relativeToURL:browse].absoluteURL;
    }, ^(NSURL *script, NSInteger status) {
        if (!script) {
            SGLog(@"motion: no web player script on the browse page (%ld)", (long)status);
            done(nil);
            return;
        }
        fetch(requestFor(script), ^id(NSData *data) { return tokenIn(data); }, ^(NSString *token, NSInteger scriptStatus) {
            SGLog(@"motion: token %@ in %@", token ? @"found" : @"not found", script.lastPathComponent);
            done(token);
        });
    });
}

static void withToken(void (^use)(NSString *token)) {
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:kTokenKey];
    if (usable(stored)) {
        use(stored);
        return;
    }
    [sg_tokenWaiting addObject:[use copy]];
    if (sg_tokenWaiting.count > 1) return;
    readToken(^(NSString *token) {
        if (token) [NSUserDefaults.standardUserDefaults setObject:token forKey:kTokenKey];
        NSArray<void (^)(NSString *)> *waiting = [sg_tokenWaiting copy];
        [sg_tokenWaiting removeAllObjects];
        for (void (^waiter)(NSString *) in waiting) waiter(token);
    });
}

// Another request may have read a new token since this one was sent; that one stays.
static void forgetToken(NSString *token) {
    if ([[NSUserDefaults.standardUserDefaults stringForKey:kTokenKey] isEqualToString:token])
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kTokenKey];
}

#pragma mark - catalog

// After a 403 or a 429 the catalog is left alone this long: each lookup meanwhile finds nothing at once and is
// not kept, so it is asked again once the pause is over. Without it every skip sent a search to a catalog that
// had said to stop.
static const NSTimeInterval kCatalogPause = 600;
static NSDate *sg_catalogPausedUntil;

static NSString *escaped(NSString *value) {
    NSCharacterSet *unreserved = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
}

// The array at `path` in the catalog's answer, empty when it has none; `answered` is NO when the catalog
// could not be asked, so the caller does not remember the absence. A refused token is read again once.
static void askCatalog(NSString *address, NSString *path, BOOL renew, void (^done)(NSArray *found, BOOL answered)) {
    if (sg_catalogPausedUntil.timeIntervalSinceNow > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{ done(nil, NO); });
        return;
    }
    withToken(^(NSString *token) {
        if (!token) {
            done(nil, NO);
            return;
        }
        NSMutableURLRequest *request = requestFor([NSURL URLWithString:address]);
        [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
        // The catalog refuses the web player's token without the web player's origin.
        [request setValue:@"https://music.apple.com" forHTTPHeaderField:@"Origin"];
        fetch(request, ^id(NSData *data) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            id found = dig(json, path);
            return [found isKindOfClass:NSArray.class] ? found : @[];
        }, ^(NSArray *found, NSInteger status) {
            if (status == 401 && renew) {
                SGLog(@"motion: token refused, reading it again");
                forgetToken(token);
                askCatalog(address, path, NO, done);
                return;
            }
            if (status == 403 || status == 429) {
                sg_catalogPausedUntil = [NSDate dateWithTimeIntervalSinceNow:kCatalogPause];
                SGLog(@"motion: the catalog answered %ld, not asked for %.0f minutes", (long)status, kCatalogPause / 60);
            }
            done(found, status == 200);
        });
    });
}

// `found` is the search's results of that type.
static void search(NSString *type, NSString *term, NSString *extend, BOOL renew, void (^done)(NSArray *found, BOOL answered)) {
    NSString *address = [NSString stringWithFormat:@"%@?term=%@&types=%@&limit=10&extend=%@", kSearch, escaped(term), type, extend];
    askCatalog(address, [NSString stringWithFormat:@"results/%@/data", type], renew, done);
}

// Runs `look` once per key and launch. `look` calls `answer` exactly once; `keep` is NO for a failure
// worth asking again.
static void lookUp(NSString *key, void (^done)(id value), void (^look)(void (^answer)(id value, BOOL keep))) {
    setUp();
    id kept = sg_kept[key];
    if (kept) {
        done(kept == NSNull.null ? nil : kept);
        return;
    }
    NSMutableArray *waiting = sg_waiting[key];
    if (waiting) {
        [waiting addObject:[done copy]];
        return;
    }
    sg_waiting[key] = [NSMutableArray arrayWithObject:[done copy]];
    look(^(id value, BOOL keep) {
        if (keep) sg_kept[key] = value ?: NSNull.null;
        if (keep && [key hasPrefix:@"album\n"] && (!value || [value isKindOfClass:NSURL.class])) keepAlbumAnswer(key, value);
        NSArray *callers = sg_waiting[key];
        [sg_waiting removeObjectForKey:key];
        for (void (^caller)(id) in callers) caller(value);
    });
}

#pragma mark - album covers

static NSString *videoOf(NSDictionary *editorialVideo, SGMotionShape shape) {
    NSArray<NSString *> *names = shape == SGMotionTall
        ? @[@"motionTallVideo3x4", @"motionDetailTall", @"motionSquareVideo1x1", @"motionDetailSquare"]
        : @[@"motionSquareVideo1x1", @"motionDetailSquare"];
    for (NSString *name in names) {
        id video = dig(editorialVideo, [name stringByAppendingString:@"/video"]);
        if ([video isKindOfClass:NSString.class] && [video length]) return video;
    }
    return nil;
}

// The master playlist names a stream per size and codec; the chosen stream's playlist names one file.
static void wholeFileOf(NSURL *master, CGFloat pixels, void (^answer)(id file, BOOL keep)) {
    fetch(requestFor(master), ^id(NSData *data) {
        NSString *uri = SGMotionStreamIn(textOf(data), pixels);
        return uri ? [NSURL URLWithString:uri relativeToURL:master].absoluteURL : nil;
    }, ^(NSURL *stream, NSInteger status) {
        if (!stream) {
            answer(nil, status == 200);
            return;
        }
        fetch(requestFor(stream), ^id(NSData *data) {
            NSString *uri = SGMotionWholeFileIn(textOf(data));
            return uri ? [NSURL URLWithString:uri relativeToURL:stream].absoluteURL : nil;
        }, ^(NSURL *file, NSInteger streamStatus) {
            answer(file, streamStatus == 200);
        });
    });
}

void SGMotionAlbumCover(NSString *artist, NSString *album, SGMotionShape shape, CGFloat pixels, void (^done)(NSURL *file)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionAlbumCover(artist, album, shape, pixels, done); });
        return;
    }
    NSString *artistKey = SGMotionNameKey(artist), *albumKey = SGMotionNameKey(album);
    if (!artistKey.length || !albumKey.length) {
        done(nil);
        return;
    }
    NSString *key = [NSString stringWithFormat:@"album\n%ld\n%@\n%@", (long)shape, artistKey, albumKey];
    // The remote file is what is kept: the store may drop its local copy later in the launch.
    lookUp(key, ^(NSURL *remote) { SGMotionFile(remote, done); }, ^(void (^answer)(id, BOOL)) {
        NSString *term = [NSString stringWithFormat:@"%@ %@", artist, SGMotionSearchName(album)];
        search(@"albums", term, @"editorialVideo", YES, ^(NSArray *found, BOOL answered) {
            if (!answered) {
                answer(nil, NO);
                return;
            }
            // Editions share a key (Midnights and Midnights (3am Edition), clean and explicit), and only one of
            // them may have the motion: the album of the same name first, then the first edition that has it.
            NSString *video = nil, *exact = plain(album);
            for (int pass = 0; pass < 2 && !video; pass++) {
                for (id result in found) {
                    id attributes = dig(result, @"attributes");
                    if (!sameArtist(artistKey, SGMotionNameKey(dig(attributes, @"artistName")))) continue;
                    id name = dig(attributes, @"name");
                    if (pass == 0 ? ![name isKindOfClass:NSString.class] || ![plain(name) isEqualToString:exact]
                                  : ![SGMotionNameKey(name) isEqualToString:albumKey]) continue;
                    video = videoOf(dig(attributes, @"editorialVideo"), shape);
                    if (video) break;
                }
            }
            NSURL *master = video ? [NSURL URLWithString:video] : nil;
            SGLog(@"motion: %@ by %@ has %@", album, artist, master ? @"an animated cover" : @"no animated cover");
            if (!master) {
                answer(nil, YES);
                return;
            }
            wholeFileOf(master, pixels, answer);
        });
    });
}

#pragma mark - artist logos

// The URL is a template ending in {w}x{h}bb.jpg; the same image comes as a PNG with its transparency.
static NSURL *logoURL(id logo, CGFloat pixels) {
    id url = dig(logo, @"url"), width = dig(logo, @"width"), height = dig(logo, @"height");
    if (![url isKindOfClass:NSString.class] || ![width isKindOfClass:NSNumber.class] || ![height isKindOfClass:NSNumber.class]) return nil;
    if ([width doubleValue] <= 0 || [height doubleValue] <= 0) return nil;
    long w = MAX(1, lround(pixels)), h = MAX(1, lround(pixels * [height doubleValue] / [width doubleValue]));
    NSString *filled = [[url stringByReplacingOccurrencesOfString:@"{w}" withString:@(w).stringValue]
                        stringByReplacingOccurrencesOfString:@"{h}" withString:@(h).stringValue];
    if ([filled hasSuffix:@".jpg"]) filled = [[filled substringToIndex:filled.length - 4] stringByAppendingString:@".png"];
    return [NSURL URLWithString:filled];
}

void SGMotionArtistLogo(NSString *artist, CGFloat pixels, void (^done)(UIImage *logo)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionArtistLogo(artist, pixels, done); });
        return;
    }
    NSString *artistKey = SGMotionNameKey(artist);
    if (!artistKey.length) {
        done(nil);
        return;
    }
    lookUp([@"logo\n" stringByAppendingString:artistKey], ^(UIImage *logo) { done(logo); }, ^(void (^answer)(id, BOOL)) {
        search(@"artists", artist, @"editorialArtwork", YES, ^(NSArray *found, BOOL answered) {
            if (!answered) {
                answer(nil, NO);
                return;
            }
            NSURL *url = nil;
            for (id result in found) {
                id attributes = dig(result, @"attributes");
                if (![SGMotionNameKey(dig(attributes, @"name")) isEqualToString:artistKey]) continue;
                url = logoURL(dig(attributes, @"editorialArtwork/musicContentColorLogoTrimmed"), pixels);
                break;
            }
            SGLog(@"motion: %@ has %@", artist, url ? @"a logo" : @"no logo");
            if (!url) {
                answer(nil, YES);
                return;
            }
            fetch(requestFor(url), ^id(NSData *data) { return [UIImage imageWithData:data]; }, ^(UIImage *logo, NSInteger status) {
                answer(logo, status == 200);
            });
        });
    });
}

#pragma mark - recordings

// The catalog's songs with this ISRC, for iOS's Music Haptics: the recording itself, not a search by name.
void SGMotionSongsWithISRC(NSString *isrc, void (^done)(NSArray *songs)) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGMotionSongsWithISRC(isrc, done); });
        return;
    }
    if (!isrc.length) {
        done(nil);
        return;
    }
    lookUp([@"isrc\n" stringByAppendingString:isrc], done, ^(void (^answer)(id, BOOL)) {
        // The phone's own country first, as Apple sells some recordings only there; then the US catalog.
        NSString *region = NSLocale.currentLocale.countryCode.lowercaseString;
        if (![region rangeOfString:@"^[a-z]{2}$" options:NSRegularExpressionSearch].length) region = @"us";
        // filter[isrc] and fields[songs], the brackets escaped: iOS before 17 makes no URL of them bare.
        NSString *(^addressIn)(NSString *) = ^NSString *(NSString *storefront) {
            return [NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/songs?filter%%5Bisrc%%5D=%@&fields%%5Bsongs%%5D=isrc,durationInMillis,hasHaptics",
                    storefront, escaped(isrc)];
        };
        askCatalog(addressIn(region), @"data", YES, ^(NSArray *found, BOOL answered) {
            if (found.count || [region isEqualToString:@"us"]) {
                answer(found, answered);
                return;
            }
            askCatalog(addressIn(@"us"), @"data", YES, ^(NSArray *inUS, BOOL answeredInUS) { answer(inUS, answeredInUS); });
        });
    });
}
