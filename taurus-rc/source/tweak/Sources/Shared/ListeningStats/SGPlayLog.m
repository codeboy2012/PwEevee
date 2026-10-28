// SGPlayLog.h says what the log holds and why it is a text file.
#include <stdio.h>
#include <time.h>
#import "SGPlayLog.h"

@implementation SGPlay
@end

@implementation SGStatEntry
@end

@implementation SGStats
@end

BOOL SGPlayCounts(double listened, double duration) {
    return listened * 1000 >= SGPlayMinimumMs || (duration > 0 && listened >= duration / 2);
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// Both shapes are UTC. sscanf and timegm rather than NSDateFormatter: an extended export runs to 100k
// rows and more, and the formatter costs microseconds a row.
static int64_t timeIn(NSString *text, BOOL seconds) {
    struct tm tm = {0};
    const char *c = text.UTF8String;
    int n = seconds ? sscanf(c, "%d-%d-%dT%d:%d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec)
                    : sscanf(c, "%d-%d-%d %d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min);
    if (n < (seconds ? 6 : 5)) return 0;
    tm.tm_year -= 1900;
    tm.tm_mon -= 1;
    return (int64_t)timegm(&tm);
}

// ponytail: the export has no track lengths, so an imported play counts from 30 s only; a full play of
// a track under 30 s is left out. The extended rows' reason_end could tell a finished track apart.
static SGPlay *playFrom(NSDictionary *row) {
    NSString *title, *artist, *album = @"", *uri = @"";
    int64_t end, ms;
    if (row[@"ts"]) {
        title = stringIn(row[@"master_metadata_track_name"]);
        artist = stringIn(row[@"master_metadata_album_artist_name"]);
        album = stringIn(row[@"master_metadata_album_album_name"]) ?: @"";
        uri = stringIn(row[@"spotify_track_uri"]) ?: @"";
        end = stringIn(row[@"ts"]) ? timeIn(row[@"ts"], YES) : 0;
        ms = [row[@"ms_played"] isKindOfClass:NSNumber.class] ? [row[@"ms_played"] longLongValue] : 0;
    } else {
        title = stringIn(row[@"trackName"]);
        artist = stringIn(row[@"artistName"]);
        end = stringIn(row[@"endTime"]) ? timeIn(row[@"endTime"], NO) : 0;
        ms = [row[@"msPlayed"] isKindOfClass:NSNumber.class] ? [row[@"msPlayed"] longLongValue] : 0;
    }
    if (!title || !artist || end <= 0 || ms < SGPlayMinimumMs) return nil;
    SGPlay *play = [SGPlay new];
    play.end = end;
    play.ms = ms;
    play.uri = uri;
    play.title = title;
    play.artist = artist;
    play.album = album;
    return play;
}

NSArray<SGPlay *> *SGPlaysFromExport(NSData *json) {
    id rows = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if (![rows isKindOfClass:NSArray.class]) return nil;
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    BOOL known = NO;
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        // Podcast files of either shape have their own keys, and the extended one's music rows have
        // ts and ms_played, so the keys say what a file is whatever it was renamed to.
        if (!(row[@"ts"] && row[@"ms_played"]) && !(row[@"endTime"] && row[@"msPlayed"])) continue;
        known = YES;
        SGPlay *play = playFrom(row);
        if (play) [plays addObject:play];
    }
    return known || [rows count] == 0 ? plays : nil;
}

#pragma mark - zip

static uint32_t le(const uint8_t *p, int bytes) {
    uint32_t v = 0;
    for (int i = bytes - 1; i >= 0; i--) v = v << 8 | p[i];
    return v;
}

// The central directory names each entry and where it starts; stored and deflated entries are read,
// deflate through NSDataCompressionAlgorithmZlib, which is raw DEFLATE (RFC 1951), as zip's method 8 is.
// ponytail: no ZIP64, so a zip over 4 GB or 65535 entries reads as empty; an export is far smaller.
NSArray<NSData *> *SGJSONFilesInZip(NSData *zip) {
    NSMutableArray<NSData *> *files = [NSMutableArray array];
    const uint8_t *b = zip.bytes;
    size_t size = zip.length;
    if (size < 22) return files;
    size_t eocd = SIZE_MAX;
    size_t floor = size > 22 + 0xFFFF ? size - 22 - 0xFFFF : 0;
    for (size_t i = size - 22; ; i--) {
        if (le(b + i, 4) == 0x06054b50) { eocd = i; break; }
        if (i == floor) break;
    }
    if (eocd == SIZE_MAX) return files;
    uint32_t count = le(b + eocd + 10, 2);
    size_t at = le(b + eocd + 16, 4);
    for (uint32_t n = 0; n < count; n++) {
        if (at + 46 > size || le(b + at, 4) != 0x02014b50) break;
        uint32_t method = le(b + at + 10, 2), packed = le(b + at + 20, 4), length = le(b + at + 24, 4);
        uint32_t nameLength = le(b + at + 28, 2), extra = le(b + at + 30, 2), comment = le(b + at + 32, 2);
        size_t local = le(b + at + 42, 4);
        if (at + 46 + nameLength > size) break;
        NSString *name = [[NSString alloc] initWithBytes:b + at + 46 length:nameLength encoding:NSUTF8StringEncoding];
        at += 46 + nameLength + extra + comment;

        BOOL json = [name.lowercaseString hasSuffix:@".json"] && ![name hasPrefix:@"__MACOSX/"];
        if (!json || local + 30 > size || le(b + local, 4) != 0x04034b50) continue;
        size_t data = local + 30 + le(b + local + 26, 2) + le(b + local + 28, 2);
        if (data + packed > size || length > 1u << 30) continue;
        if (method == 0 && packed == length) {
            [files addObject:[zip subdataWithRange:NSMakeRange(data, packed)]];
        } else if (method == 8 && length) {
            NSData *out = [[zip subdataWithRange:NSMakeRange(data, packed)] decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:nil];
            if (out.length == length) [files addObject:out];
        }
    }
    return files;
}

#pragma mark - the log

static NSString *field(NSString *text) {
    if (!text) return @"";
    NSArray *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"]];
    return [parts componentsJoinedByString:@" "];
}

static NSString *lineOf(SGPlay *play) {
    return [NSString stringWithFormat:@"%lld\t%lld\t%@\t%@\t%@\t%@\n", play.end, play.ms, field(play.uri), field(play.title),
            field(play.artist), field(play.album)];
}

static NSString *keyOf(SGPlay *play) {
    return [NSString stringWithFormat:@"%@\x1f%@", play.title.lowercaseString, play.artist.lowercaseString];
}

@implementation SGPlayLog {
    NSString *_path;
    NSMutableArray<SGPlay *> *_plays;
}

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) _path = [path copy];
    return self;
}

