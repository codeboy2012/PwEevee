#import <UIKit/UIKit.h>

extern const CGFloat SGRSideMargin;      // 16, the page's side margin
extern const CGFloat SGRGrid;            // 8, every gap is a multiple of it
extern const CGFloat SGRRadiusArtwork;   // 12, the player's cover
extern const CGFloat SGRRadiusCard;      // 16, a content card
extern const CGFloat SGRRadiusCover;     // 8, a release cover in a list
extern const CGFloat SGRRadiusThumb;     // 6, a row's thumbnail up to 64pt
extern const CGFloat SGRGlassCircleSize; // 44, a round glass behind a top bar button
extern const CGFloat SGRActionHeight;    // 48, a button of the action row under a hero
extern const CGFloat SGRActionSpacing;   // 12, between the buttons of an action row
extern const CGFloat SGRGlassSpacing;    // 16, how near two glass shapes merge in one container
extern const NSTimeInterval SGRCrossfade;   // 0.35, a new image or field colour fading in

UIColor *SGRPrimary(void);      // white
UIColor *SGRSecondary(void);    // white 65%, 80% with Increase Contrast
UIColor *SGRTertiary(void);     // white 40%, 60% with Increase Contrast
UIColor *SGRAccent(void);       // the accent colour of Appearance, else Spotify's green
NSInteger SGRAccentRGB(void);   // that colour as 0xRRGGBB, for following the cover (PlayerCoverAccent.x)
// The view SGRPlainCheck.x marks the stand-in checkmark with, for the player to tint it too.
extern NSString *const SGRPlainCheckIdentifier;
UIColor *SGRNeutralField(void); // #121212, the field before a colour arrives; SGRAmoled.x turns it black
// Where glass cannot be (Reduce Transparency), the shape it would have had: white 16% over the field.
UIColor *SGRSolidGlassFill(void);
// A content surface on the field (a card), a step lighter than the field it sits on.
UIColor *SGRElevated(UIColor *field);
UIColor *SGRHairline(void);

UIFont *SGRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest);
// The same font with digits of one width, so a time or a count does not twitch as it changes.
UIFont *SGRMonospacedDigitsFont(UIFont *font);

BOOL SGRReduceMotion(void);
BOOL SGRReduceTransparency(void);
BOOL SGRIncreaseContrast(void);

typedef NS_ENUM(NSInteger, SGRMotion) {
    SGRMotionLayout,   // a spring with no overshoot, for anything moving or resizing
    SGRMotionPress,    // a spring with a little bounce, for press feedback
    SGRMotionFade,     // an ease in and out over SGRCrossfade, kept under Reduce Motion
    SGRMotionRespond,  // a spring with a touch of bounce, for a tap bringing something back
    SGRMotionExit,     // a quick ease out, for something leaving the screen
};
void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished));
// A layout spring: runs `animations`, then lays `host` out within it. Under Reduce Motion both are instant.
void SGRAnimateLayout(UIView *host, void (^animations)(void), void (^completion)(BOOL finished));
