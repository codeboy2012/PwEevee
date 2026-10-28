#import <UIKit/UIKit.h>

// The page's list (trees/clean/playlist/02.txt:23).
extern NSString *const SGRPlaylistListIdentifier;
// PlaylistMenu.x. The row of curation pills over the first track (own-playlist/01.txt:33).
extern NSString *const SGRPlaylistCurationIdentifier;
void SGRPlaylistTakeCuration(UIView *cell);
void SGRPlaylistTakeSort(UIView *page, UIView *button);

UIViewController *SGRPlaylistHeaderOf(UIView *view);
UIView *SGRPlaylistPageOf(UIView *view);

UIColor *SGRPlaylistFieldColor(UIView *view);
// The cover of the page `view` is on, for its field to take its colour from. The same image again is a no-op.
void SGRPlaylistSetArtwork(UIView *view, UIImage *image);
