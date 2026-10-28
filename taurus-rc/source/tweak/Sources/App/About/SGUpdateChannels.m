// The channel model the header documents: where the setting lives, how a release is
// sorted into a channel, and how two versions order. All Foundation, no UIKit, so the
// Mac-side test tool can compile it beside the tweak and pin the rules down at name.
#import "SGUpdateChannels.h"

// The channel choice is one key, so a future backup/restore carries a single
// self-explanatory entry. The per-channel caches share the spotifyglass.update prefix
// the rest of the check already uses, one namespace apiece, and stay apart.
static NSString *const kChoice = @"spotifyglass.update.channel";
static NSString *const kReleasesKeys[3] = {
    @"spotifyglass.update.releases.stable",
    @"spotifyglass.update.releases.nightly",
    @"spotifyglass.update.releases.alpha",
};
static NSString *const kCheckedKeys[3] = {
    @"spotifyglass.update.checked.stable",
    @"spotifyglass.update.checked.nightly",
    @"spotifyglass.update.checked.alpha",
};

NSString *SGUpdateChannelTitle(SGUpdateChannel channel) {
    switch (channel) {
        case SGUpdateChannelNightly: return @"Nightly";
        case SGUpdateChannelAlpha:   return @"Alpha";
        case SGUpdateChannelStable:
        default:                     return @"Stable";
    }
}

NSString *SGUpdateChannelDetail(SGUpdateChannel channel) {
    switch (channel) {
        case SGUpdateChannelNightly:
            return @"Development builds. Newer than stable, less tested, and bugs and regressions are still possible.";
        case SGUpdateChannelAlpha:
            return @"Experimental builds. The earliest and most frequent updates, and the likeliest to be rough.";
        case SGUpdateChannelStable:
        default:
            return @"Tested releases for everyone. Updates less often, and still not promised to be bug-free.";
    }
}

// Nothing unknown may stand as a channel: a defaults file written by hand, or a value
// some other version renamed, reads back as Stable rather than as nonsense.
SGUpdateChannel SGUpdateChannelNow(void) {
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:kChoice];
    if ([stored isKindOfClass:NSString.class]) {
        for (NSInteger channel = SGUpdateChannelStable; channel <= SGUpdateChannelAlpha; channel++)
            if ([SGUpdateChannelTitle((SGUpdateChannel)channel) caseInsensitiveCompare:stored] == NSOrderedSame)
                return (SGUpdateChannel)channel;
    }
    return SGUpdateChannelStable;   // new installs, and anything unreadable, sit on Stable
}

void SGUpdateChannelSelect(SGUpdateChannel channel) {
    if (channel < SGUpdateChannelStable || channel > SGUpdateChannelAlpha) return;
    [[NSUserDefaults standardUserDefaults] setObject:SGUpdateChannelTitle(channel) forKey:kChoice];
}

#pragma mark - the version rules

// The version rules the header writes down, in code. "0.14.1" against "0.15": the
// numbers position by position, a missing one counting zero. Beyond the numbers, what
// follows the first dash is the identifier list, and a release line outranks its own
// pre-releases, whose identifiers rank nightly < alpha < beta < pre < rc, with a
// number riding an identifier counting up and a plain number outranking any name
// (the semver rule). So 0.14.1 < 0.15, and 2.2.0-pre < 2.2.0, and
// 3.1.0-alpha.1 > 3.1.0-nightly.2.
//
// The parsed shape: the line is the digits, the tokens are the identifiers after the
// first dash, each packed as (rank << 40) | number, so alpha.2 sorts past alpha.1 and
// "2" sorts past "alpha" with one comparison apiece. A rank of 6 marks a plain number.
static const unsigned long long SGPreNightly = 1;
static const unsigned long long SGPreAlpha   = 2;
static const unsigned long long SGPreBeta    = 3;
static const unsigned long long SGPrePre     = 4;
static const unsigned long long SGPreRC      = 5;
static const unsigned long long SGPreNumber  = 6;

typedef struct {
    unsigned long long line[8];     // 2, 2, 0 for "v2.2.0-pre"
    NSInteger lineCount;
    BOOL pre;                       // carries an identifier list at all
    unsigned long long token[8];    // (rank << 40) | number
    NSInteger tokenCount;
} SGVer;

