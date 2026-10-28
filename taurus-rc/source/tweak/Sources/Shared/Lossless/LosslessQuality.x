// Spotify's streaming quality, read and set through its own preferences object (captured as Spotify makes it).
#import "Core/SGCore.h"
#import "LosslessQuality.h"
#import "SGLossless.h"

#define SGKeyLosslessSavedQuality @"spotifyglass.lossless.savedQuality"   // [cellular, Wi-Fi] while lowered
static const NSInteger kLowest = 1;

@interface _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation : NSObject
- (NSInteger)audioPlayBitrate;
- (NSInteger)audioPlayBitrateNonMetered;
- (void)setAudioPlayBitrate:(NSInteger)level;
- (void)setAudioPlayBitrateNonMetered:(NSInteger)level;
@end

static __weak _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation *sg_preferences;

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation
- (id)initWithScheduler:(id)scheduler {
    id made = %orig;
    sg_preferences = made;
    // Lowered when Spotify last quit, and lossless is off now: nothing else would put it back.
    if (!SGHidden(SGKeyLossless)) dispatch_async(dispatch_get_main_queue(), ^{ SGLosslessLowerQuality(NO); });
    return made;
}
%end

BOOL SGStreamQuality(NSInteger *metered, NSInteger *nonMetered) {
    __auto_type preferences = sg_preferences;
    if (!preferences) return NO;
    *metered = preferences.audioPlayBitrate;
    *nonMetered = preferences.audioPlayBitrateNonMetered;
    return YES;
}

BOOL SGSetStreamQuality(NSInteger metered, NSInteger nonMetered) {
    __auto_type preferences = sg_preferences;
    if (!preferences) return NO;
    preferences.audioPlayBitrate = metered;
    preferences.audioPlayBitrateNonMetered = nonMetered;
    return YES;
}

void SGLosslessLowerQuality(BOOL lower) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray<NSNumber *> *saved = [defaults arrayForKey:SGKeyLosslessSavedQuality];
    NSInteger metered, nonMetered;
    if (!SGStreamQuality(&metered, &nonMetered)) return;
    if (lower && !saved) {
        if (metered == kLowest && nonMetered == kLowest) return;
        [defaults setObject:@[@(metered), @(nonMetered)] forKey:SGKeyLosslessSavedQuality];
        SGSetStreamQuality(kLowest, kLowest);
        SGLog(@"lossless: Spotify's quality lowered for the next track (was %ld, %ld)", (long)metered, (long)nonMetered);
    } else if (!lower && saved.count == 2) {
        if (metered == kLowest && nonMetered == kLowest) SGSetStreamQuality(saved[0].integerValue, saved[1].integerValue);
        [defaults removeObjectForKey:SGKeyLosslessSavedQuality];
        SGLog(@"lossless: Spotify's quality back to %ld, %ld", (long)saved[0].integerValue, (long)saved[1].integerValue);
    }
}

%ctor {
    #if !SG_DRIVER
    if (!SGHidden(SGKeyLossless) && ![NSUserDefaults.standardUserDefaults arrayForKey:SGKeyLosslessSavedQuality]) return;
    #endif
    %init;
    SGRequireClasses(@[@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}
