// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Lyrics.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LyricsSources/LyricsSources.h"

SGModSection *SGLyricsSourcesSection(BOOL namingSource) {
    SGModRow *sources = SGPageRow(@"Sources", ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        // The first one asked and how many follow it, short enough to sit beside the title.
        NSArray<NSString *> *order = SGLyricsOrder();
        if (!order.count) return @"Off";
        NSString *first = SGLyricsProviderFor(order.firstObject).name;
        return order.count == 1 ? first : [NSString stringWithFormat:@"%@ +%lu", first, (unsigned long)order.count - 1];
    };
    SGModRow *imported = SGPageRow(@"Imported LRC files", ^UIViewController *{ return SGImportedLRCPage(); });
    imported.value = ^NSString *{
        NSUInteger count = SGImportedLRCFiles().count;
        return count ? @(count).stringValue : @"None";
    };
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources, imported,
        SGSwitchRow(@"Lyrics for every track", @"Even where Spotify has none", SGKeyLyricsAllTracks), nil];
    [rows addObject:SGSpicyLyricsKeyRow()];
    if (namingSource) [rows addObject:SGOptionRow(@"Show source", nil, SGKeyLyricsCredit)];
    if (SGEeveeLyricsOn()) {
        [rows addObject:SGOptionRow(@"Use these sources anyway", @"Only if EeveeSpotify's lyrics are really off", SGKeyLyricsBesideEevee)];
        return SGNotedSection(@"Sources", rows, @"EeveeSpotify's lyrics are on, so it answers Spotify's lyrics and these sources stay "
                                                @"off: both answering froze Spotify after launch. Turn its lyrics off in its own "
                                                @"settings to use these.");
    }
    return SGSection(@"Sources", rows);
}

SGModRow *SGLockScreenLyricsRow(void) {
    SGModRow *row = SGSwitchRow(@"Lock screen lyrics", @"Current line in place of the artist", SGKeyLockScreenLyrics);
    row.changed = ^(BOOL on) { SGLockScreenArtistLyricsChanged(on); };
    return row;
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(@"Translation language", nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.choiceFooter = @"Used when the lyrics come with translations. Any shows the first.";
    return row;
}

// Only the redesign's lyrics view sweeps words.
SGModRow *SGLyricsWordTimingRow(void) {
    return SGOptionRow(@"Simulate word timing", nil, SGKeyLyricsSimulateWords);
}

// Only the redesign's lyrics view draws it, and every one there is redrawn as the switch flips.
SGModRow *SGLyricsRomanisedRow(void) {
    SGModRow *row = SGOptionRow(@"Romanized lyrics", @"Lines in other alphabets, again in Latin letters", SGKeyLyricsRomanised);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    };
    return row;
}

// Read wherever lines are timed, so it applies as the thumb moves.
SGModRow *SGLyricsDelayRow(void) {
    return SGSliderRow(@"Delay", nil, 0, 1000, 25, ^double { return SGKaraokeDelayMs(); },
                       ^(double value) { SGSetInt(SGKeyLyricsDelay, lround(value)); },
                       ^NSString *(double value) { return [NSString stringWithFormat:@"%ld ms", lround(value)]; });
}
