// The Home redesign: Spotify's Home page kept, with its controllers, lists and cards, decluttered to a
// music app on black and restyled from the Kit. No settings of its own.
//
//     HomeSections.x   known video and episode sections collapse; the shortcuts grid, DJ and shelves of
//                      cards stay, and unknown feed sections remain visible. The DJ loses its heading, and
//                      the flags the redesign forces on Home
//     HomeHeader.x     a large title where the filter pills were, the avatar at the trailing edge, no scrim
//     HomeHeadings.x   the shelves' headings in the Music app's size, drawn over Spotify's
//     HomeCards.x      the Encore button every card is: shortcut tiles (HomeTiles.m), continuous corners on the
//                      shelf covers, the DJ card at the card radius without its talking transcript
//     HomeTiles.m      a shortcut tile's picture run across the tile, blurred behind its title
//     HomeTopPicks.x   the first shelf drawn large, and the page's gradient following the album at its leading edge
//     HomePerf.x       FLEX builds: the frames of each scroll of Home and the time the hooks above took
//
// Every hook installs only while Redesigned UI is on (SGRedesignedUI).
// Threading: main thread only.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

// Whether HomeSections.x has collapsed the section in this cell.
BOOL SGRHomeSectionCollapsed(UIView *cell);

// Styles a shortcut tile (id=Shortcut.Card.Home) and keeps its picture in step with its cover (HomeTiles.m).
void SGRHomeStyleTile(UIView *tile);

// FLEX builds only (HomePerf.x): a hook takes the time as it starts and hands it back as it ends; outside
// a FLEX build Begin returns 0 and End does nothing.
typedef NS_ENUM(NSUInteger, SGRHomeProbe) {
    SGRHomeProbeSections,
    SGRHomeProbeHeader,
    SGRHomeProbeHeadings,
    SGRHomeProbeCards,
    SGRHomeProbeTiles,
    SGRHomeProbeCount,
};
CFTimeInterval SGRHomeProbeBegin(void);
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began);

// The "Home page" switch of Appearance: on, the glass Home (mixes first, glass pills, gradient, scrolling header);
// off, the Home as it was. Read once at launch (HomeCards.x).
#define SGRKeyHomeGlass @"spotifyglass.redesign.home.glass"
#define SGRKeyHomeTopPicks @"spotifyglass.redesign.home.toppicks"
BOOL SGRHomeGlassStyle(void);
SGModRow *SGRHomeStyleRow(void);
SGModRow *SGRHomeTopPicksRow(void);
void SGRHomeProfilePhotoPreferenceChanged(void);

// Whether the view sits in the shelf HomeTopPicks.x draws large (a card of it, or its cell).
BOOL SGRHomeShelfIsLarge(UIView *view);
