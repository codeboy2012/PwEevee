#import "Core/SGCore.h"
#import "Diagnostics.h"
#import "Headers/SPTPlayer.h"
#import <objc/runtime.h>

static NSString *summarize(id value, NSUInteger depth);

// Long collections and the queues would bury the line; their size is enough.
static NSString *summarizeCollection(id value) {
    if ([value isKindOfClass:NSArray.class]) return [NSString stringWithFormat:@"[%lu]", (unsigned long)[value count]];
    if ([value isKindOfClass:NSSet.class]) return [NSString stringWithFormat:@"{%lu}", (unsigned long)[value count]];
    return nil;
}

static NSString *readable(id value, NSUInteger depth) {
    if (!value) return @"nil";
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSURL.class]) {
        return [value description];
    }
    NSString *collection = summarizeCollection(value);
    if (collection) return collection;
    if ([value isKindOfClass:NSDictionary.class]) return [value description];
    return depth > 0 ? summarize(value, depth - 1) : NSStringFromClass([value class]);
}

static NSString *summarize(id object, NSUInteger depth) {
    if (!object) return @"nil";
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (Class cls = [object class]; cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        for (unsigned i = 0; i < count; i++) {
            NSString *name = @(property_getName(properties[i]));
            if ([seen containsObject:name]) continue;
            [seen addObject:name];
            id value = nil;
            @try {
                value = [object valueForKey:name];
            } @catch (NSException *exception) {
                continue;
            }
            [parts addObject:[NSString stringWithFormat:@"%@=%@", name, readable(value, depth)]];
        }
        free(properties);

        count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned i = 0; i < count; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            NSString *name = [@(ivar_getName(ivars[i])) stringByReplacingOccurrencesOfString:@"_" withString:@""];
            if ([seen containsObject:name]) continue;
            [seen addObject:name];
            id value = nil;
            @try {
                value = object_getIvar(object, ivars[i]);
            } @catch (NSException *exception) {
                continue;
            }
            [parts addObject:[NSString stringWithFormat:@"%@=%@", name, readable(value, depth)]];
        }
        free(ivars);
    }
    return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([object class]), [parts componentsJoinedByString:@" "]];
}

static void report(SPTPlayerState *state) {
    static NSString *last;
    static NSDate *lastAt;
    if (lastAt && -lastAt.timeIntervalSinceNow < 1) return;
    NSString *line = summarize(state, 2);
    if ([line isEqualToString:last]) return;
    last = line;
    lastAt = NSDate.date;
    SGLogLong(@"player state", line);
    SPTPlayerTrack *track = state.track;
    if (track) SGLogLong(@"player track metadata", track.metadata.description);
}

%hook SPTEsperantoPlayer
- (id)state {
    id state = %orig;
    if (SGIsDebugBuild() && [state isKindOfClass:NSClassFromString(@"SPTPlayerState")]) report(state);
    return state;
}
%end

%hook _TtC28EncoreConsumerMobile_BaseKit14PlayButtonView
- (void)setEnabled:(BOOL)enabled {
    %orig;
    if (!SGIsDebugBuild() || enabled) return;
    static NSUInteger logged;
    if (logged++ >= 4) return;
    SGLogLong(@"play button disabled", [NSThread.callStackSymbols componentsJoinedByString:@"\n"]);
}
%end

%ctor {
    if (!SGIsDebugBuild()) return;
    %init;
    SGRequireClasses(@[@"SPTEsperantoPlayer", @"_TtC28EncoreConsumerMobile_BaseKit14PlayButtonView"]);
    SGLog(@"debug build: the player's state is logged as it changes");
}
