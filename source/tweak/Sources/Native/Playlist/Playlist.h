// Playlist: parts of the playlist page hidden one switch each (Playlist.x). An unset switch is off.
#import <UIKit/UIKit.h>

#define SGHidePlaylistArtwork @"spotifyglass.hide.playlistArtwork"
#define SGHidePlaylistDescription @"spotifyglass.hide.playlistDescription"
#define SGHidePlaylistCreator @"spotifyglass.hide.playlistCreator"
#define SGHidePlaylistLength @"spotifyglass.hide.playlistLength"
#define SGHidePlaylistVideo @"spotifyglass.hide.playlistVideo"
#define SGHidePlaylistAddTo @"spotifyglass.hide.playlistAddTo"
#define SGHidePlaylistDownload @"spotifyglass.hide.playlistDownload"
#define SGHidePlaylistShare @"spotifyglass.hide.playlistShare"
#define SGHidePlaylistMore @"spotifyglass.hide.playlistMore"
#define SGHidePlaylistPills @"spotifyglass.hide.playlistPills"
#define SGHidePlaylistFind @"spotifyglass.hide.playlistFind"
#define SGKeyPlaylistBackdrop @"spotifyglass.playlistBackdrop"

UIViewController *SGPlaylistSettingsPage(void);   // opened from the Home & Library page
