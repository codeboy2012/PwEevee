#import <UIKit/UIKit.h>

@interface SGGlowSwitch : UIControl
@property (nonatomic, getter=isOn) BOOL on;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
@end

NSArray<UIColor *> *SGGlowRainbowColors(void);
