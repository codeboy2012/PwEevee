#import <Foundation/Foundation.h>

#define SGKeyStock @"spotifyglass.stock"

BOOL SGFlag(NSString *key, BOOL fallback);
BOOL SGEnabled(NSString *key);   // an unset switch is on
BOOL SGHidden(NSString *key);    // an unset switch is off
void SGSetEnabled(NSString *key, BOOL on);

NSInteger SGInt(NSString *key, NSInteger fallback);
void SGSetInt(NSString *key, NSInteger value);

extern NSString *const SGFlagOverridePrefix;
id SGFlagOverride(NSString *key);
void SGSetFlagOverride(NSString *key, id value);

void SGMigrateKey(NSString *from, NSString *to);

// Quits Spotify so the hooks read the switches afresh on the next launch; the writes reach cfprefsd first.
void SGRestartSpotify(void);
