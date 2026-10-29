// The icons a tab of the mod's own can wear, on either look's bar: one of Spotify's Encore glyphs or an
// SF Symbol. Each look keeps which of the two an entry's icon name belongs to under its own key; an entry
// saved before there was a choice has none and means Encore.
#import <UIKit/UIKit.h>

// The value either look stores for a tab whose icon is an SF Symbol.
extern NSString *const SGTabIconSetSymbols;

// The icon drawn the way the bar draws Spotify's own: an Encore glyph by its SPTEncoreIcon class method,
// or an SF Symbol at Encore's visual size (19 pt semibold) in `color`. A symbol name that does not
// resolve tries Encore, and a glyph name Encore does not have ends in star.fill.
UIView *SGTabIconView(NSString *name, BOOL symbol, UIColor *color);

// Every glyph SPTEncoreIcon has, sorted case-insensitively, asked of the class once; empty if it is gone.
NSArray<NSString *> *SGEncoreGlyphNames(void);
// A few glyphs and symbols a tab is likely to want, in that order, kept to the ones that draw here.
NSArray<NSString *> *SGCommonTabGlyphs(void);
NSArray<NSString *> *SGCommonTabSymbols(void);
// Every SF Symbol this iOS draws, read once in the background, handed back on the main queue. Without
// the system's list of names it is the common ones only.
void SGLoadSymbolNames(void (^done)(NSArray<NSString *> *names));
