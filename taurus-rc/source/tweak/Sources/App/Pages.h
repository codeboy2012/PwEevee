#import <UIKit/UIKit.h>

#define SGKeySidebarBadgeText @"spotifyglass.sidebarBadgeText"
extern NSNotificationName const SGSidebarBadgeTextDidChangeNotification;

// Redesigned UI, the one switch between the two looks, and what its ⓘ reads out.
void SGSetRedesignedUI(BOOL on);
extern NSString *const SGRedesignedUIInfo;

UIViewController *SGAppearanceSettingsPage(void);   // Appearance for the selected look and the shared sidebar badge
UIViewController *SGPlayerSettingsPage(void);
UIViewController *SGLyricsSettingsPage(void);  // its sources in either look, and the redesign's display
UIViewController *SGNavbarPage(void);       // the tab editor of whichever look is stored
