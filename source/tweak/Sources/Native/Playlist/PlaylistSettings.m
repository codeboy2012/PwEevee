#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Playlists" intro:nil sections:@[
        SGSection(@"Header", @[
            SGOptionRow(@"Artwork background", nil, SGKeyPlaylistBackdrop),
        ]),
        SGSection(@"Hide in the playlist header", @[
            SGHideRow(@"Cover artwork", nil, SGHidePlaylistArtwork),
            SGHideRow(@"Description", nil, SGHidePlaylistDescription),
            SGHideRow(@"Creator and collaborators", nil, SGHidePlaylistCreator),
            SGHideRow(@"Length and saves", nil, SGHidePlaylistLength),
        ]),
        SGSection(@"Hide playlist buttons", @[
            SGHideRow(@"Video", nil, SGHidePlaylistVideo),
            SGHideRow(@"Add to library", nil, SGHidePlaylistAddTo),
            SGHideRow(@"Download", nil, SGHidePlaylistDownload),
            SGHideRow(@"Share", nil, SGHidePlaylistShare),
            SGHideRow(@"More", nil, SGHidePlaylistMore),
        ]),
        SGSection(@"Hide above the tracks", @[
            SGHideRow(@"Curation pills", nil, SGHidePlaylistPills),
            SGHideRow(@"Find and sort bar", nil, SGHidePlaylistFind),
        ]),
    ] footer:nil];
}
