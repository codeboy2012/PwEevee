// One font for the whole app (Fonts.x), chosen on the Appearance page under either look, and a font file
// of the user's own as one of the choices (FontImport.m).
#import <UIKit/UIKit.h>

#define SGKeyAppFont @"spotifyglass.font"
// The imported family: its files' names in Application Support/spoti.pw/Fonts, and the family name read from them.
// SGKeyAppFontFile is the single file of an import from before families, moved to the list on first use.
#define SGKeyAppFontFiles @"spotifyglass.font.files"
#define SGKeyAppFontName @"spotifyglass.font.name"
#define SGKeyAppFontFile @"spotifyglass.font.file"
// The family chosen under More fonts, by its name ("Avenir Next").
#define SGKeyAppFontFamily @"spotifyglass.font.family"

typedef NS_ENUM(NSInteger, SGAppFont) {
    SGAppFontSpotify,   // Spotify's own, untouched
    SGAppFontSystem,    // San Francisco
    SGAppFontRounded,   // SF Rounded
    SGAppFontSerif,     // New York
    SGAppFontMono,      // SF Mono
    SGAppFontCustom,    // the family imported from Files
    SGAppFontFamily,    // a family iOS carries, named by SGKeyAppFontFamily
};

SGAppFont SGAppFontChosen(void);
NSArray<NSString *> *SGAppFontNames(void);   // the five built in, by SGAppFont
NSArray<NSString *> *SGAppFontFamilies(void);   // More fonts: the families this iPhone has of a fixed few
// Registers the imported files with Core Text for this process and answers the family name, or nil when no
// file is left or Core Text will not take them.
NSString *SGRegisterCustomFont(void);
// The family name the faces share, or nil when they differ, one has none, or there are none.
NSString *SGFontSingleFamily(NSArray<NSString *> *names);

// Opens Files to import a font family for the lyrics alone; `done` runs once the files are in or refused.
void SGPickFontForLyrics(void (^done)(void));

@class SGModRow;
NSArray<SGModRow *> *SGAppFontRows(void);   // the Font row, opening the page of choices
