#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGNotedSection(@"Header", @[
            SGSwitchRow(@"Animated cover", @"Apple Music's, where the album has one", SGRKeyAnimatedCovers),
        ], @"Apple Music gets only the artist and album name. Nothing is downloaded in Low Data or Low Power Mode."),
        SGNotedSection(@"Track list", @[
            SGHideRow(@"Hide album artists", @"Featured artists stay visible", SGRKeyHideAlbumArtists),
            SGHideRow(@"Hide all track artists", @"Including featured artists", SGRKeyHideAllAlbumArtists),
            SGHideRow(@"Hide explicit tags", @"Next to track artists", SGRKeyHideExplicitAlbumTags),
        ], nil),
    ];
    return [[SGModPage alloc] initWithTitle:@"Albums" intro:nil sections:sections footer:nil];
}