static BOOL SGAllDigits(NSString *text) {
    if (!text.length) return NO;
    return [[text stringByTrimmingCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]] isEqualToString:@""];
}

static unsigned long long SGDigitsValue(NSString *text) {
    unsigned long long value = 0;
    for (NSUInteger i = 0; i < text.length; i++)
        value = value * 10 + ([text characterAtIndex:i] - '0');
    return value;
}

// One identifier piece: "alpha", "2", or a name with its number riding along. YES for
// any of those, NO for an identifier nobody placed (a token, then, that nothing may
// count on).
static BOOL SGToken(NSString *piece, unsigned long long *packed) {
    if ([piece isEqualToString:@"nightly"]) { *packed = SGPreNightly << 40; return YES; }
    if ([piece isEqualToString:@"alpha"])   { *packed = SGPreAlpha   << 40; return YES; }
    if ([piece isEqualToString:@"beta"])    { *packed = SGPreBeta    << 40; return YES; }
    if ([piece isEqualToString:@"pre"])     { *packed = SGPrePre     << 40; return YES; }
    if ([piece isEqualToString:@"rc"])      { *packed = SGPreRC      << 40; return YES; }
    if (SGAllDigits(piece)) { *packed = (SGPreNumber << 40) | SGDigitsValue(piece); return YES; }
    // A name with its number riding along: "alpha2" or "rc11". The longest name the
    // head matches wins the read, and the tail must be all digits.
    for (NSUInteger cut = piece.length; cut > 0; cut--) {
        NSString *head = [piece substringToIndex:cut];
        NSString *tail = [piece substringFromIndex:cut];
        unsigned long long rank = 0;
        if      ([head isEqualToString:@"nightly"]) rank = SGPreNightly;
        else if ([head isEqualToString:@"alpha"])   rank = SGPreAlpha;
        else if ([head isEqualToString:@"beta"])    rank = SGPreBeta;
        else if ([head isEqualToString:@"pre"])     rank = SGPrePre;
        else if ([head isEqualToString:@"rc"])      rank = SGPreRC;
        if (rank) {
            if (tail.length && SGAllDigits(tail)) { *packed = (rank << 40) | SGDigitsValue(tail); return YES; }
            return NO;   // letters after a recognized name are spelling nobody placed
        }
    }
    return NO;
}

// "v2.2.0-pre", "2.2.0-alpha.2", "nightly-2026.10.25" -- every shape a channel tag may
// take. NO means the version compares as nothing instead of as a guess: a release the
// reader cannot parse is never claimed as newer.
static BOOL SGVerParse(NSString *text, SGVer *out) {
    if (!(text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) || !text.length) return NO;
    NSString *string = [text lowercaseString];
    if ([string hasPrefix:@"v"]) string = [string substringFromIndex:1];
    // A nightly tag may lead with its own word ("nightly-2026.10.25"); the leading
    // non-digits and the dash they end at are naming, not version, and lose.
    NSRange firstDigit = [string rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]];
    if (firstDigit.location == NSNotFound) return NO;
    if (firstDigit.location > 0) {
        NSString *before = [string substringToIndex:(NSUInteger)firstDigit.location];
        if (![before hasSuffix:@"-"]) return NO;
        string = [string substringFromIndex:(NSUInteger)firstDigit.location];
    }
    NSRange dash = [string rangeOfString:@"-"];
    NSString *line  = dash.location == NSNotFound ? string : [string substringToIndex:(NSUInteger)dash.location];
    NSString *ident = dash.location == NSNotFound ? @""      : [string substringFromIndex:(NSUInteger)NSMaxRange(dash)];

    NSMutableArray<NSNumber *> *pieces = [NSMutableArray array];
    for (NSString *piece in [line componentsSeparatedByString:@"."]) {
        if (!piece.length) continue;
        if (pieces.count >= 8) return NO;               // more line pieces than fit: not a version
        if (!SGAllDigits(piece)) return NO;             // "0-pre" in the line is not a line
        [pieces addObject:@(SGDigitsValue(piece))];
    }
    if (!pieces.count) return NO;
    out->lineCount = (NSInteger)pieces.count;
    for (NSInteger i = 0; i < out->lineCount; i++)
        out->line[(NSUInteger)i] = pieces[(NSUInteger)i].unsignedLongLongValue;

    out->pre = NO;
    out->tokenCount = 0;
    if (!ident.length) return YES;                      // no dash at all, or a bare trailing "-"
    out->pre = YES;                                     // "2.2.0-" carries a blank identifier list
    for (NSString *piece in [ident componentsSeparatedByString:@"."]) {
        if (!piece.length) continue;
        if (out->tokenCount >= 8) break;                // more identifiers than fit: drop the tail
        unsigned long long packed = 0;
        if (!SGToken(piece, &packed)) return NO;
        out->token[(NSUInteger)out->tokenCount++] = packed;
    }
    return YES;
}

