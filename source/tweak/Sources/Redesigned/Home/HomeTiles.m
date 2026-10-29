#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Home.h"

// How far the cover sits in from the tile's top, bottom and leading edges, and its corners there.
static const CGFloat kInset = 6, kCoverRadius = 11, kPillRadius = 18;
// The original look, when the Home page switch is off.
static const CGFloat kPlainInset = 5, kPlainCoverRadius = 4;

static char kSurfaceKey, kImageKey, kShownKey;

// Tints already worked out, by the image object while it lives (main thread only).
static NSMapTable<UIImage *, UIColor *> *tints(void) {
    static NSMapTable *table;
    if (!table) table = [NSMapTable weakToStrongObjectsMapTable];
    return table;
}

static UIColor *untinted(void) {
    static UIColor *color;
    if (!color) color = SGRElevated(UIColor.blackColor);
    return color;
}

@interface SGRTileParts : NSObject
@property (nonatomic, weak) UIView *fill;
@property (nonatomic, weak) UIView *square;
@property (nonatomic, weak) UIImageView *cover;
@end

@implementation SGRTileParts
@end

static SGRTileParts *partsOf(UIView *tile) {
    UIView *holder = SGRFindByIdentifier(tile, @"Encore.ImageView", &kImageKey);
    SGRTileParts *parts = [SGRTileParts new];
    for (UIView *sub in holder.subviews) {
        if ([sub isKindOfClass:UIImageView.class]) parts.cover = (UIImageView *)sub;
    }
    parts.square = holder.superview;
    UIView *first = tile.subviews.firstObject;
    if (object_getClass(first) == UIView.class && CGRectEqualToRect(first.frame, tile.bounds)) parts.fill = first;
    return parts;
}

static UIView *surfaceIn(UIView *tile, UIView *fill) {
    UIView *surface = objc_getAssociatedObject(tile, &kSurfaceKey);
    if (!surface) {
        surface = [UIView new];
        surface.userInteractionEnabled = NO;
        surface.accessibilityElementsHidden = YES;
        surface.backgroundColor = untinted();
        objc_setAssociatedObject(tile, &kSurfaceKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (surface.superview != tile) {
        if (fill) [tile insertSubview:surface aboveSubview:fill];
        else [tile insertSubview:surface atIndex:0];
    }
    if (!CGRectEqualToRect(surface.frame, tile.bounds)) surface.frame = tile.bounds;
    if (!SGRHomeGlassStyle()) return surface;
    CALayer *layer = surface.layer;
    CGFloat radius = MIN(kPillRadius, tile.bounds.size.height / 2);
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    layer.masksToBounds = YES;
    layer.borderWidth = 1;
    layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
    CAGradientLayer *sheen = nil;
    for (CALayer *sub in layer.sublayers) if ([sub isKindOfClass:CAGradientLayer.class]) sheen = (CAGradientLayer *)sub;
    if (!sheen) {
        sheen = [CAGradientLayer layer];
        sheen.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.20].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.02].CGColor,
                         (id)[UIColor colorWithWhite:0 alpha:0.18].CGColor];
        [layer addSublayer:sheen];
    }
    if (!CGRectEqualToRect(sheen.frame, surface.bounds)) sheen.frame = surface.bounds;
    return surface;
}

static void inset(UIView *square) {
    CGFloat side = square.bounds.size.height;
    if (side <= kInset * 4) return;
    BOOL glass = SGRHomeGlassStyle();
    CGFloat inset = glass ? kInset : kPlainInset;
    CGFloat scale = (side - inset * 2) / side;
    CGAffineTransform shrink = CGAffineTransformMakeScale(scale, scale);
    if (!CGAffineTransformEqualToTransform(square.transform, shrink)) square.transform = shrink;
    CALayer *layer = square.layer;
    // The radius is drawn scaled with the square.
    CGFloat radius = (glass ? kCoverRadius : kPlainCoverRadius) / scale;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;

    CGAffineTransform follow = CGAffineTransformMakeTranslation(-square.bounds.size.width * (1 - scale) / 2, 0);
    BOOL after = NO;
    for (UIView *sibling in square.superview.subviews) {
        if (sibling == square) {
            after = YES;
            continue;
        }
        if (after && !CGAffineTransformEqualToTransform(sibling.transform, follow)) sibling.transform = follow;
    }
}

// The pill's colour: the cover's tint taken up to a glass-like, saturated level.
static UIColor *vivid(UIColor *color) {
    if (!color) return SGRHomeGlassStyle() ? [UIColor colorWithWhite:1 alpha:0.14] : untinted();
    if (!SGRHomeGlassStyle()) return color;
    CGFloat h, sat, b, a;
    if (![color getHue:&h saturation:&sat brightness:&b alpha:&a]) return color;
    return [UIColor colorWithHue:h saturation:MIN(1, sat * 1.15) brightness:MAX(b, 0.12) * 3.2 > 0.6 ? 0.6 : MAX(b, 0.12) * 3.2 alpha:0.62];
}

static void tint(UIView *tile, UIView *surface, UIColor *color, BOOL animated) {
    color = vivid(color);
    if ([surface.backgroundColor isEqual:color]) return;
    if (!animated || !tile.window) {
        surface.backgroundColor = color;
        return;
    }
    SGRAnimate(SGRMotionFade, ^{ surface.backgroundColor = color; }, nil);
}

static void refresh(UIView *tile) {
    SGRTileParts *parts = partsOf(tile);
    UIImageView *cover = parts.cover;
    UIView *square = parts.square;
    if (!cover || !square || square.bounds.size.width < 20 || tile.bounds.size.width <= square.bounds.size.width) return;
    UIView *surface = surfaceIn(tile, parts.fill);
    inset(square);

    UIImage *image = cover.image;
    if (!image) {
        objc_setAssociatedObject(tile, &kShownKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tint(tile, surface, nil, NO);
        return;
    }
    UIColor *known = [tints() objectForKey:image];
    if (known) {
        objc_setAssociatedObject(tile, &kShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tint(tile, surface, known, YES);
        return;
    }
    if (objc_getAssociatedObject(tile, &kShownKey) == image) return;
    objc_setAssociatedObject(tile, &kShownKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    __weak UIView *weakTile = tile;
    [SGRPalette tintForImage:image surface:untinted() completion:^(UIColor *color) {
        UIView *strongTile = weakTile;
        if (color) [tints() setObject:color forKey:image];
        // A tile reused for another cover in the meantime has asked for that one.
        if (!strongTile || objc_getAssociatedObject(strongTile, &kShownKey) != image) return;
        tint(strongTile, surfaceIn(strongTile, partsOf(strongTile).fill), color, YES);
    }];
}

void SGRHomeStyleTile(UIView *tile) {
    CFTimeInterval began = SGRHomeProbeBegin();
    UIImageView *cover = partsOf(tile).cover;
    if (!cover) return;
    __weak UIView *weakTile = tile;
    // The block is replaced on every pass, so a cover taken into another tile tells the tile it is in now.
    SGRObserveImage(cover, ^(UIImageView *view) {
        UIView *strongTile = weakTile;
        if (strongTile && [view isDescendantOfView:strongTile]) refresh(strongTile);
    });
    refresh(tile);
    SGRHomeProbeEnd(SGRHomeProbeTiles, began);
}
