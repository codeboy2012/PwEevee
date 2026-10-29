#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SGFlagType) { SGFlagUnknown, SGFlagBool, SGFlagInt, SGFlagEnum };
typedef struct { const char *key; SGFlagType type; long value, lower, upper; } SGFlagDef;
extern const SGFlagDef SGFlagTable[];
extern const NSUInteger SGFlagCount;

UIViewController *SGAllFlagsPage(void);
UIViewController *SGLabsPage(void);
