#import <UIKit/UIKit.h>

#define SGKeyNavbar @"spotifyglass.navbar"

extern NSString *const SGNavbarID;      // NSString, the entry's identity
extern NSString *const SGNavbarTitle;   // NSString, the name in the settings list and under the icon
extern NSString *const SGNavbarURI;     // NSString, the mod's own tabs only: what a tap opens
extern NSString *const SGNavbarIcon;    // NSString, an SPTEncoreIcon class method such as "podcasts"
extern NSString *const SGNavbarHidden;  // NSNumber
NSArray<NSDictionary *> *SGNavbarLayout(void);
void SGSetNavbarLayout(NSArray<NSDictionary *> *layout);
// Spotify's own tabs in Spotify's order, as Navbar.x last saw them on the bar.
NSArray<NSString *> *SGNavbarStock(void);
void SGSetNavbarStock(NSArray<NSString *> *stock);

// Navbar.x, called from the tab bar's layout passes in TabBarHooks.x.
void SGComposeTabBar(UIView *tabBar);
void SGLogTabBarRow(UIView *tabBar);
// Lays the bar out again after the Navbar page changes something, so it does not wait for a touch.
void SGRefreshTabBar(void);

UIViewController *SGNavbarSettingsPage(void);   // the tab editor, in Mod Settings
UIViewController *SGNavbarEditorPage(void);     // the tab editor alone, for the welcome tour
