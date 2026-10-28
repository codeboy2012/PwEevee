#import "Core/SGCore.h"
#import "Playlist.h"

@interface NSObject (SGPlaylistHeader)
- (NSLayoutConstraint *)headerViewHeightConstraint;
- (NSLayoutConstraint *)layoutGuideHeightConstraint;
@end

static UIView *viewNamed(UIView *root, NSString *marker) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [NSStringFromClass(v.class) containsString:marker]) found = v;
    });
    return found;
}

// A prefix, not the whole identifier: the download button carries its state in the tail.
static UIView *identNamed(UIView *root, NSString *ident) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v.accessibilityIdentifier hasPrefix:ident]) found = v;
    });
    return found;
}

// Only ever hides. A switch turned off again shows after Spotify restarts, like every other one.
static void hide(UIView *view, NSString *key) {
    if (view && SGHidden(key)) view.hidden = YES;
}

// The header layout is Encore's own class, so the hook asks whose page it is before touching it.
static UIViewController *playlistHeaderOf(UIView *view) {
    for (UIResponder *r = view; r; r = r.nextResponder) {
        if (![r isKindOfClass:UIViewController.class]) continue;
        return [NSStringFromClass(r.class) containsString:@"FreeTierPlaylist"] ? (UIViewController *)r : nil;
    }
    return nil;
}

static void applyColumn(UIView *header) {
    UIView *column = nil;
    for (UIView *v = viewNamed(header, @"ExpandableTextView"); v && v != header; v = v.superview) {
        if (![NSStringFromClass(v.superview.class) containsString:@"AutoLayoutStackView"]) continue;
        column = v;
        break;
    }
    for (UIView *row in column.subviews) {
        BOOL last = row == column.subviews.lastObject && [NSStringFromClass(row.class) containsString:@"StackView"];
        if (SGHasClass(row, @"ExpandableTextView")) hide(row, SGHidePlaylistDescription);
        else if (SGHasClass(row, @"FacepileView")) hide(row, SGHidePlaylistCreator);
        else if (last) hide(row, SGHidePlaylistLength);
    }
}

static void applyActions(UIView *row) {
    static const struct { __unsafe_unretained NSString *ident, *key; } buttons[] = {
        {@"Components.UI.WatchFeedEntityExplorerButton", SGHidePlaylistVideo},
        {@"Components.UI.AddToButton", SGHidePlaylistAddTo},
        {@"DownloadButton.Granular", SGHidePlaylistDownload},
        {@"Components.UI.ShareButton", SGHidePlaylistShare},
        {@"Components.UI.ContextMenuButton", SGHidePlaylistMore},
    };
    for (UIView *action in row.subviews) {
        for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++) {
            if (identNamed(action, buttons[i].ident)) hide(action, buttons[i].key);
        }
    }
}

// Find on page and Sort sit in a header view of their own, one that holds nothing else.
static void applyFindBar(UIView *header) {
    for (UIView *v = viewNamed(header, @"EncoreTextField"); v && v != header; v = v.superview) {
        if (![NSStringFromClass(v.class) containsString:@"HeaderView"]) continue;
        hide(v, SGHidePlaylistFind);
        return;
    }
}

