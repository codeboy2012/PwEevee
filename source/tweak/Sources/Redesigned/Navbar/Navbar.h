#import <UIKit/UIKit.h>

#define SGRKeyNavbar @"spotifyglass.redesign.navbar"
// Icons only on the glass bar. Off unless set; applies as soon as the bar lays out again.
#define SGRKeyNavbarHideLabels @"spotifyglass.redesign.navbar.hideLabels"
#define SGRKeyNavbarAppleIcons @"spotifyglass.redesign.navbar.appleIcons"
#define SGRKeyNavbarProfilePhoto @"spotifyglass.redesign.navbar.profilePhoto"
#define SGRKeyNavbarBottomGradient @"spotifyglass.redesign.navbar.bottomGradient"
// Whether a page's scroll minimizes the glass bar: its first and last tab stay as two round buttons and the now
// playing card moves between them. On unless set; read once at launch.
#define SGRKeyNavbarMinimize @"spotifyglass.redesign.navbar.minimize"

extern NSString *const SGRNavbarID;      // NSString, the entry's identity
extern NSString *const SGRNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGRNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGRNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts"
extern NSString *const SGRNavbarIconSet; // NSString, SGTabIconSetSymbols for an SF Symbol
extern NSString *const SGRNavbarCustomIcon; // NSNumber, whether a stock tab has a custom glyph
extern NSString *const SGRNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *SGRNavbarLayout(void);
void SGRSetNavbarLayout(NSArray<NSDictionary *> *layout);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGRNavbarStock(void);
void SGRSetNavbarStock(NSArray<NSString *> *stock);
NSArray<NSString *> *SGRNavbarRemovedStock(void);
void SGRSetNavbarRemovedStock(NSArray<NSString *> *stock);
NSURL *SGRNavbarTabURL(NSString *uri);

// Navbar.x, called from the tab bar's layout passes in TabBar.x.
void SGRComposeTabBar(UIView *tabBar);
void SGRLogTabBarRow(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRRefreshTabBar(void);
void SGRSetTabBarGradientVisible(BOOL visible);
void SGRNavbarSetProfilePhotoVisible(UIView *face);
NSString *SGRNavbarDefaultIcon(NSString *stockID);
BOOL SGRNavbarEntryHasCustomIcon(NSDictionary *entry);

UIViewController *SGRNavbarSettingsPage(void);   // the tab editor, in Mod Settings
UIViewController *SGRNavbarEditorPage(void);     // the tab editor alone, for the welcome tour

// TabBar.x: whether the glass bar is minimized by a page's scroll, and minimizing it (TabBarMinimize.x).
BOOL SGRTabBarMinimized(void);
void SGRSetTabBarMinimized(BOOL minimized, BOOL animated);

// TabBar.x: shows the given custom tab (an SGRTabItemView on the row) as the bar's selected one, and keeps
// it selected until a stock tab is tapped; Spotify never paints one of the mod's tabs white itself.
void SGRTabBarMarkCustomSelected(UIView *customItem);

// TabBar.x: passes a tap on to the Spotify view a mod view stands in for, so the mini player's pill opens the player.
// SGRFireTapRecognizers fires the tap recognizers on that one view alone; it answers whether it had any.
BOOL SGRFireTapRecognizers(UIView *view);
