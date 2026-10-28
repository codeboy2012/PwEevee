#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"
#import "Redesigned/Player/Player.h"

UIViewController *SGRNowPlayingBarSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Now playing" intro:SGRestartNote sections:@[
        SGSection(nil, @[
            SGHideRow(@"Hide the device button", nil, SGRHideBarConnect),
        ]),
        SGSection(nil, @[
            SGSwitchRow(@"Moving background", nil, SGRKeyPlayerMotion),
        ]),
    ] footer:nil];
}

// The Mini player section on the redesign's Player page: Spotify's own flag for the bar moving in between
// the tabs as the page scrolls (the Apple Music style transition the section's footer describes).
NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    SGModRow *roundedArtwork = SGOptionRow(@"Rounded-square album art", @"Use rounded corners instead of a circle",
                                            SGRKeyNowPlayingRoundedArtwork);
    roundedArtwork.changed = ^(BOOL on) { SGRNowPlayingBarRefresh(); };
    SGModRow *progressThickness = SGSliderRow(@"Progress bar thickness", nil, 0, 5, 0.25,
        ^double {
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            return [defaults objectForKey:SGRKeyNowPlayingProgressThickness]
                ? [defaults doubleForKey:SGRKeyNowPlayingProgressThickness] : 2;
        },
        ^(double value) {
            [NSUserDefaults.standardUserDefaults setDouble:MIN(5, MAX(0, value)) forKey:SGRKeyNowPlayingProgressThickness];
            SGRNowPlayingBarRefresh();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%.2g pt", value]; });
    return @[
        roundedArtwork,
        progressThickness,
        SGFlagRow(@"Mini player transition animations", @"ios-feature-nowplaying.miniplayer_transition_animations"),
    ];
}
