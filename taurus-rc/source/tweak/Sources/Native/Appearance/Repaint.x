// Keeps the areas the native look's tweaks stripped transparent when Spotify repaints them.
#import "Core/SGCore.h"
#import "Repaint.h"

__weak UIView *sg_lyricsCardRoot = nil;
__weak UIView *sg_lyricsPageRoot = nil;
__weak UIView *sg_homeRoot = nil;
__weak UIView *sg_npvBackdropRoot = nil;

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    if (color && (sg_lyricsCardRoot || sg_lyricsPageRoot || sg_homeRoot || sg_npvBackdropRoot)) {
        UIView *view = (UIView *)self.delegate;
        if ([view isKindOfClass:UIView.class] && view.layer == self && !SGKeepsColor(view)) {
            if (SGIsInside(view, sg_lyricsCardRoot) || SGIsInside(view, sg_lyricsPageRoot)) {
                color = NULL;
            } else if (SGIsInside(view, sg_npvBackdropRoot)) {
                // The album colour arrives on the plane per track, outside any layout pass.
                color = NULL;
            } else if (SGIsBaseSurface(color) && SGIsInside(view, sg_homeRoot)) {
                color = NULL;
            }
        }
    }
    %orig(color);
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
}
