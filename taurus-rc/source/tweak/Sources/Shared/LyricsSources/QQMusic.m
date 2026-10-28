// QQ Music, for the Mandarin, Cantonese and other Asian songs the rest have no timed lyrics for.
// Timed by the line: its own word timing (QRC) comes enciphered, so plain LRC is asked for and read
// the way LRCLIB's is. Searched by title and artist, and a recording is only taken when its title
// is the track's, one of its singers is the track's artist and its length is about the track's, so a
// cover or a namesake by someone else is passed over.
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kAPI = @"https://u.y.qq.com/cgi-bin/musicu.fcg";
static const NSInteger kLengthSlack = 6;
static NSString *const kLyricRequest = @"music.musichallSong.PlayLyricInfo.GetPlayLyricInfo";

NSString *SGLyricsMatchKey(NSString *text) {
    static NSCharacterSet *dropped;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *building = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
        [building formUnionWithCharacterSet:NSCharacterSet.punctuationCharacterSet];
        [building formUnionWithCharacterSet:NSCharacterSet.symbolCharacterSet];
        dropped = [building copy];
    });
    if (![text isKindOfClass:NSString.class]) return @"";
    return [[text.lowercaseString componentsSeparatedByCharactersInSet:dropped] componentsJoinedByString:@""];
}

NSString *SGLyricsLeadArtist(NSString *artist) {
    NSRange featuring = [artist rangeOfString:@" feat" options:NSCaseInsensitiveSearch];
    return featuring.location == NSNotFound ? artist : [artist substringToIndex:featuring.location];
}

BOOL SGLyricsSameArtist(NSString *credited, NSString *artist) {
    NSString *name = SGLyricsMatchKey(credited), *lead = SGLyricsMatchKey(SGLyricsLeadArtist(artist));
    return name.length && lead.length && ([name containsString:lead] || [lead containsString:name]);
}

static id dig(id root, NSArray<NSString *> *path) {
    for (NSString *key in path) root = [root isKindOfClass:NSDictionary.class] ? root[key] : nil;
    return root;
}

static void ask(NSString *name, NSDictionary *request, void (^done)(id reply)) {
    NSDictionary *body = @{@"comm": @{@"ct": @"19", @"cv": @"1859", @"uin": @"0"}, name: request};
    NSDictionary *headers = @{@"Referer": @"https://y.qq.com/", @"User-Agent": SGLyricsBrowserAgent, @"Accept": @"application/json"};
    SGLyricsPostJSON([NSURL URLWithString:kAPI], headers, body, ^(id root) {
        done(dig(root, @[name, @"data"]));
    });
}

// The first recording on the page that is the track: QQ ranks its own catalog well, so the first
// that fits is taken rather than the closest in length.
static NSNumber *songFor(id data, SGLyricsQuery *query) {
    NSString *title = SGLyricsMatchKey(query.title);
    id list = dig(data, @[@"body", @"song", @"list"]);
    for (NSDictionary *song in [list isKindOfClass:NSArray.class] ? list : @[]) {
        if (![song isKindOfClass:NSDictionary.class]) continue;
        id name = [song[@"title"] isKindOfClass:NSString.class] ? song[@"title"] : song[@"songname"];
        if (![SGLyricsMatchKey(name) isEqualToString:title]) continue;
        id interval = song[@"interval"];
        NSInteger length = [interval isKindOfClass:NSNumber.class] ? [interval integerValue] : 0;
        if (query.seconds > 0 && length > 0 && labs(length - query.seconds) > kLengthSlack) continue;
        BOOL sung = NO;
        id singers = song[@"singer"];
        for (NSDictionary *singer in [singers isKindOfClass:NSArray.class] ? singers : @[]) {
            sung = sung || ([singer isKindOfClass:NSDictionary.class] && SGLyricsSameArtist(singer[@"name"], query.artist));
        }
        if (sung && [song[@"id"] isKindOfClass:NSNumber.class]) return song[@"id"];
    }
    return nil;
}

SGLyricsAsk SGQQMusicAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSString *lead = SGLyricsLeadArtist(query.artist);
    if (!SGLyricsMatchKey(query.title).length || !SGLyricsMatchKey(lead).length) {
        done(nil);
        return;
    }
    ask(@"req", @{@"module": @"music.search.SearchCgiService", @"method": @"DoSearchForQQMusicDesktop", @"param": @{
        @"query": [NSString stringWithFormat:@"%@ %@", query.title, lead],
        @"search_type": @0, @"grp": @1, @"num_per_page": @8, @"page_num": @1,
    }}, ^(id found) {
        NSNumber *song = songFor(found, query);
        if (!song) {
            SGLog(@"qqmusic: no recording of %@ by %@ near %lds", query.title, lead, (long)query.seconds);
            done(nil);
            return;
        }
        ask(kLyricRequest, @{@"module": @"music.musichallSong.PlayLyricInfo", @"method": @"GetPlayLyricInfo",
                             @"param": @{@"crypt": @0, @"qrc": @0, @"songID": song}}, ^(id data) {
            id lyric = dig(data, @[@"lyric"]);
            NSData *decoded = [lyric isKindOfClass:NSString.class]
                ? [[NSData alloc] initWithBase64EncodedString:lyric options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
            NSString *lrc = decoded ? [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] : nil;
            SGLyricsResult *result = SGLyricsLRCResult(lrc);
            SGLog(@"qqmusic: song %@ gave %lu timed lines", song, (unsigned long)result.karaokeLines.count);
            done(result);
        });
    });
};
