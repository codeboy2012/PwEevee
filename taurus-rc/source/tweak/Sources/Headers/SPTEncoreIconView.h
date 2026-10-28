#import <UIKit/UIKit.h>

@interface SPTEncoreIconView : UIView
- (instancetype)initWithIcon:(id)icon;
- (void)setForegroundColor:(UIColor *)color;
- (void)setActiveForegroundColor:(UIColor *)color;
- (void)setIsActive:(BOOL)active;
- (BOOL)isActive;
@end

@interface NSObject (SPTEncoreIcon)
- (NSString *)name;
@end
