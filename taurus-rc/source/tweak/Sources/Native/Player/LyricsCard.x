#import "Core/SGCore.h"
#import "NowPlaying.h"
#import "Native/Appearance/Repaint.h"

static const CGFloat kCardRadius = 16;
static char kCardGlassKey;

#pragma mark - the card in the player's scroll list

// The cell around the card, the view Spotify paints and rounds.
static UIView *cellAround(UIView *view) {
    Class cell = NSClassFromString(@"_TtC12Element_List18CollectionViewCell");
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:cell]) return v;
    }
    return nil;
}

%hook _TtC22Lyrics_CardElementImpl8CardView
- (void)layoutSubviews {
    %orig;
    if (!SGFlag(SGKeyLyricsCard, NO)) return;
    UIView *cell = cellAround((UIView *)self);
    // A card PlayerDeclutter.x collapsed reports no height; leave it alone.
    if (!cell || cell.bounds.size.height < 40) return;
    sg_lyricsCardRoot = cell;
    SGStripBackgrounds(cell);
    UIVisualEffectView *glass = SGGlassFor(cell, &kCardGlassKey);
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    glass.frame = cell.bounds;
    glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    SGShapeGlass(glass, kCardRadius, NO);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC22Lyrics_CardElementImpl8CardView",
        @"_TtC12Element_List18CollectionViewCell",
    ]);
}