static NSComparisonResult SGVerCompare(SGVer *a, SGVer *b) {
    NSInteger top = MAX(a->lineCount, b->lineCount);
    for (NSInteger i = 0; i < top; i++) {
        unsigned long long left  = i < a->lineCount ? a->line[(NSUInteger)i] : 0;
        unsigned long long right = i < b->lineCount ? b->line[(NSUInteger)i] : 0;
        if (left != right) return left > right ? NSOrderedDescending : NSOrderedAscending;
    }
    // The release beats its own pre-releases; one of them carrying a list decides.
    if (a->pre != b->pre) return a->pre ? NSOrderedAscending : NSOrderedDescending;
    // Identifiers position by position; a prefix run counts as the run without the
    // identifier being older -- "alpha" < "alpha.1".
    NSInteger topTokens = MAX(a->tokenCount, b->tokenCount);
    for (NSInteger i = 0; i < topTokens; i++) {
        BOOL outOfA = i >= a->tokenCount;
        BOOL outOfB = i >= b->tokenCount;
        if (outOfA != outOfB) return outOfA ? NSOrderedAscending : NSOrderedDescending;
        if (a->token[(NSUInteger)i] != b->token[(NSUInteger)i])
            return a->token[(NSUInteger)i] > b->token[(NSUInteger)i] ? NSOrderedDescending : NSOrderedAscending;
    }
    return NSOrderedSame;
}

BOOL SGVersionIsPrerelease(NSString *version) {
    SGVer parsed;
    if (!SGVerParse(version, &parsed)) return NO;
    return parsed.pre;
}

NSComparisonResult SGVersionCompare(NSString *a, NSString *b) {
    SGVer left, right;
    if (!SGVerParse(a, &left) || !SGVerParse(b, &right)) {
        // Something is unreadable on one side. The comparison did not happen, so no
        // order may be claimed: nothing is newer by default, whatever the strings say.
        return NSOrderedSame;
    }
    return SGVerCompare(&left, &right);
}

#pragma mark - which channel a release reaches

NSArray<NSString *> *SGUpdateChannelBucketNames(void) {
    return @[@"stable", @"nightly", @"alpha"];
}

// A GitHub Releases reply into buckets. The tag decides, and the title is never a
// channel signal: the live release list has been seen putting an upstream component's
// version (" SpoTi.pw 0.22.0-alpha.2 ...") into v2.2.0-pre's title and "SpoTi.pw
// v0.23.0-beta" into v1.0.2's; titles that name channels would route those releases
// wrong. The explicit channel identifier is read first, so a release whose tag names
// alpha or nightly is answered before the version rules get a chance to read the same
// word as a pre-release hint.
NSInteger SGUpdateChannelFor(BOOL draft, BOOL prerelease, NSString *tag, NSString *title __attribute__((unused))) {
    if (draft) return NSNotFound;
    NSString *tagText = [(tag ?: @"") lowercaseString];
    if ([tagText containsString:@"alpha"])   return SGUpdateChannelAlpha;
    if ([tagText containsString:@"nightly"]) return SGUpdateChannelNightly;
    // A tag that reads as nothing is a release no channel may answer for.
    SGVer parsed;
    if (!SGVerParse(tagText, &parsed)) return NSNotFound;
    // -pre, -beta, -rc are test builds for their own table: no channel hands them out.
    if (prerelease || parsed.pre) return NSNotFound;
    return SGUpdateChannelStable;
}

