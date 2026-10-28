// Clean shared links: the tracking Spotify adds to the open.spotify.com links it copies and shares, taken off.
// Foundation only, so it runs on whatever thread the share sheet asks on and in the Mac check
// (harness/clean-links).
//
// What goes is what says who shared the link and from where: si, nd, pt, context and every utm_. What the link
// opens stays: the path with its intl-xx/ segment, the fragment, and every other parameter in its order --
// t, above all, the second a shared episode starts at.
#import "Privacy.h"

static NSString *const kHost = @"open.spotify.com";

static BOOL isTracking(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower isEqualToString:@"si"] || [lower isEqualToString:@"nd"] || [lower isEqualToString:@"pt"] ||
           [lower isEqualToString:@"context"] || [lower hasPrefix:@"utm_"];
}

NSURL *SGCleanLinkURL(NSURL *url) {
    // The host checked before it is compared: a nil one would compare as the same.
    if (![url isKindOfClass:NSURL.class] || !url.host || [url.host caseInsensitiveCompare:kHost] != NSOrderedSame) return url;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    // The encoded items, so what is kept goes back byte for byte as it came.
    NSArray<NSURLQueryItem *> *items = parts.percentEncodedQueryItems;
    if (!items.count) return url;
    NSMutableArray<NSURLQueryItem *> *kept = [NSMutableArray array];
    for (NSURLQueryItem *item in items) {
        if (!isTracking(item.name)) [kept addObject:item];
    }
    if (kept.count == items.count) return url;
    // nil and not an empty list: an empty one leaves the "?" behind.
    parts.percentEncodedQueryItems = kept.count ? kept : nil;
    return parts.URL ?: url;
}

NSString *SGCleanLinksInText(NSString *text) {
    if (![text isKindOfClass:NSString.class] || [text rangeOfString:kHost options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return text;
    }
    // The detector rather than a pattern of its own: it knows where a link in a sentence ends, so a full stop
    // or a closing bracket after it is not read as the end of the last parameter and taken off with it.
    static NSDataDetector *detector;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL]; });
    NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSMutableString *cleaned = nil;
    // From the end, so the ranges still to come are where they were.
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        // The link as written, not the detector's reading of it, which puts a scheme on a bare host.
        NSString *written = [text substringWithRange:match.range];
        NSURL *url = [NSURL URLWithString:written];
        NSURL *clean = SGCleanLinkURL(url);
        if (!url || clean == url) continue;
        if (!cleaned) cleaned = [text mutableCopy];
        [cleaned replaceCharactersInRange:match.range withString:clean.absoluteString];
    }
    return cleaned ? [cleaned copy] : text;
}

id SGCleanLinkObject(id object) {
    if ([object isKindOfClass:NSURL.class]) return SGCleanLinkURL(object);
    if ([object isKindOfClass:NSString.class]) return SGCleanLinksInText(object);
    return object;
}
