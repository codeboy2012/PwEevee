#import <os/lock.h>
#import "Core/SGCore.h"
#import "SGRedesign.h"

static os_unfair_lock sg_flagsLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, id> *sg_flags;

static id forcedNow(NSString *key) {
    os_unfair_lock_lock(&sg_flagsLock);
    id value = sg_flags[key];
    os_unfair_lock_unlock(&sg_flagsLock);
    return value;
}

void SGRedesignForceFlags(NSString *owner, NSDictionary<NSString *, id> *flags) {
    if (!flags.count) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGRegisterFlagForcer(YES, ^id(NSString *key) { return SGRedesignedUI() ? forcedNow(key) : nil; },
                             ^id(NSString *key) { return SGRedesignedUIStored() ? forcedNow(key) : nil; });
    });
    os_unfair_lock_lock(&sg_flagsLock);
    NSMutableDictionary *all = [sg_flags mutableCopy] ?: [NSMutableDictionary dictionary];
    [all addEntriesFromDictionary:flags];
    sg_flags = [all copy];
    os_unfair_lock_unlock(&sg_flagsLock);
    if (!SGRedesignedUI()) return;
    SGLog(@"redesign %@: forcing %lu flags", owner, (unsigned long)flags.count);
    [flags enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        id override = SGFlagOverride(key);
        if (override) SGLog(@"redesign %@: flag %@ forced %@ over the All flags override %@", owner, key, value, override);
    }];
}
