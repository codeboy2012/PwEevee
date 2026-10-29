#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

// The tint the glass takes of the card's colour, and how dark the far corner of the colour under it gets.
static const CGFloat kTintAlpha = 0.35;
static const CGFloat kFarBrightness = 0.55;
// Where the title's top leading corner moves to, clear of the larger corner.
static const CGFloat kTitleInset = 12;
static const CGFloat kPressScale = 0.96;

static char kPartsKey, kRoundedKey;

@interface UIView (SGREncoreBox)
- (BOOL)isHighlighted;
@end

@interface SGRSearchCardPlate : UIView
@end

@implementation SGRSearchCardPlate
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

@interface SGRSearchCardParts : NSObject
@property (nonatomic) SGRSearchCardPlate *plate;
@property (nonatomic) UIVisualEffectView *glass;
@property (nonatomic) UIColor *color;
@end

@implementation SGRSearchCardParts
@end

static void logOnce(NSString *what) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:what]) return;
    [logged addObject:what];
    SGLog(@"redesign search: %@", what);
}

static BOOL isCategoryCard(UIView *box) {
    return [box.superview.accessibilityIdentifier isEqualToString:@"Components.UI.CategoryCardBrowse"];
}

// The Box's animationLayer: a shape layer no view owns.
static CAShapeLayer *fillLayerOf(UIView *box) {
    for (CALayer *layer in box.layer.sublayers) {
        if ([layer isKindOfClass:CAShapeLayer.class] && ![layer.delegate isKindOfClass:UIView.class]) return (CAShapeLayer *)layer;
    }
    return nil;
}

// Any other shape layer of the Box's that paints goes too: the glass is the card's only surface.
static void hideFills(UIView *box) {
    for (CALayer *layer in box.layer.sublayers) {
        if (![layer isKindOfClass:CAShapeLayer.class] || [layer.delegate isKindOfClass:UIView.class] || layer.hidden) continue;
        if (((CAShapeLayer *)layer).fillColor) layer.hidden = YES;
    }
}

// The Box's content view: its one subview of its own size that clips.
static UIView *contentOf(UIView *box) {
    for (UIView *sub in box.subviews) {
        if (sub.clipsToBounds && CGSizeEqualToSize(sub.bounds.size, box.bounds.size)) return sub;
    }
    return nil;
}

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
}

static UIColor *darker(UIColor *color) {
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
    if (![color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) return color;
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness * kFarBrightness alpha:alpha];
}

