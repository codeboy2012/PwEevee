#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB

UIColor *SGRAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGRAccentLabel(void);  // "#RRGGBB", or the name of Spotify's own
void SGRPickAccent(void);        // the system colour picker over the top of the app, stored on the way out

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent colour, for the Appearance card
