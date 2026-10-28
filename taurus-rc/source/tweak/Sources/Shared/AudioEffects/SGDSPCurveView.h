#import <UIKit/UIKit.h>

@interface SGDSPCurveView : UIView
// SGKeyDSPEqualizerGains or SGKeyDSPCompanderGains.
- (instancetype)initWithKey:(NSString *)key;
// The stored gains again, and their curve.
- (void)reload;
// The height the table gives its row.
+ (CGFloat)heightForKey:(NSString *)key;
@end
