// The presets: built-in ones over a reset, and the user's own as a copy of every dsp key. Everything goes back
// in through AudioEffects.h's setters, so it is clamped and applied the way the page's own changes are.
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"

static NSString *const kPrefix = @"spotifyglass.dsp.";

static NSUserDefaults *store(void) {
    return NSUserDefaults.standardUserDefaults;
}

// A value back through its setter: a switch (the key naming its own effect), a number, the gains as a
// list, or text. Anything else is left out, a preset from a later build naming a key this one lacks too.
static void setValue(NSString *key, id value) {
    if (![key hasPrefix:kPrefix]) return;
    if ([value isKindOfClass:NSArray.class]) SGDSPSetGains(key, value);
    else if ([value isKindOfClass:NSString.class]) SGDSPSetString(key, value);
    else if (![value isKindOfClass:NSNumber.class]) return;
    else if ([SGDSPEffectOf(key) isEqualToString:key]) SGDSPSetSwitch(key, [value boolValue]);
    else SGDSPSetNumber(key, [value doubleValue]);
}

// A pick is meant to be heard: the master switch, off until asked for, comes on with it.
static void turnOn(void) {
    if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
}

static NSDictionary<NSString *, id> *currentValues(void) {
    NSDictionary<NSString *, id> *all = store().dictionaryRepresentation;
    NSMutableDictionary<NSString *, id> *values = [NSMutableDictionary dictionary];
    for (NSString *key in all) {
        if ([key hasPrefix:kPrefix]) values[key] = all[key];
    }
    return values;
}

#pragma mark - built in

typedef struct {
    NSString *__unsafe_unretained name, *__unsafe_unretained detail;
} SGDSPPresetName;

static const SGDSPPresetName kBuiltIn[] = {
    {@"Bass boost", @"Bass boost at 8 dB"},
    {@"Vocal clarity", @"Equalizer on voices, a light compander"},
    {@"Late night", @"Quiet and loud evened out, less bass"},
    {@"Concert hall", @"A large hall's reverb, a wider stage"},
    {@"Warm analog", @"Tube warmth, a warm equalizer"},
    {@"Headphone comfort", @"Crossfeed, a softer top"},
    {@"Wide stereo", @"Stereo widening"},
};

static NSArray<NSNumber *> *equalizer(NSString *preset) {
    return SGDSPEqualizerPreset((NSInteger)[SGDSPEqualizerPresetNames() indexOfObject:preset]);
}

static NSDictionary<NSString *, id> *builtInValues(NSInteger index) {
    switch (index) {
        case 0: return @{SGKeyDSPBass: @YES, SGKeyDSPBassGain: @8};
        case 1: return @{SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: equalizer(@"Vocal"),
                         SGKeyDSPCompander: @YES, SGKeyDSPCompanderGains: @[@0, @0.2, @0.3, @0.3, @0.3, @0.2, @0]};
        // The compander over 0 lifts the quiet parts and holds the loud ones; the gain brings the level back.
        case 2: return @{SGKeyDSPCompander: @YES, SGKeyDSPCompanderGains: @[@0.6, @0.7, @0.8, @0.8, @0.8, @0.7, @0.6],
                         SGKeyDSPCompanderTime: @0.3, SGKeyDSPEqualizer: @YES,
                         SGKeyDSPEqualizerGains: @[@-6, @-5, @-4, @-2, @-1, @0, @0, @0, @0, @0, @0, @0, @-1, @-2, @-2],
                         SGKeyDSPPostGain: @3, SGKeyDSPLimiterThreshold: @-3};
        case 3: return @{SGKeyDSPReverb: @YES, SGKeyDSPReverbPreset: @7, SGKeyDSPReverbAmount: @40,
                         SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @65};
        case 4: return @{SGKeyDSPTube: @YES, SGKeyDSPTubeDrive: @6, SGKeyDSPEqualizer: @YES, SGKeyDSPEqualizerGains: equalizer(@"Warm")};
        case 5: return @{SGKeyDSPCrossfeed: @YES, SGKeyDSPCrossfeedMode: @2, SGKeyDSPEqualizer: @YES,
                         SGKeyDSPEqualizerGains: @[@0, @0, @0, @0, @0, @0, @0, @0, @0, @0, @-1, @-2, @-2, @-3, @-3]};
        case 6: return @{SGKeyDSPStereoWide: @YES, SGKeyDSPStereoWideLevel: @75};
    }
    return nil;
}

NSArray<NSString *> *SGDSPBuiltInPresetNames(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (size_t i = 0; i < sizeof kBuiltIn / sizeof *kBuiltIn; i++) [names addObject:kBuiltIn[i].name];
    return names;
}

NSString *SGDSPBuiltInPresetDetail(NSInteger index) {
    return index >= 0 && index < (NSInteger)(sizeof kBuiltIn / sizeof *kBuiltIn) ? kBuiltIn[index].detail : nil;
}

void SGDSPLoadBuiltInPreset(NSInteger index) {
    NSDictionary<NSString *, id> *values = builtInValues(index);
    if (!values) return;
    NSMutableDictionary<NSString *, id> *kept = [NSMutableDictionary dictionary];
    NSDictionary<NSString *, id> *now = currentValues();
    for (NSString *key in now) {
        if ([SGDSPEffectOf(key) isEqualToString:SGKeyDSPGraphicEq]) kept[key] = now[key];
    }
    SGDSPResetAll();
    for (NSString *key in kept) setValue(key, kept[key]);
    for (NSString *key in values) setValue(key, values[key]);
    turnOn();
}

#pragma mark - the user's

static NSDictionary<NSString *, NSDictionary *> *userPresets(void) {
    id presets = [store() objectForKey:SGKeyDSPUserPresets];
    return [presets isKindOfClass:NSDictionary.class] ? presets : @{};
}

NSArray<NSString *> *SGDSPUserPresetNames(void) {
    return [userPresets().allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

void SGDSPSaveUserPreset(NSString *name) {
    if (!name.length) return;
    NSMutableDictionary *presets = [userPresets() mutableCopy];
    presets[name] = currentValues();
    [store() setObject:presets forKey:SGKeyDSPUserPresets];
}

BOOL SGDSPLoadUserPreset(NSString *name) {
    NSDictionary *values = userPresets()[name];
    if (![values isKindOfClass:NSDictionary.class]) return NO;
    SGDSPResetAll();
    for (NSString *key in values) setValue(key, values[key]);
    turnOn();
    return YES;
}

void SGDSPDeleteUserPreset(NSString *name) {
    NSMutableDictionary *presets = [userPresets() mutableCopy];
    [presets removeObjectForKey:name];
    [store() setObject:presets forKey:SGKeyDSPUserPresets];
}

#pragma mark - GraphicEQ text

// One line: AutoEq's files end in a newline, and a copy out of a web page often has more.
NSString *SGDSPGraphicEqLine(NSString *text) {
    NSArray<NSString *> *words = [text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    NSString *line = [words componentsJoinedByString:@" "];
    return [line.lowercaseString hasPrefix:@"graphiceq:"] ? line : nil;
}