- (NSArray<SGPlay *> *)plays {
    if (_plays) return _plays;
    _plays = [NSMutableArray array];
    NSString *text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 6) continue;
        SGPlay *play = [SGPlay new];
        play.end = f[0].longLongValue;
        play.ms = f[1].longLongValue;
        play.uri = f[2];
        play.title = f[3];
        play.artist = f[4];
        play.album = f[5];
        [_plays addObject:play];
    }
    return _plays;
}

- (void)append:(NSArray<SGPlay *> *)plays {
    if (!plays.count) return;
    [NSFileManager.defaultManager createDirectoryAtPath:_path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableString *text = [NSMutableString string];
    for (SGPlay *play in plays) [text appendString:lineOf(play)];
    FILE *file = fopen(_path.fileSystemRepresentation, "a");
    if (!file) return;
    fputs(text.UTF8String, file);
    fclose(file);
}

// Not loaded for it: a play ending should not read the whole log on the main thread.
- (void)record:(SGPlay *)play {
    [_plays addObject:play];
    [self append:@[play]];
}

- (NSUInteger)merge:(NSArray<SGPlay *> *)incoming {
    NSMutableDictionary<NSString *, NSMutableArray<NSNumber *> *> *ends = [NSMutableDictionary dictionary];
    for (SGPlay *play in self.plays) {
        NSString *key = keyOf(play);
        if (!ends[key]) ends[key] = [NSMutableArray array];
        [ends[key] addObject:@(play.end)];
    }
    NSMutableArray<SGPlay *> *added = [NSMutableArray array];
    for (SGPlay *play in incoming) {
        NSString *key = keyOf(play);
        BOOL have = NO;
        for (NSNumber *end in ends[key]) {
            if (llabs(end.longLongValue - play.end) <= 90) { have = YES; break; }
        }
        if (have) continue;
        if (!ends[key]) ends[key] = [NSMutableArray array];
        [ends[key] addObject:@(play.end)];
        [added addObject:play];
    }
    [_plays addObjectsFromArray:added];
    [self append:added];
    return added.count;
}

- (void)erase {
    [NSFileManager.defaultManager removeItemAtPath:_path error:nil];
    _plays = [NSMutableArray array];
}

@end

#pragma mark - stats

static NSArray<SGStatEntry *> *topOf(NSDictionary<NSString *, SGStatEntry *> *entries, NSUInteger top) {
    NSArray<SGStatEntry *> *sorted = [entries.allValues sortedArrayUsingComparator:^NSComparisonResult(SGStatEntry *a, SGStatEntry *b) {
        if (a.plays != b.plays) return a.plays > b.plays ? NSOrderedAscending : NSOrderedDescending;
        if (a.ms != b.ms) return a.ms > b.ms ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return [sorted subarrayWithRange:NSMakeRange(0, MIN(top, sorted.count))];
}

static void count(NSMutableDictionary<NSString *, SGStatEntry *> *entries, NSString *key, NSString *name, NSString *detail, SGPlay *play) {
    SGStatEntry *entry = entries[key];
    if (!entry) {
        entry = [SGStatEntry new];
        entry.name = name;
        entry.detail = detail;
        entries[key] = entry;
    }
    entry.plays++;
    entry.ms += play.ms;
}

// Tracks go by title and artist rather than URI: the basic export has no URIs, and a track's URI can
// differ between its single and its album.
SGStats *SGStatsSince(NSArray<SGPlay *> *plays, int64_t since, NSUInteger top) {
    NSMutableDictionary<NSString *, SGStatEntry *> *tracks = [NSMutableDictionary dictionary], *artists = [NSMutableDictionary dictionary],
                                                   *albums = [NSMutableDictionary dictionary];
    SGStats *stats = [SGStats new];
    for (SGPlay *play in plays) {
        if (play.end < since) continue;
        stats.plays++;
        stats.ms += play.ms;
        NSString *artist = play.artist.lowercaseString;
        count(tracks, keyOf(play), play.title, play.artist, play);
        count(artists, artist, play.artist, nil, play);
        if (play.album.length) count(albums, [NSString stringWithFormat:@"%@\x1f%@", play.album.lowercaseString, artist], play.album, play.artist, play);
    }
    stats.tracks = topOf(tracks, top);
    stats.artists = topOf(artists, top);
    stats.albums = topOf(albums, top);
    return stats;
}
