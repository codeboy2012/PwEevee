#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlaying.h"

NSArray<SGModSection *> *SGNativePlayerScreenSections(void) {
    return @[
        SGSection(@"Player screen", @[
            SGOptionRow(@"Artwork background", nil, SGKeyPlayerBackdrop),
            SGOptionRow(@"Glass header buttons", nil, SGKeyPlayer),
            SGKillRow(@"Disable Canvas", @"ios-feature-canvas.canvas_enabled"),
            SGFlagRow(@"Sheet style player", @"ios-feature-nowplaying.sheet_style_npv"),
            SGFlagRow(@"Redesigned header", @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled"),
            SGFlagRow(@"New progress slider", @"ios-feature-encoreexperiments.new_npv_slider_enabled"),
            SGFlagRow(@"Expand the sticky header on tap", @"ios-feature-nowplaying.expand_sticky_header_on_tap"),
        ]),
        SGSection(@"Hide cards below the player", @[
            SGHideRow(@"Lyrics", nil, SGHideLyricsCard),
            SGHideRow(@"About the artist", nil, SGHideAboutArtist),
            SGHideRow(@"Related videos", nil, SGHideRelatedVideos),
            SGHideRow(@"SongDNA", nil, SGHideSongDNA),
            SGHideRow(@"Live events", nil, SGHideLiveEvents),
            SGHideRow(@"Explore the artist", nil, SGHideExploreArtist),
            SGHideRow(@"Credits", nil, SGHideCredits),
            SGHideRow(@"Merch", nil, SGHideMerch),
            SGHideRow(@"Recommendations", nil, SGHideRecommendations),
        ]),
        SGSection(@"Hide on the player", @[
            SGHideRow(@"Lyrics preview", nil, SGHideLyricsInline),
            SGHideRow(@"Shuffle", nil, SGHideShuffle),
            SGHideRow(@"Repeat", nil, SGHideRepeat),
            SGHideRow(@"Add to playlist", nil, SGHideAddTo),
            SGHideRow(@"Queue", nil, SGHideQueue),
            SGHideRow(@"Share", nil, SGHideShare),
            SGHideRow(@"Connect to a device", nil, SGHideConnect),
        ]),
    ];
}

SGModRow *SGGlassLyricsRow(void) {
    return SGOptionRow(@"Glass lyrics", nil, SGKeyLyricsCard);
}

UIViewController *SGQueueSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Queue & devices" intro:SGRestartNote sections:@[
        SGSection(@"Bottom sheets", @[
            SGFlagRow(@"Queue as a bottom sheet", @"ios-feature-nowplaying.bottom_sheet_queue_enabled"),
            SGFlagRow(@"Connect as a bottom sheet", @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet"),
            SGFlagRow(@"Connect sheet from the video switcher", @"ios-playbackcontrol-audiovideoswitcher-impl.enable_connect_bottom_sheet"),
        ]),
        SGSection(@"Queue", @[
            SGFlagRow(@"Queue flip transition", @"ios-feature-nowplaying.queue_flip_transition_enabled"),
            SGFlagRow(@"Play next in the context menu", @"ios-feature-queue.is_play_next_context_menu_enabled"),
        ]),
    ] footer:nil];
}
