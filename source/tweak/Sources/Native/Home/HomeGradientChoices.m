#import "Core/SGCore.h"
#import "Home.h"

static NSDictionary *choiceDef(SGHomeChoice choice) {
    static NSDictionary<NSNumber *, NSDictionary *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @(SGHomeChoiceTint): @{
                @"key": @"spotifyglass.homeGradientTint",
                @"default": @0,
                @"names": @[@"Spotify green", @"Teal", @"Blue", @"Indigo", @"Purple", @"Pink",
                            @"Red", @"Amber"],
            },
            @(SGHomeChoiceStrength): @{
                @"key": @"spotifyglass.homeGradientStrength",
                @"default": @1,
                @"names": @[@"Subtle", @"Medium", @"Bold"],
            },
            @(SGHomeChoiceHeight): @{
                @"key": @"spotifyglass.homeGradientHeight",
                @"default": @1,
                @"names": @[@"Short", @"Medium", @"Tall", @"The whole screen"],
            },
        };
    });
    return table[@(choice)] ?: table[@(SGHomeChoiceTint)];
}

NSArray<NSString *> *SGHomeChoiceNames(SGHomeChoice choice) {
    return choiceDef(choice)[@"names"];
}

NSString *SGHomeChoiceKey(SGHomeChoice choice) {
    return choiceDef(choice)[@"key"];
}

NSInteger SGHomeChoiceDefault(SGHomeChoice choice) {
    return [choiceDef(choice)[@"default"] integerValue];
}

NSInteger SGHomeChoiceValue(SGHomeChoice choice) {
    NSDictionary *def = choiceDef(choice);
    NSInteger fallback = [def[@"default"] integerValue];
    NSInteger index = SGInt(def[@"key"], fallback);
    return index >= 0 && index < (NSInteger)[def[@"names"] count] ? index : fallback;
}
