// Album redesign: whether a track row's artist line says anything the album's header does not. Foundation only,
// so the Mac check in harness/album-credits runs it as the tweak does.
//
// The line is redundant in two cases only: it is the album's artist again, or it is the album's artist and the
// guests the title already names after a featured-artist marker. Everything else keeps its line -- a compilation,
// a different guest, guests in another order, a guest named in the title with no marker -- because a line hidden
// wrongly takes away who is on the track, and a line kept wrongly costs only the clutter.
#import <Foundation/Foundation.h>

// Canonical composition, lower case, and any run of white space as one space: what two spellings of the same
// credit can differ by. Accents stay, and names are never split at "&", "/" or " x ".
static NSString *normalised(NSString *text) {
    NSString *folded = text.precomposedStringWithCanonicalMapping.lowercaseString;
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in [folded componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (word.length) [words addObject:word];
    }
    return [words componentsJoinedByString:@" "];
}

// The guests a title names at its very end: "(feat. A)", "[ft B]", "- with C", and featuring the same way.
static NSString *featuredIn(NSString *title) {
    static NSRegularExpression *suffix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *marker = @"(?:feat\\.?|ft\\.?|featuring|with)\\s+";
        NSString *pattern = [NSString stringWithFormat:@"(?:\\(\\s*%@([^()]+?)\\s*\\)|\\[\\s*%@([^\\[\\]]+?)\\s*\\]|\\s-\\s%@(.+?))$",
                             marker, marker, marker];
        suffix = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    });
    NSTextCheckingResult *match = [suffix firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    for (NSUInteger i = 1; match && i < match.numberOfRanges; i++) {
        NSRange range = [match rangeAtIndex:i];
        if (range.location != NSNotFound) return [title substringWithRange:range];
    }
    return nil;
}

BOOL SGRCreditRepeatsAlbum(NSString *albumArtist, NSString *rowArtist, NSString *title) {
    if (!albumArtist.length || !rowArtist.length) return NO;
    // The header joins co-artists with " • ", a row with ", ".
    NSString *album = [normalised(albumArtist) stringByReplacingOccurrencesOfString:@" • " withString:@", "];
    NSString *row = normalised(rowArtist);
    if (!album.length) return NO;
    if ([row isEqualToString:album]) return YES;
    NSString *lead = [album stringByAppendingString:@", "];
    if (![row hasPrefix:lead] || row.length == lead.length || !title.length) return NO;
    NSString *guests = [row substringFromIndex:lead.length];
    NSString *featured = featuredIn(normalised(title));
    return featured && [normalised(featured) isEqualToString:guests];
}
