// The native look's lyrics for a local file with an imported LRC file linked to it (Shared/LocalFiles/
// LocalLyrics.h): Spotify turns its own lyrics off for local files before it asks its lyrics service,
// so the player's footer gets a button of the mod's that opens a page of its own.
//
//     LocalLyricsButton.x   the button on the footer, and has_lyrics for a linked local file
//     LocalLyricsPage.m     the page: the lines on black, following the song
#import <UIKit/UIKit.h>

// The page for whatever plays, full screen.
UIViewController *SGLocalLyricsPage(void);
