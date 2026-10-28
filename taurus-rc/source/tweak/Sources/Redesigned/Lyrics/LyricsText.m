#import "Core/SGCore.h"
#import "LyricsText.h"

NSNotificationName const SGRLyricsTextDidChangeNotification = @"spotifyglass.redesign.lyricsTextDidChange";

static NSString *keyOf(SGRLyricsText text) {
    switch (text) {
        case SGRLyricsTextLyrics: return @"lyrics";
        case SGRLyricsTextPronunciation: return @"pronunciation";
        case SGRLyricsTextTranslation: return @"translation";
    }
    return nil;
}

NSString *SGRLyricsTextName(SGRLyricsText text) {
    switch (text) {
        case SGRLyricsTextLyrics: return @"Lyrics";
        case SGRLyricsTextPronunciation: return @"Pronunciation";
        case SGRLyricsTextTranslation: return @"Translation";
    }
    return nil;
}

// A stored order is taken only as a full set of the three; anything else is Apple Music's.
NSArray<NSNumber *> *SGRLyricsTextOrder(void) {
    NSArray<NSNumber *> *fallback = @[@(SGRLyricsTextLyrics), @(SGRLyricsTextPronunciation), @(SGRLyricsTextTranslation)];
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGRKeyLyricsTextOrder];
    if (![stored isKindOfClass:NSArray.class] || [stored count] != fallback.count) return fallback;
    NSMutableArray<NSNumber *> *order = [NSMutableArray array];
    for (id key in stored) {
        for (NSNumber *text in fallback) {
            if ([key isEqual:keyOf(text.integerValue)] && ![order containsObject:text]) [order addObject:text];
        }
    }
    return order.count == fallback.count ? order : fallback;
}

void SGRSetLyricsTextOrder(NSArray<NSNumber *> *order) {
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSNumber *text in order) [keys addObject:keyOf(text.integerValue)];
    [NSUserDefaults.standardUserDefaults setObject:keys forKey:SGRKeyLyricsTextOrder];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}

void SGRSetLyricsTextShown(SGRLyricsText text, BOOL shown) {
    SGSetEnabled(text == SGRLyricsTextTranslation ? SGRKeyLyricsTranslation : SGRKeyLyricsPronunciation, shown);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRLyricsTextDidChangeNotification object:nil];
}
