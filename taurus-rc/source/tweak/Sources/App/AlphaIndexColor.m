// The alphabet index's letters take the accent colour of the look the app runs in: the redesign's own, or the
// native look's (Spotify's green until one is chosen). Defined here because only App knows both looks.
#import "Core/SGCore.h"
#import "Shared/AlphaIndex/AlphaIndex.h"
#import "Native/Appearance/Appearance.h"
#import "Redesigned/Kit/SGRTokens.h"

UIColor *SGAlphaIndexColor(void) {
    if (SGRedesignedUI()) return SGRAccent();
    return SGAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
}
