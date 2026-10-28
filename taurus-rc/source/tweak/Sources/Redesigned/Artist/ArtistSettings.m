// The redesign's artist page settings.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Artist.h"

UIViewController *SGRArtistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Artists" intro:SGRestartNote sections:@[
        SGNotedSection(@"Apple Music", @[
            SGSwitchRow(@"Artist logos", @"In place of the name when a logo is available", SGRKeyArtistLogo),
        ], @"Only the artist's name is sent to Apple Music."),
    ] footer:nil];
}
