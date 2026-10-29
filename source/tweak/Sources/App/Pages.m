#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Shared/AlphaIndex/AlphaIndex.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Concerts/Concerts.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/Lossless/SGLossless.h"
#import "Shared/Player/PlayerSettings.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Kit/SGRAccent.h"

NSString *const SGRedesignedUIInfo = @"PwEevee's redesigned look, leaning towards Apple Music's style. It is not compatible with the legacy look's settings.\n\nThe legacy look gives you more freedom, yet still looks like Spotify.";
NSNotificationName const SGSidebarBadgeTextDidChangeNotification = @"spotifyglass.sidebarBadgeTextDidChange";

static NSString *sidebarBadgeText(void) {
    NSString *text = [NSUserDefaults.standardUserDefaults stringForKey:SGKeySidebarBadgeText];
    return text;
}

static SGModRow *sidebarBadgeTextRow(void) {
    SGModRow *row = SGStatActionRow(@"Sidebar badge text", @"Change the text shown in Spotify's sidebar badge",
        ^NSString *{ return sidebarBadgeText(); }, ^{
            UIViewController *top = SGTopController();
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sidebar badge text"
                message:@"Leave the field empty to keep Spotify's own badge." preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
                field.text = sidebarBadgeText();
                field.clearButtonMode = UITextFieldViewModeWhileEditing;
                field.returnKeyType = UIReturnKeyDone;
            }];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (text.length) [NSUserDefaults.standardUserDefaults setObject:text forKey:SGKeySidebarBadgeText];
                else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySidebarBadgeText];
                [NSNotificationCenter.defaultCenter postNotificationName:SGSidebarBadgeTextDidChangeNotification object:nil];
            }]];
            [top presentViewController:alert animated:YES completion:nil];
        });
    row.refreshOn = SGSidebarBadgeTextDidChangeNotification;
    return SGWithSymbol(row, @"tag");
}

void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
}

static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Spotify"
        message:on ? @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it." : @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *unavailableRow(void) {
    SGModRow *row = SGStatActionRow(@"Redesigned UI", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Redesigned UI"
            message:[NSString stringWithFormat:@"The redesign is built on Liquid Glass, which iOS 26 draws and no earlier version can. This phone runs iOS %@, so the mod gives you its legacy look instead: Spotify's own screens with everything else the mod adds on them.", UIDevice.currentDevice.systemVersion]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    return SGWithSymbol(row, @"sparkles");
}

UIViewController *SGAppearanceSettingsPage(void) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    if (!SGRedesignAvailable()) {
        [rows addObject:unavailableRow()];
        [rows addObjectsFromArray:SGNativeAppearanceRows()];
    } else {
        SGModRow *redesign = SGOptionRow(@"Redesigned UI", nil, SGKeyRedesign);
        redesign.glows = YES;
        redesign.info = SGRedesignedUIInfo;
        redesign.changed = ^(BOOL on) {
            SGSetRedesignedUI(on);
            offerRestart(on);
        };
        [rows addObject:SGWithSymbol(redesign, @"sparkles")];
        if (SGRedesignedUIStored()) {
            [rows addObjectsFromArray:SGRAppearanceRows()];
            [rows addObject:SGRHomeStyleRow()];
            [rows addObject:SGRHomeTopPicksRow()];
        } else {
            [rows addObjectsFromArray:SGNativeAppearanceRows()];
        }
        [rows addObjectsFromArray:SGAppFontRows()];
    }
    [rows addObject:sidebarBadgeTextRow()];
    SGModSection *section = SGNotedSection(nil, rows, @"Some changes apply after you restart Spotify.");
    return [[SGModPage alloc] initWithTitle:@"Appearance" intro:nil sections:@[section] footer:nil];
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

// Pronunciation, translation, word sweeping and line meanings exist only in the redesign's lyrics.
UIViewController *SGLyricsSettingsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGLyricsSourcesSection(redesigned)];
    if (redesigned) {
        SGModRow *landscape = SGSwitchRow(@"Landscape lyrics", @"Show lyrics beside the player controls", SGRKeyLandscapeLyrics);
        landscape.changed = ^(BOOL on) { SGRPlayerLyricsOrientationChanged(); };
        [sections addObject:SGSection(@"Display", @[landscape,
            SGLyricsWordTimingRow(), SGLyricsRomanisedRow(), SGLyricsDelayRow(),
            SGRLyricsTextSizesRow(), SGLyricsTranslationLanguageRow(), SGLyricsMeaningsRow(), SGLyricsMeaningMarkersRow()])];
        [sections addObject:SGSection(@"Translation", @[SGTranslateEverySongRow(), SGGeminiKeyRow(), SGSavedTranslationsRow()])];
    }
    [sections addObject:SGSection(nil, more)];
    // The redesign's page leads with a live preview of the lyrics, a glass pill to search the song it plays,
    // the presets and the sliders and font behind the Adjust button; every change applies to the app's lyrics at once.
    if (redesigned) return SGRLyricsSettingsPage(@"Lyrics", SGRestartNote, sections);
    return [[SGModPage alloc] initWithTitle:@"Lyrics" intro:SGRestartNote sections:sections footer:nil];
}

UIViewController *SGPlayerSettingsPage(void) {
    SGModRow *blocked = SGPageRow(@"Blocked artists", ^UIViewController *{ return SGArtistBlockSettingsPage(); });
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : @"Off";
    };
    BOOL native = !SGRedesignedUIStored();

    // AirPods gestures has its own row on the Mod Settings root, so it is not repeated here.
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        SGWithSymbol(SGPageRow(@"Gestures", ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap"),
        SGWithSymbol(blocked, @"person.crop.circle.badge.xmark"),
    ])];
    NSMutableArray<SGModRow *> *pages = [NSMutableArray array];
    if (native) {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing bar", ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
        [pages addObject:SGWithSymbol(SGPageRow(@"Queue & devices", ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward")];
    } else {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing", ^UIViewController *{ return SGRNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
    }
    [sections addObject:SGSection(nil, pages)];
    // Playlists and artist pages: the alphabet index works with either look, the concerts card is the redesign's.
    NSMutableArray<SGModRow *> *browsing = [NSMutableArray arrayWithObject:SGWithSymbol(SGAlphaIndexRow(), @"textformat.abc")];
    if (!native) {
        [browsing addObject:SGWithSymbol(SGSwitchRow(@"Upcoming concerts", @"Show an artist's tour dates under their name", SGKeyConcerts), @"ticket")];
    }
    [sections addObject:SGNotedSection(@"Browsing", browsing, @"Applies after you restart Spotify.")];
    [sections addObject:SGNotedSection(@"Lossless", @[
        SGOptionRow(@"Lossless files", @"Play matching FLAC or ALAC files instead of Spotify's stream", SGKeyLossless),
    ], @"Put matching files in Files › Spotify › Lossless. Applies after you restart Spotify.")];
    if (!native) return SGRPlayerSettingsPage(sections);
    if (native) [sections addObjectsFromArray:SGNativePlayerScreenSections()];
    return [[SGModPage alloc] initWithTitle:@"Player" intro:SGRestartNote sections:sections footer:nil];
}
