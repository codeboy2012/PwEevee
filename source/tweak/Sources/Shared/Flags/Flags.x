#import "Core/SGCore.h"
#import "Flags.h"

static id forced(NSString *key) {
    return SGForcedFlagValue(key);
}

static void seedFlagDefaultsOnce(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *seededKey = @"spotifyglass.flags.defaultOverridesSeeded";
    if ([defaults boolForKey:SGKeyStock] || [defaults boolForKey:seededKey]) return;
    if (!SGFlagOverride(@"ios-feature-localfiles.documents_enabled"))
        SGSetFlagOverride(@"ios-feature-localfiles.documents_enabled", @1);
    [defaults setBool:YES forKey:seededKey];
}

static BOOL boolFor(NSString *key, BOOL orig) {
    id value = forced(key);
    return value ? [value boolValue] : orig;
}

static long intFor(NSString *key, long lower, long upper, long orig) {
    id value = forced(key);
    return value ? MAX(lower, MIN(upper, (long)[value longLongValue])) : orig;
}

static id enumFor(NSString *key, id orig) {
    id value = forced(key);
    return [value isKindOfClass:NSString.class] ? value : orig;
}

%hook _TtC22RemoteConfigurationSDK25ConfigurationProviderImpl
- (BOOL)boolValueForId:(NSString *)key defaultValue:(BOOL)fallback {
    BOOL orig = %orig;
    return boolFor(key, orig);
}
- (long)intValueForId:(NSString *)key lower:(long)lower upper:(long)upper defaultValue:(long)fallback {
    long orig = %orig;
    return intFor(key, lower, upper, orig);
}
- (id)enumValueForId:(NSString *)key values:(NSArray *)values defaultValue:(id)fallback {
    id orig = %orig;
    return enumFor(key, orig);
}
%end

// The observable properties listed in Info.plist go through a second provider.
%hook _TtC22RemoteConfigurationSDK35ObservableConfigurationProviderImpl
- (BOOL)boolValueForId:(NSString *)key defaultValue:(BOOL)fallback {
    BOOL orig = %orig;
    return boolFor(key, orig);
}
- (long)intValueForId:(NSString *)key lower:(long)lower upper:(long)upper defaultValue:(long)fallback {
    long orig = %orig;
    return intFor(key, lower, upper, orig);
}
- (id)enumValueForId:(NSString *)key values:(NSArray *)values defaultValue:(id)fallback {
    id orig = %orig;
    return enumFor(key, orig);
}
%end

%ctor {
    seedFlagDefaultsOnce();
    SGRegisterFlagForcer(NO, ^id(NSString *key) {
        return [key isEqualToString:@"floating_music_videos_unit_enabled"] ? @NO : nil;
    }, nil);
    %init;
    SGRequireClasses(@[
        @"_TtC22RemoteConfigurationSDK25ConfigurationProviderImpl",
        @"_TtC22RemoteConfigurationSDK35ObservableConfigurationProviderImpl",
    ]);
}
