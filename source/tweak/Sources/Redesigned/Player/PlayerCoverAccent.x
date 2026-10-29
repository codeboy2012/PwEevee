// Player redesign: Follow the cover, the player's accent from the cover of the song playing.
//
// Spotify draws its lit controls with the accent baked in (Kit/SGRAccent.x swaps it where a color is made): the
// shuffle and repeat icons are images drawn in it, the repeat dot is a view with it as its background, and the like
// checkmark is a Lottie animation whose shape layers are filled with it. None of them asks for the color again, so
// the player paints them itself, over Spotify's bottom stack (the title row with the like, the progress bar, the
// controls and the footer): an image drawn in the accent is tinted from its own shape, a background or a shape layer
// in the accent takes the color, and every original is kept to give back. It paints whenever the cover's color
// changes and whenever the stack or one of its buttons lays out, which is when Spotify hands a button its new state.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

static NSInteger sg_cover = -1;   // 0xRRGGBB while a cover gives one, else -1
static __weak UIView *sg_stack;   // the bottom stack last painted
static char kOriginalKey, kTintedKey, kAccentImageKey, kOriginalFillKey, kOriginalStrokeKey;

BOOL SGRPlayerFollowsCover(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGHidden(SGRKeyPlayerFollowsCover); });
    return on;
}

