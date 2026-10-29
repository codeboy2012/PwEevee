#import <UIKit/UIKit.h>

@interface SGRGlyphView : UIImageView
- (instancetype)initWithSymbol:(NSString *)symbol pointSize:(CGFloat)size weight:(UIImageSymbolWeight)weight;
@property (nonatomic, readonly) NSString *symbol;
- (void)setSymbol:(NSString *)symbol animated:(BOOL)animated;
@end

@interface SGRGlyphButton : UIControl
+ (instancetype)buttonWithSymbol:(NSString *)symbol pointSize:(CGFloat)size title:(NSString *)accessibilityTitle;
@property (nonatomic, readonly) SGRGlyphView *glyph;
@property (nonatomic, copy) void (^onTap)(void);
@end
