// EeveeSpotify, brought into Mod Settings.
//
// The Eevee payload is compiled (Evevee Spotify/component/), so its own settings page can neither be
// edited nor told to hide sections. What it stores, it stores in Spotify's NSUserDefaults under plain
// keys (patchType, darkPopUps, experimentsOptions, sponsorBlockOptions, ...), so this file drives those
// keys directly and presents them as the mod's own rows (Settings/SGModPage.h). Lyrics belong to the
// payload: its rewriter and Shared/LyricsSources hook the same color-lyrics response, and Eevee's own
// stored choice decides which one runs.
#import <UIKit/UIKit.h>

// The EeveeSpotify page, built from the mod's own rows over Eevee's own stored settings.
UIViewController *SGEeveeSpotifyPage(void);

// The app icon picker, over the same icons (the 142 PNGs at the app root) and the same stored key
// (EeveeSelectedAppIconName) the payload's own picker reads and writes.
UIViewController *SGEeveeIconsPage(void);

// Takes the standalone EeveeSpotify row the payload injects above Spotify's settings list out, undoes
// the 68pt top inset it added, and leaves a hidden stand-in with the same tag (1338), which the
// payload's own injection guard reads as "already there" so the row never comes back.
void SGEeveeRemoveStandaloneRow(UICollectionView *list);

// Takes the payload's gear button (tag 1337) out of a navigation bar's items, for the hooks that own
// the bars it lands on. Returns the items unchanged when the button is not among them.
NSArray *SGEeveeFilteredBarItems(NSArray *items);

// Undoes the lyrics off-switch the old integration lock wrote (lyricsSource = 4, its notReplaced):
// the key is removed only while it still holds that forced value, leaving whatever the user chose in
// Eevee's own UI. Safe to call every launch.
void SGEeveeRestoreLyricsReplacement(void);
