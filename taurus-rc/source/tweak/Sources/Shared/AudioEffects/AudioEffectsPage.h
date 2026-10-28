#import <UIKit/UIKit.h>
#import "AudioEffects.h"

UIViewController *SGDSPSettingsPage(void);
// What the Mod Settings row reads out: Off, On, or how many effects are on.
NSString *SGDSPSummary(void);

// The pages the effects' rows push (AudioEffectsLibraryPage.m).
UIViewController *SGDSPLibraryPage(SGDSPFileKind kind);
UIViewController *SGDSPGraphicEqPage(void);
// The choice of a file effect's library, "None" when there is none.
NSString *SGDSPChosenFile(SGDSPFileKind kind);
