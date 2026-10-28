#import <Foundation/Foundation.h>
#import <os/log.h>

void SGLogMessage(NSString *message);
#define SGLog(fmt, ...) SGLogMessage([NSString stringWithFormat:(fmt), ##__VA_ARGS__])

// Long dumps, split into numbered parts under the unified log's size cap.
void SGLogLong(NSString *tag, NSString *text);
NSString *SGLogContents(void);
// Logs every class of the list that this Spotify does not have; a feature calls it from its %ctor.
void SGRequireClasses(NSArray<NSString *> *names);
