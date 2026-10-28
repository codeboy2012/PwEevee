#import "Core/SGCore.h"
#import "SGRGlass.h"
#import "SGRTokens.h"

typedef NS_ENUM(NSInteger, SGRGlassMode) {
    SGRGlassModeGlass,
    SGRGlassModeBlur,
    SGRGlassModeSolid,
};

static SGRGlassMode glassMode(void) {
    if (SGRReduceTransparency()) return SGRGlassModeSolid;
    if (@available(iOS 26.0, *)) return SGRGlassModeGlass;
    return SGRGlassModeBlur;
}

static UIView *newShape(SGRGlassMode mode) {
    UIView *shape;
    switch (mode) {
        case SGRGlassModeGlass:
            shape = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
            break;
        case SGRGlassModeBlur:
            shape = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
            break;
        case SGRGlassModeSolid:
            shape = [UIView new];
            shape.backgroundColor = SGRSolidGlassFill();
            break;
    }
    shape.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    shape.userInteractionEnabled = NO;
    return shape;
}

#pragma mark - inside a control

static char kInsideModeKey, kFilmKey;

// The film that makes a shape prominent, inside the effect's own content view so the corners clip it.
static void keepFilm(UIView *shape, BOOL prominent, SGRGlassMode mode) {
    if (mode == SGRGlassModeSolid) {
        shape.backgroundColor = prominent ? [SGRSolidGlassFill() colorWithAlphaComponent:0.26] : SGRSolidGlassFill();
        return;
    }
    UIView *film = objc_getAssociatedObject(shape, &kFilmKey);
    if (!prominent) {
        film.hidden = YES;
        return;
    }
    UIView *content = [shape isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)shape).contentView : shape;
    if (!film) {
        film = [UIView new];
        film.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        film.userInteractionEnabled = NO;
        film.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(shape, &kFilmKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    film.hidden = NO;
    if (film.superview != content) [content addSubview:film];
    if (!CGRectEqualToRect(film.frame, content.bounds)) {
        film.frame = content.bounds;
        film.layer.cornerRadius = MIN(content.bounds.size.width, content.bounds.size.height) / 2;
        film.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

static UIView *glassInside(UIView *control, const void *key, CGSize size, BOOL capsule, BOOL prominent) {
    if (!control || !key) return nil;
    SGRGlassMode mode = glassMode();
    UIView *shape = objc_getAssociatedObject(control, key);
    if (shape && [objc_getAssociatedObject(shape, &kInsideModeKey) integerValue] != mode) {
        [shape removeFromSuperview];
        shape = nil;
    }
    if (!shape) {
        shape = newShape(mode);
        shape.accessibilityElementsHidden = YES;
        shape.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(shape, &kInsideModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(control, key, shape, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (shape.superview != control) [control addSubview:shape];
    if (control.subviews.firstObject != shape) [control insertSubview:shape atIndex:0];
    shape.hidden = size.width <= 0 || size.height <= 0;
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    if (!CGRectEqualToRect(shape.bounds, bounds)) {
        shape.bounds = bounds;
        SGShapeGlass(shape, MIN(size.width, size.height) / 2, capsule);
    }
    keepFilm(shape, prominent, mode);
    CGPoint middle = CGPointMake(CGRectGetMidX(control.bounds), CGRectGetMidY(control.bounds));
    if (!CGPointEqualToPoint(shape.center, middle)) shape.center = middle;
    return shape;
}

UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side) {
    return glassInside(control, key, CGSizeMake(side, side), YES, NO);
}

UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent) {
    return glassInside(control, key, size, YES, prominent);
}

static UIVisualEffect *shapeEffect(SGRGlassMode mode) {
    switch (mode) {
        case SGRGlassModeGlass: return SGGlassEffect();
        case SGRGlassModeBlur: return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        case SGRGlassModeSolid: return nil;
    }
    return nil;
}

void SGRShowGlass(UIView *shape, BOOL shown) {
    if (!shape) return;
    if (![shape isKindOfClass:UIVisualEffectView.class]) {
        shape.alpha = shown ? 1 : 0;
        return;
    }
    ((UIVisualEffectView *)shape).effect = shown ? shapeEffect(glassMode()) : nil;
}
