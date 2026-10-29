#import <Foundation/Foundation.h>

typedef id (^SGFlagForcer)(NSString *key);

void SGRegisterFlagForcer(BOOL beatsOverride, SGFlagForcer atLaunch, SGFlagForcer locked);

// The value the provider hands Spotify: forcers that beat an override, the override, then the rest.
id SGForcedFlagValue(NSString *key);
id SGLockedFlagValue(NSString *key, BOOL *beatsOverride);
