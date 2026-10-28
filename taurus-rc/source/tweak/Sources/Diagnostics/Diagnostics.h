#import <Foundation/Foundation.h>

void SGDriverSingSetEnabled(BOOL enabled);

BOOL SGIsDebugBuild(void);
NSString *SGScreenTree(void);
void SGDumpScreen(NSString *reason);
