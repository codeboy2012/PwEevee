// "Add a Tab", the same for either look: a sheet with the tab's name, the page it opens and the icon on
// it, each picked rather than typed (Choose a Link, Choose an Icon). The sheet stores nothing; the look's
// own editor keeps what it hands back in that look's list.
#import <UIKit/UIKit.h>

// The keys of a preset and of the tab handed back.
extern NSString *const SGTabTitle;     // NSString
extern NSString *const SGTabURI;       // NSString, a spotify: URI
extern NSString *const SGTabIcon;      // NSString, an Encore glyph or an SF Symbol
extern NSString *const SGTabIconSet;   // SGTabIconSetSymbols (TabIcons.h) for an SF Symbol, absent for Encore

// `presets` carry Encore icons; those Spotify's router has nowhere to send are left out. `add` is given
// the tab when Add is tapped, then the sheet goes; Cancel hands back nothing.
void SGPresentAddTabSheet(UIViewController *owner, NSArray<NSDictionary *> *presets, void (^add)(NSDictionary *tab));
// The same sheet as Edit Tab, over `tab` (the keys above): Save hands the tab back as it now is, and a Remove
// Tab row under the rest runs `remove` once an action sheet has asked.
void SGPresentEditTabSheet(UIViewController *owner, NSArray<NSDictionary *> *presets, NSDictionary *tab,
                           void (^save)(NSDictionary *tab), void (^remove)(void));
// The same editor limited to a tab's name and icon, for tabs whose destination Spotify owns.
void SGPresentEditTabAppearanceSheet(UIViewController *owner, NSDictionary *tab, void (^save)(NSDictionary *tab));
