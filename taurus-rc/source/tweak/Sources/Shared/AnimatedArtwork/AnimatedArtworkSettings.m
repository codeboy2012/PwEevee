// The lock screen's ordered artwork views and whether moving-artwork downloads run in Low Data Mode.
// iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGSourcesPage.h"
#import "AnimatedArtwork.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"

static NSString *const kStarCanvas = @"canvas";
static NSString *const kStarLyrics = @"lyrics";
static NSString *const kStarFill = @"fill";
static NSString *const kStarDefault = @"default";
static NSString *const kStarColorful = @"colorful";

static BOOL starViewOrderContains(NSString *key) {
    return [SGLockScreenStarViewOrder() containsObject:key];
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();
        SGModRow *lyrics = SGSwitchRow(@"Show lock-screen lyrics",
            @"Allow the Lyrics view on the lock screen; turning this off keeps artwork and in-app lyrics",
            SGKeyLockScreenLyricsView);
        lyrics.changed = ^(BOOL on) {
            SGLockScreenStarEnsureView();
            SGLockScreenLyricsExclusivityChanged(SGEnabled(SGKeyLockScreenExclusiveLyrics));
        };
        SGModRow *style = SGChoiceRow(@"Lyrics style", @"Still draws each line once; Animated breathes the cover behind it",
                                      SGKeyLockScreenLyricsStyle, @[@"Still", @"Animated"], 0);
        style.visible = ^BOOL { return SGLockScreenLyricsViewEnabled() && starViewOrderContains(kStarLyrics); };
        SGModRow *exclusiveLyrics = SGSwitchRow(@"Automatically switch lyric styles",
            @"Turn off artist-name lyrics while lock-screen Lyrics is selected, and restore them when it is not",
            SGKeyLockScreenExclusiveLyrics);
        exclusiveLyrics.changed = ^(BOOL on) { SGLockScreenLyricsExclusivityChanged(on); };
        exclusiveLyrics.visible = ^BOOL { return SGLockScreenLyricsViewEnabled(); };
        SGModRow *star = SGOptionRow(@"Switch with the star", @"Cycle through the ordered lock-screen artwork views",
                                     SGKeyLockScreenStar);
        star.changed = ^(BOOL on) {
            if (!on) SGLockScreenStarEnsureView();
        };
        SGModRow *starViews = SGLockScreenStarViewsRow();
        SGModRow *lowData = SGOptionRow(@"Download in Low Data Mode", @"Moving artwork, up to about 7 MB a song", SGKeyMotionLowData);
        lowData.visible = ^BOOL { return starViewOrderContains(kStarCanvas); };
        SGModRow *coverSize = SGSliderRow(@"Fallback album art size",
            @"Every song's colourful cover-and-blur treatment, even when Canvas or animated covers are available",
            0.25, 0.85, 0.05,
            ^double { return SGLockScreenCoverArtworkScale(); },
            ^(double value) { SGSetInt(SGKeyLockScreenCoverArtworkScale, (NSInteger)lround(value * 100)); },
            ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; });
        coverSize.visible = ^BOOL { return starViewOrderContains(kStarColorful); };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        return @[
            starViews,
            lyrics,
            style,
            exclusiveLyrics,
            star,
            sources,
            lowData,
            coverSize,
        ];
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

SGModRow *SGLockScreenStarViewsRow(void) {
    SGModRow *row = SGPageRow(@"Full-screen artwork", ^UIViewController *{
        NSArray<SGSource *> *views = @[
            [SGSource sourceWithKey:kStarCanvas name:@"Canvas" detail:@"The track's Canvas or its Apple Music animated cover"],
            [SGSource sourceWithKey:kStarLyrics name:@"Lyrics" detail:SGLockScreenLyricsViewEnabled()
                ? @"Synced lyrics over the blurred album artwork" : @"Turn on Show lock-screen lyrics to use this view"],
            [SGSource sourceWithKey:kStarFill name:@"Fill" detail:@"The cover fading into progressively blurred artwork"],
            [SGSource sourceWithKey:kStarColorful name:@"Colourful" detail:@"Every Song: the custom moving-cover look, without source animations"],
            [SGSource sourceWithKey:kStarDefault name:@"Default" detail:@"iOS's full album artwork without an animated layer"],
        ];
        return SGSourcesPageMakeWithMinimumOnCount(@"Full-screen artwork",
            @"Drag to choose the order. The first available view is used when star cycling is off. Move a view below the line to disable it; keep at least one enabled.",
            views, ^NSArray<NSString *> *{ return SGLockScreenStarViewOrder(); },
            ^(NSArray<NSString *> *keys) {
                NSArray<NSString *> *order = keys.count ? keys : @[kStarDefault];
                [NSUserDefaults.standardUserDefaults setObject:order forKey:SGKeyLockScreenStarViews];
                SGLockScreenStarEnsureView();
            }, 1);
    });
    row.value = ^NSString *{
        NSArray<NSString *> *current = SGLockScreenAvailableStarViews();
        if (!current.count) return @"Default";
        if (SGHidden(SGKeyLockScreenStar) && current.count > 1) {
            NSString *selected = SGLockScreenCurrentStarView();
            NSUInteger index = selected ? [current indexOfObject:selected] : NSNotFound;
            if (index != NSNotFound)
                return [NSString stringWithFormat:@"%@ (%lu/%lu)", SGLockScreenStarViewName(selected),
                        (unsigned long)index + 1, (unsigned long)current.count];
        }
        NSString *first = SGLockScreenStarViewName(current.firstObject);
        return current.count == 1 ? first : [NSString stringWithFormat:@"%@ +%lu", first, (unsigned long)current.count - 1];
    };
    return SGWithSymbol(row, @"arrow.trianglehead.2.clockwise.rotate.90");
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(@"Full-screen artwork", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        NSString *message = [NSString stringWithFormat:@"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers and Fill can show there once the iPhone is updated.", UIDevice.currentDevice.systemVersion];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Needs iOS 26" message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