static void unpack(NSInteger rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

static UIColor *coverColor(void) {
    CGFloat r, g, b;
    unpack(sg_cover, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

// Whether a color is the accent's: its hue within kHueNear, and colorful. Darker shades of it count (a pressed state).
static const CGFloat kHueNear = 0.05, kColorful = 0.35;
static BOOL accentLike(CGFloat r, CGFloat g, CGFloat b) {
    static CGFloat accentHue = -1;
    if (accentHue < 0) {
        CGFloat ar, ag, ab, s, v, a;
        unpack(SGRAccentRGB(), &ar, &ag, &ab);
        [[UIColor colorWithRed:ar green:ag blue:ab alpha:1] getHue:&accentHue saturation:&s brightness:&v alpha:&a];
    }
    CGFloat h, s, v, a;
    if (![[UIColor colorWithRed:r green:g blue:b alpha:1] getHue:&h saturation:&s brightness:&v alpha:&a]) return NO;
    CGFloat d = fabs(h - accentHue);
    return MIN(d, 1 - d) < kHueNear && s > kColorful && v > 0.2;
}

static BOOL colorAccentLike(UIColor *color) {
    CGFloat r, g, b, a;
    return color && [color getRed:&r green:&g blue:&b alpha:&a] && a > 0.5 && accentLike(r, g, b);
}

static BOOL cgAccentLike(CGColorRef color) {
    if (!color || CGColorGetNumberOfComponents(color) != 4) return NO;
    const CGFloat *c = CGColorGetComponents(color);
    return c[3] > 0.5 && accentLike(c[0], c[1], c[2]);
}

// Whether an image is drawn in the accent: the average of its opaque pixels, read once at 16 by 16 and kept on it.
static BOOL imageAccentLike(UIImage *image) {
    NSNumber *known = objc_getAssociatedObject(image, &kAccentImageKey);
    if (known) return known.boolValue;
    enum { kSide = 16 };
    uint8_t pixels[kSide * kSide * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    BOOL accent = NO;
    if (context && image.CGImage) {
        CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), image.CGImage);
        double r = 0, g = 0, b = 0, n = 0;
        for (int i = 0; i < kSide * kSide; i++) {
            uint8_t alpha = pixels[i * 4 + 3];
            if (alpha < 128) continue;
            r += pixels[i * 4] / (double)alpha;
            g += pixels[i * 4 + 1] / (double)alpha;
            b += pixels[i * 4 + 2] / (double)alpha;
            n++;
        }
        accent = n >= 4 && accentLike(r / n, g / n, b / n);
    }
    if (context) CGContextRelease(context);
    objc_setAssociatedObject(image, &kAccentImageKey, @(accent), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return accent;
}

static void paintImageView(UIImageView *view) {
    UIImage *image = view.image, *tinted = objc_getAssociatedObject(view, &kTintedKey);
    UIImage *original = image == tinted ? objc_getAssociatedObject(view, &kOriginalKey) : image;
    if (!original) return;
    if (sg_cover < 0 || !imageAccentLike(original)) {
        if (image == tinted && tinted) view.image = original;
        objc_setAssociatedObject(view, &kTintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (image == tinted && tinted) return;
    UIImage *made = [original imageWithTintColor:coverColor() renderingMode:UIImageRenderingModeAlwaysOriginal];
    objc_setAssociatedObject(view, &kOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kTintedKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.image = made;
}

static void paintBackground(UIView *view) {
    UIColor *original = objc_getAssociatedObject(view, &kOriginalKey);
    UIColor *current = view.backgroundColor;
    if (!original && !colorAccentLike(current)) return;
    if (!original) {
        original = current;
        objc_setAssociatedObject(view, &kOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    view.backgroundColor = sg_cover < 0 ? original : coverColor();
}

static void paintShape(CAShapeLayer *layer) {
    for (int stroke = 0; stroke < 2; stroke++) {
        void *key = stroke ? &kOriginalStrokeKey : &kOriginalFillKey;
        id original = objc_getAssociatedObject(layer, key);
        CGColorRef current = stroke ? layer.strokeColor : layer.fillColor;
        if (!original && !cgAccentLike(current)) continue;
        if (!original) {
            original = (__bridge id)current;
            objc_setAssociatedObject(layer, key, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        CGColorRef color = sg_cover < 0 ? (__bridge CGColorRef)original : coverColor().CGColor;
        if (stroke) layer.strokeColor = color;
        else layer.fillColor = color;
    }
}

static char kOriginalAnimationsKey;
static NSString *const kPaintedKey = @"spotifyglass.coverPainted";

// Lottie's Core Animation renderer colors a shape with a keyframe animation on fillColor or strokeColor, which shows
// over the layer's own value: those keyframes in the accent take the cover's color, the animations as Lottie made
// them kept by key to give back.
static void paintAnimations(CALayer *layer) {
    NSMutableDictionary<NSString *, CAAnimation *> *originals = objc_getAssociatedObject(layer, &kOriginalAnimationsKey);
    for (NSString *key in layer.animationKeys) {
        CAAnimation *animation = [layer animationForKey:key];
        if (![animation isKindOfClass:CAKeyframeAnimation.class]) continue;
        CAKeyframeAnimation *keyframes = (CAKeyframeAnimation *)animation;
        if (![keyframes.keyPath isEqualToString:@"fillColor"] && ![keyframes.keyPath isEqualToString:@"strokeColor"]) continue;
        // A layer copies what it is given, so a painted animation is told by the cover it carries, not by identity.
        NSNumber *painted = [animation valueForKey:kPaintedKey];
        CAKeyframeAnimation *base = keyframes;
        if (painted) {
            CAKeyframeAnimation *original = (CAKeyframeAnimation *)originals[key];
            if (!original) continue;
            if (sg_cover < 0) {
                [layer addAnimation:original forKey:key];
                [originals removeObjectForKey:key];
                continue;
            }
            if (painted.integerValue == sg_cover) continue;
            base = original;
        } else {
            if (sg_cover < 0) continue;
            if (!originals) {
                originals = [NSMutableDictionary dictionary];
                objc_setAssociatedObject(layer, &kOriginalAnimationsKey, originals, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            originals[key] = keyframes;
        }
        BOOL any = NO;
        NSMutableArray *values = [NSMutableArray arrayWithCapacity:base.values.count];
        for (id value in base.values) {
            BOOL accent = CFGetTypeID((__bridge CFTypeRef)value) == CGColorGetTypeID() && cgAccentLike((__bridge CGColorRef)value);
            any |= accent;
            [values addObject:accent ? (__bridge id)coverColor().CGColor : value];
        }
        if (!any) {
            [originals removeObjectForKey:key];
            continue;
        }
        CAKeyframeAnimation *made = [base copy];
        made.values = values;
        [made setValue:@(sg_cover) forKey:kPaintedKey];
        [layer addAnimation:made forKey:key];
    }
}

static void paintLayers(CALayer *layer) {
    if ([layer isKindOfClass:CAShapeLayer.class]) paintShape((CAShapeLayer *)layer);
    if (layer.animationKeys.count) paintAnimations(layer);
    for (CALayer *sublayer in layer.sublayers) paintLayers(sublayer);
}

void SGRPlayerPaintCover(UIView *stack) {
    if (!SGRPlayerFollowsCover() || !stack) return;
    if (stack.superview && [stack isKindOfClass:UIStackView.class]) sg_stack = stack;
    static Class lottie;
    if (!lottie) lottie = NSClassFromString(@"Lottie.LottieAnimationView");
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    SGForEachView(stack, ^(UIView *view) {
        if ([view.accessibilityIdentifier isEqualToString:SGRPlainCheckIdentifier]) view.tintColor = sg_cover < 0 ? SGRAccent() : coverColor();
        else if ([view isKindOfClass:UIImageView.class]) paintImageView((UIImageView *)view);
        else if (lottie && [view isKindOfClass:lottie]) paintLayers(view.layer);
        else paintBackground(view);
    });
    [CATransaction commit];
}

void SGRPlayerSetCoverAccent(UIColor *cover) {
    NSInteger rgb = -1;
    CGFloat h, s, v, a;
    if ([cover getHue:&h saturation:&s brightness:&v alpha:&a] && s >= 0.15) {
        // Bright and clear enough to read on the dark player, the hue kept.
        UIColor *bright = [UIColor colorWithHue:h saturation:MIN(0.85, MAX(0.45, s)) brightness:MAX(0.9, v) alpha:1];
        CGFloat r, g, b;
        [bright getRed:&r green:&g blue:&b alpha:&a];
        rgb = ((NSInteger)lround(r * 255) << 16) | ((NSInteger)lround(g * 255) << 8) | (NSInteger)lround(b * 255);
    }
    if (rgb != sg_cover) {
        sg_cover = rgb;
        SGLog(@"redesign player: follow the cover %@", rgb < 0 ? @"gives the accent back (a gray cover)" : [NSString stringWithFormat:@"paints #%06lX", (long)rgb]);
    }
    SGRPlayerPaintCover(sg_stack);
}

// A button in the player's stack laid out: Spotify hands it a new state's icon or animation this way.
%hook UIButton
- (void)layoutSubviews {
    %orig;
    UIView *stack = sg_stack;
    if (stack && (sg_cover >= 0 || objc_getAssociatedObject(self, &kTintedKey)) && [(UIView *)self isDescendantOfView:stack]) {
        SGRPlayerPaintCover((UIView *)self);
    }
}

- (void)setImage:(UIImage *)image forState:(UIControlState)state {
    %orig;
    UIView *stack = sg_stack;
    if (stack && [(UIView *)self isDescendantOfView:stack]) SGRPlayerPaintCover((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGRPlayerFollowsCover()) return;
    %init;
}
