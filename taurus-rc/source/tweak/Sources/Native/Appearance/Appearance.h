#import <UIKit/UIKit.h>

#define SGKeyAmoled @"spotifyglass.amoled"
#define SGKeyAccent @"spotifyglass.accent"   // 0xRRGGBB; unset or negative keeps Spotify's own green

UIColor *SGAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGAccentLabel(void);  // "#RRGGBB", or the name of Spotify's own
void SGPickAccent(void);        // the system colour picker over the top of the app, stored on the way out

@class SGModRow;
NSArray<SGModRow *> *SGNativeAppearanceRows(void);   // AMOLED and the accent colour, for the Appearance card