static NSString *SGStringOr(id value, NSString *fallback) {
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

NSDictionary *SGUpdateChannelsFromReleasesJSON(NSData *data) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:NSArray.class]) return nil;
    NSArray<NSString *> *names = SGUpdateChannelBucketNames();
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *buckets = [NSMutableDictionary dictionary];
    for (id item in (NSArray *)json) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *release = item;
        NSString *tag = SGStringOr(release[@"tag_name"], nil);
        if (!tag.length) continue;                       // a release without a tag is not one
        NSInteger channel = SGUpdateChannelFor([release[@"draft"] boolValue],
                                               [release[@"prerelease"] boolValue],
                                               tag, SGStringOr(release[@"name"], nil));
        if (channel == NSNotFound) continue;
        NSMutableArray *bucket = buckets[names[(NSUInteger)channel]];
        if (!bucket) bucket = buckets[names[(NSUInteger)channel]] = [NSMutableArray array];
        [bucket addObject:@{
            @"version": [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag,
            @"notes": SGStringOr(release[@"body"], @""),
            @"date": SGStringOr(release[@"published_at"], @""),
            @"url": SGStringOr(release[@"html_url"], @""),
        }];
    }
    // Newest first, and among versions that tie the order GitHub published in stands.
    for (NSString *name in buckets.allKeys) {
        NSMutableArray *bucket = buckets[name];
        NSMutableArray<NSDictionary *> *indexed = [NSMutableArray array];
        [bucket enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger i, BOOL *stop __attribute__((unused))) {
            [indexed addObject:@{ @"entry": entry, @"at": @(i) }];
        }];
        [indexed sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            // sortUsingComparator orders ascending, so a "newer first" bucket is a reversed
            // version compare -- and for ties, a reversed index compare, which stands the
            // later-published entry ahead.
            NSComparisonResult order = SGVersionCompare(a[@"entry"][@"version"], b[@"entry"][@"version"]);
            if (order != NSOrderedSame) return order == NSOrderedDescending ? NSOrderedAscending : NSOrderedDescending;
            return [b[@"at"] compare:a[@"at"]];
        }];
        [bucket removeAllObjects];
        for (NSDictionary *indexedEntry in indexed) [bucket addObject:indexedEntry[@"entry"]];
    }
    return buckets;
}

#pragma mark - each channel keeps its own answer

NSArray<NSDictionary *> *SGUpdateChannelStoredList(SGUpdateChannel channel) {
    if (channel < SGUpdateChannelStable || channel > SGUpdateChannelAlpha) return nil;
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:kReleasesKeys[(NSUInteger)channel]];
    return [stored isKindOfClass:NSArray.class] ? stored : nil;
}

NSTimeInterval SGUpdateChannelCheckedAt(SGUpdateChannel channel) {
    if (channel < SGUpdateChannelStable || channel > SGUpdateChannelAlpha) return 0;
    return [[NSUserDefaults standardUserDefaults] doubleForKey:kCheckedKeys[(NSUInteger)channel]];
}

void SGUpdateChannelStoreList(SGUpdateChannel channel, NSArray<NSDictionary *> *list) {
    if (channel < SGUpdateChannelStable || channel > SGUpdateChannelAlpha) return;
    NSUserDefaults *store = [NSUserDefaults standardUserDefaults];
    if (list.count) [store setObject:list forKey:kReleasesKeys[(NSUInteger)channel]];
    else [store removeObjectForKey:kReleasesKeys[(NSUInteger)channel]];   // an empty answer is the absence of the key
}

void SGUpdateChannelNoteChecked(SGUpdateChannel channel) {
    if (channel < SGUpdateChannelStable || channel > SGUpdateChannelAlpha) return;
    [[NSUserDefaults standardUserDefaults] setDouble:NSDate.date.timeIntervalSince1970 forKey:kCheckedKeys[(NSUInteger)channel]];
}
