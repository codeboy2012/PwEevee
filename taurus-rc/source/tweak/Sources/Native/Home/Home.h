#import <UIKit/UIKit.h>

#define SGKeyHomeGradient @"spotifyglass.homeGradient"

// Parts of Home to hide, one switch each (HomeDeclutter.x). An unset switch is off.
#define SGHideHomeShortcuts @"spotifyglass.hide.homeShortcuts"
#define SGHideHomePills @"spotifyglass.hide.homePills"
#define SGHideHomePromo @"spotifyglass.hide.homePromo"
#define SGHideHomePreviews @"spotifyglass.hide.homePreviews"
#define SGHideHomeDJ @"spotifyglass.hide.homeDJ"

typedef NS_ENUM(NSInteger, SGHomeChoice) {
    SGHomeChoiceTint,       // which colour it fades
    SGHomeChoiceStrength,   // how far up or down that colour is taken
    SGHomeChoiceHeight,     // how far down the page it reaches
    SGHomeChoiceCount,
};

NSArray<NSString *> *SGHomeChoiceNames(SGHomeChoice choice);
NSString *SGHomeChoiceKey(SGHomeChoice choice);
NSInteger SGHomeChoiceDefault(SGHomeChoice choice);
NSInteger SGHomeChoiceValue(SGHomeChoice choice);

UIViewController *SGHomeSettingsPage(void);
UIViewController *SGHomeGradientPage(void);