static BOOL glassAllowed(void) {
    if (SGRReduceTransparency()) return NO;
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static SGRSearchCardParts *partsIn(UIView *box, UIView *content) {
    SGRSearchCardParts *parts = objc_getAssociatedObject(box, &kPartsKey);
    if (!parts) {
        parts = [SGRSearchCardParts new];
        SGRSearchCardPlate *plate = [SGRSearchCardPlate new];
        plate.userInteractionEnabled = NO;
        plate.accessibilityElementsHidden = YES;
        plate.layer.zPosition = -2;
        CAGradientLayer *gradient = (CAGradientLayer *)plate.layer;
        gradient.startPoint = CGPointMake(0, 0);
        gradient.endPoint = CGPointMake(1, 1);
        parts.plate = plate;
        objc_setAssociatedObject(box, &kPartsKey, parts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Behind the cover and the title whatever order Spotify keeps its own views in, by depth.
    if (parts.plate.superview != content) [content insertSubview:parts.plate atIndex:0];
    if (glassAllowed() && !parts.glass) {
        UIVisualEffectView *glass = [UIVisualEffectView new];
        glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        glass.userInteractionEnabled = NO;
        glass.accessibilityElementsHidden = YES;
        glass.layer.zPosition = -1;
        parts.glass = glass;
        parts.color = nil;
    }
    if (parts.glass && parts.glass.superview != content) [content insertSubview:parts.glass aboveSubview:parts.plate];
    if (parts.glass) parts.glass.hidden = !glassAllowed();
    return parts;
}

static void paint(SGRSearchCardParts *parts, UIColor *color) {
    if (parts.color && CGColorEqualToColor(parts.color.CGColor, color.CGColor)) return;
    parts.color = color;
    ((CAGradientLayer *)parts.plate.layer).colors = @[(id)color.CGColor, (id)darker(color).CGColor];
    if (@available(iOS 26.0, *)) {
        if (parts.glass) {
            UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
            effect.tintColor = [color colorWithAlphaComponent:kTintAlpha];
            parts.glass.effect = effect;
        }
    }
}

// The title's own position, before the move, is where Spotify's layout put its centre.
static void moveTitleIn(UIView *content) {
    for (UIView *sub in content.subviews) {
        if (![NSStringFromClass(sub.class) containsString:@"EncoreLabel"]) continue;
        CGPoint origin = CGPointMake(sub.center.x - sub.bounds.size.width / 2, sub.center.y - sub.bounds.size.height / 2);
        CGAffineTransform moved = CGAffineTransformMakeTranslation(MAX(0, kTitleInset - origin.x), MAX(0, kTitleInset - origin.y));
        if (!CGAffineTransformEqualToTransform(sub.transform, moved)) sub.transform = moved;
    }
}

static void roundCover(UIView *content) {
    for (UIView *sub in content.subviews) {
        if (![sub.accessibilityIdentifier isEqualToString:@"Encore.ImageView"]) continue;
        for (UIView *image in sub.subviews) {
            if (![image isKindOfClass:UIImageView.class]) continue;
            roundCorners(image, SGRRadiusThumb);
            if (!image.layer.masksToBounds) image.layer.masksToBounds = YES;
        }
    }
}

static void style(UIView *box) {
    if (!isCategoryCard(box)) return;
    UIView *content = contentOf(box);
    CAShapeLayer *fill = fillLayerOf(box);
    if (!content || !fill) {
        logOnce([NSString stringWithFormat:@"a category card without its %@, left as Spotify's", content ? @"fill layer" : @"content view"]);
        return;
    }
    // A pressed card's fill is Spotify's pressed shade; the colour is taken while it is not pressed.
    CGColorRef fillColor = fill.fillColor;
    SGRSearchCardParts *parts = partsIn(box, content);
    if (fillColor && CGColorGetAlpha(fillColor) > 0 && ![box isHighlighted]) paint(parts, [UIColor colorWithCGColor:fillColor]);
    if (!parts.color) return;
    hideFills(box);

    if (content.layer.cornerRadius != SGRRadiusCard && objc_getAssociatedObject(box, &kRoundedKey)) {
        logOnce([NSString stringWithFormat:@"Spotify set a card's content radius back to %.0f; the Box's corner holds", content.layer.cornerRadius]);
    }
    objc_setAssociatedObject(box, &kRoundedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    roundCorners(box, SGRRadiusCard);
    if (!box.layer.masksToBounds) box.layer.masksToBounds = YES;
    roundCorners(content, SGRRadiusCard);
    CGRect bounds = content.bounds;
    if (!CGRectEqualToRect(parts.plate.frame, bounds)) parts.plate.frame = bounds;
    if (parts.glass && !CGRectEqualToRect(parts.glass.frame, bounds)) {
        parts.glass.frame = bounds;
        SGShapeGlass(parts.glass, SGRRadiusCard, NO);
    }
    moveTitleIn(content);
    roundCover(content);
    logOnce(parts.glass ? @"category cards on tinted glass" : @"category cards on their colour, no glass");
}

%hook _TtCE16Encore_LayoutKitO16EncoreFoundation6Encore3Box
- (void)layoutSubviews {
    %orig;
    style((UIView *)self);
}

- (void)setHighlighted:(BOOL)highlighted {
    UIView *box = (UIView *)self;
    BOOL was = [box isHighlighted];
    %orig;
    if (was == highlighted || !isCategoryCard(box)) return;
    SGRAnimate(SGRMotionPress, ^{
        box.transform = highlighted ? CGAffineTransformMakeScale(kPressScale, kPressScale) : CGAffineTransformIdentity;
    }, nil);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtCE16Encore_LayoutKitO16EncoreFoundation6Encore3Box"]);
}