static void collapseCover(UIViewController *headerVC, UIView *layout, UIView *cover) {
    NSLayoutConstraint *height = [headerVC respondsToSelector:@selector(headerViewHeightConstraint)] ? [headerVC headerViewHeightConstraint] : nil;
    NSLayoutConstraint *guide = [headerVC respondsToSelector:@selector(layoutGuideHeightConstraint)] ? [headerVC layoutGuideHeightConstraint] : nil;
    CGFloat full = CGRectGetHeight(layout.bounds), before = height.constant;
    if (before < full) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"playlist header: %.0f layout, header constraint %.0f, guide %.0f", full, before, guide.constant); });
        return;
    }

    CGFloat top = CGFLOAT_MAX, bottom = 0;
    for (UIView *v in layout.subviews) {
        if (v == cover) continue;
        top = MIN(top, CGRectGetMinY(v.frame));
        bottom = MAX(bottom, CGRectGetMaxY(v.frame));
    }
    if (top == CGFLOAT_MAX) return;

    CGFloat coverTop = CGRectGetMinY(cover.frame);
    CGFloat shift = coverTop > 0 && coverTop < top ? top - coverTop : 0;
    for (UIView *v in layout.subviews) {
        if (v != cover && shift > 0) v.frame = CGRectOffset(v.frame, 0, -shift);
    }

    CGFloat target = bottom - shift + (before - full);
    if (target > before - 0.5) return;
    height.constant = target;
    if (guide.constant > before - target) guide.constant -= before - target;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"playlist header: layout %.0f, header %.0f -> %.0f, guide %.0f", full, before, target, guide.constant); });
}

static char kBackdropKey, kSourceKey;

static void applyBackdrop(UIView *layout) {
    if (!SGFlag(SGKeyPlaylistBackdrop, NO)) return;
    UIImage *image = nil;
    for (UIView *v in identNamed(layout, @"EditableHeaderArtworkElement.ImageView").subviews) {
        if ([v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image) image = ((UIImageView *)v).image;
    }
    if (!image) return;

    UIView *container = nil;
    for (UIView *v = layout.superview; v && !container; v = v.superview) {
        for (UIView *sub in v.subviews) {
            if ([sub.accessibilityIdentifier isEqualToString:@"_backgroundViewContainer"]) container = sub;
        }
    }
    UIView *header = container.subviews.firstObject;
    if (header.subviews.count < 2) return;

    UIView *backdrop = objc_getAssociatedObject(header, &kBackdropKey);
    if (!backdrop) {
        backdrop = SGBackdropMake(header.bounds, 1);
        objc_setAssociatedObject(header, &kBackdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (backdrop.superview != header) [header insertSubview:backdrop atIndex:1];

    UIImageView *sample = SGBackdropImageView(backdrop);
    if (objc_getAssociatedObject(sample, &kSourceKey) == image) return;
    objc_setAssociatedObject(sample, &kSourceKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sample.image = SGBackdropSample(image);
}

%hook _TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout
- (void)layoutSubviews {
    %orig;
    UIViewController *headerVC = playlistHeaderOf((UIView *)self);
    if (!headerVC) return;
    UIView *layout = (UIView *)self, *cover = identNamed(layout, @"Components.Header.UI.ArtworkImage");
    hide(cover, SGHidePlaylistArtwork);
    applyColumn(layout);
    applyBackdrop(layout);
    if (cover.hidden) collapseCover(headerVC, layout, cover);
}
%end

// The cover loads after the header is laid out, and a new image does not lay the header out again.
%hook UIImageView
- (void)setImage:(UIImage *)image {
    %orig;
    if (!image || ![self.superview.accessibilityIdentifier isEqualToString:@"EditableHeaderArtworkElement.ImageView"]) return;
    for (UIView *v = self.superview; v; v = v.superview) {
        if (![NSStringFromClass(v.class) containsString:@"HeaderContentLayout"]) continue;
        if (playlistHeaderOf(v)) applyBackdrop(v);
        return;
    }
}
%end

%hook UIStackView
- (void)layoutSubviews {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"HeaderActionsRow"] && playlistHeaderOf(self)) applyActions(self);
}
%end

%hook SPTFreeTierPlaylistEncoreHeaderViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *header = ((UIViewController *)self).viewIfLoaded;
    if (header) applyFindBar(header);
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    if (!SGHidden(SGHidePlaylistPills) || !identNamed((UIView *)self, @"PlaylistCuration.Row.CurationActionsToolbar")) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"playlist pills: asked for a height, answered 0"); });
    return result;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28EncoreConsumerMobile_BaseKit19HeaderContentLayout",
        @"SPTFreeTierPlaylistEncoreHeaderViewController",
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell",
    ]);
}
