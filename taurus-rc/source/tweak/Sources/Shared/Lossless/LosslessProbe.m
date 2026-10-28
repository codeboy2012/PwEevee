// FLEX builds only: the lossless engine and Spotify's streaming quality, driven from the Mac (scripts/phone.py).
#if SG_DRIVER
#import "Diagnostics/Diagnostics.h"
#import "Core/SGCore.h"
#import "SGLossless.h"
#import "LosslessQuality.h"
#import "Shared/Player/PlayerState.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Spotify's streaming quality settings and the playing track's quality; --set N sets both settings to N.
static NSDictionary *quality(NSDictionary *p, NSString **error) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    Class preferences = NSClassFromString(@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation");
    for (NSString *name in @[@"audioPlayBitrate", @"audioPlayBitrateNonMetered", @"setAudioPlayBitrateNonMetered:"]) {
        Method m = class_getInstanceMethod(preferences, NSSelectorFromString(name));
        result[[@"type_" stringByAppendingString:name]] = m ? @(method_getTypeEncoding(m)) : @"missing";
    }
    __block NSInteger metered = -1, nonMetered = -1;
    __block BOOL read = NO;
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (p[@"set"]) SGSetStreamQuality([p[@"set"] integerValue], [p[@"set"] integerValue]);
        read = SGStreamQuality(&metered, &nonMetered);
        id state = SGPlayerState();
        id q = [state respondsToSelector:NSSelectorFromString(@"playbackQuality")] ? [state valueForKey:@"playbackQuality"] : nil;
        result[@"track"] = [[state valueForKeyPath:@"track.URI"] description] ?: @"";
        id future = [state respondsToSelector:NSSelectorFromString(@"future")] ? [state valueForKey:@"future"] : nil;
        id next = [future isKindOfClass:NSArray.class] ? [(NSArray *)future firstObject] : nil;
        result[@"next"] = [[next valueForKey:@"URI"] description] ?: @"";
        result[@"playback_quality"] = [q description] ?: @"none";
        SEL originName = NSSelectorFromString(@"fileOriginToString:");
        if ([q respondsToSelector:originName]) {
            for (long long o = 0; o < 6; o++) {
                id name = ((id (*)(id, SEL, long long))objc_msgSend)(q, originName, o);
                result[[NSString stringWithFormat:@"origin_name_%lld", o]] = [name description] ?: @"nil";
            }
        }
        for (NSString *key in @[@"bitrateLevel", @"targetBitrateLevel", @"targetBitrateAvailable", @"fileOrigin", @"hifiStatus", @"qualityRestrictionReason", @"highestAvailableQuality"]) {
            @try { result[[@"q_" stringByAppendingString:key]] = [[q valueForKey:key] description] ?: @"nil"; } @catch (NSException *e) { result[[@"q_" stringByAppendingString:key]] = @"?"; }
        }
    });
    if (!read) { *error = @"Spotify's preferences object was not captured"; return nil; }
    result[@"metered"] = @(metered);
    result[@"non_metered"] = @(nonMetered);
    return result;
}

NSDictionary *SGLosslessProbe(NSString *verb, NSDictionary *p, NSString **error) {
    if ([verb isEqualToString:@"anchor"]) {
        NSString *path = p[@"path"];
        if (!path.length) { *error = @"lossless anchor takes --path to a FLAC or ALAC file in the app's container"; return nil; }
        return SGLosslessAnchor(path, p[@"hint"] ? [p[@"hint"] doubleValue] : -1, error);
    }
    if ([verb isEqualToString:@"check"]) return SGLosslessCheck(error);
    if ([verb isEqualToString:@"quality"]) return quality(p, error);
    if ([verb isEqualToString:@"stop"]) {
        SGLosslessStop(YES);
        return @{};
    }
    *error = @"lossless takes anchor, check, quality or stop";
    return nil;
}
#endif
