#import <Foundation/Foundation.h>

// Only these context restrictions may be overridden. An empty, malformed or mixed set
// must not turn a normal command into one that bypasses the player's other restrictions.
static inline BOOL SGRadioModeReasonsOnly(NSSet *reasons) {
    if (![reasons isKindOfClass:NSSet.class] || !reasons.count) return NO;
    for (id reason in reasons) {
        if (![reason isKindOfClass:NSString.class] ||
            (![(NSString *)reason isEqualToString:@"radio"] &&
             ![(NSString *)reason isEqualToString:@"endless_context"] &&
             ![(NSString *)reason isEqualToString:@"autoplay"])) return NO;
    }
    return YES;
}
