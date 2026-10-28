#import <UIKit/UIKit.h>

#define SGRHideBarConnect @"spotifyglass.redesign.hide.barConnect"   // the device button on the card
#define SGRKeyNowPlayingRoundedArtwork @"spotifyglass.redesign.nowPlayingBar.roundedArtwork"
#define SGRKeyNowPlayingProgressThickness @"spotifyglass.redesign.nowPlayingBar.progressThickness"

@class SGModRow;

UIViewController *SGRNowPlayingBarSettingsPage(void);
NSArray<SGModRow *> *SGRNowPlayingBarRows(void);   // the Mini player section on the redesign's Player page

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
// The artwork on that card in `host`'s coordinates; CGRectNull when none was found.
CGRect SGRNowPlayingArtworkFrameIn(UIView *host);
void SGRNowPlayingBarRefresh(void);

// Docks the card into one row with the tab bar's two round buttons (TabBar.x, TabBarMinimize.x). The card is not
// scaled down to fit: that left its text and cover too small to read. A compact pill of the mod's own takes the row
// instead, one line high like the round buttons: the cover, the title on one line and play/pause. `row` is in window
// coordinates and `host` is the view the pill is drawn in (the glass bar's host, which also holds the two buttons).
// The pill grows out of the card's place and the card fades under it; NO puts the card back as Spotify lays it out.
void SGRDockNowPlayingCard(BOOL docked, CGRect row, UIView *host, BOOL animated);

// Whether a track is playing or paused on the card, so there is something for the minimized pill to show. The glass bar
// only minimizes while there is, and is left whole otherwise.
BOOL SGRNowPlayingAvailable(void);
