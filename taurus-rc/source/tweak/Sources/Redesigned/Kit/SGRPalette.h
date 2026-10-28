#import <UIKit/UIKit.h>

typedef struct {
    CGSize backdropSize;
    BOOL dissolve;
    BOOL amoled;
    // The colours of a moving field (SGRFlow.h): the artwork's main colour in each quarter and overall.
    BOOL flow;
    BOOL fill;
} SGRPaletteRequest;

@interface SGRPalette : NSObject
@property (nonatomic, readonly) UIColor *edgeColor;
@property (nonatomic, readonly) UIColor *fieldColor;
@property (nonatomic, readonly) UIImage *backdrop;   // nil unless asked for, at most 160px wide
@property (nonatomic, readonly) UIImage *dissolve;   // nil unless asked for, 96px wide
@property (nonatomic, readonly) NSArray<UIColor *> *flowColors;
@property (nonatomic, readonly) NSArray<UIImage *> *fillBlurs;
@property (nonatomic, readonly) UIColor *fillBackgroundColor;
// nil to the completion when the image has no bitmap to read (a symbol, a CIImage).
+ (void)paletteForImage:(UIImage *)image request:(SGRPaletteRequest)request completion:(void (^)(SGRPalette *palette))completion;

+ (void)tintForImage:(UIImage *)image surface:(UIColor *)surface completion:(void (^)(UIColor *tint))completion;
@end

UIColor *SGRFieldColorFor(UIColor *color);
