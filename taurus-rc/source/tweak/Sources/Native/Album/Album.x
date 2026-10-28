#import "Core/SGCore.h"
#import "Album.h"

static NSString *const kTemplate = @"CreativeWorkPlatform.CreativeWorkTemplateView";

static UIView *albumPageOf(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kTemplate]) return v;
    }
    return nil;
}

static UIView *identNamed(UIView *root, NSString *ident) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v.accessibilityIdentifier hasPrefix:ident]) found = v;
    });
    return found;
}

#pragma mark - header buttons

static const struct { __unsafe_unretained NSString *ident, *key; } buttons[] = {
    {@"Components.UI.WatchFeedEntityExplorerButton", SGHideAlbumExplore},
    {@"Components.UI.AddToButton", SGHideAlbumAddTo},
    {@"DownloadButton.Granular", SGHideAlbumDownload},
    {@"Components.UI.ContextMenuButton", SGHideAlbumMore},
};

static NSString *keyFor(UIView *action) {
    NSString *ident = action.subviews.firstObject.accessibilityIdentifier;
    for (size_t i = 0; ident && i < sizeof(buttons) / sizeof(buttons[0]); i++) {
        if ([ident hasPrefix:buttons[i].ident]) return buttons[i].key;
    }
    return nil;
}

// The buttons arrive after the page has laid out, and a row that keeps its size lays nothing else out.
%hook UIStackView
- (void)layoutSubviews {
    %orig;
    BOOL row = NO;
    for (UIView *action in self.subviews) {
        if (keyFor(action)) row = YES;
    }
    if (!row || !albumPageOf(self)) return;
    for (UIView *action in self.subviews) {
        NSString *key = keyFor(action);
        if (key && SGHidden(key)) action.hidden = YES;
    }
}
%end

#pragma mark - the cover behind the header

static char kBackdropKey, kSourceKey;

static void applyBackdrop(UIView *page) {
    if (!SGFlag(SGKeyAlbumBackdrop, NO)) return;
    __block UIImage *image = nil;
    SGForEachView(identNamed(page, @"CreativeWorkPlatform.Components.UI.ArtWorkElement.WithCoverArt"), ^(UIView *v) {
        if (!image && [v isKindOfClass:UIImageView.class]) image = ((UIImageView *)v).image;
    });
    UIView *header = page.subviews.firstObject;
    if (!image || ![NSStringFromClass(header.class) containsString:@"HeaderView"]) return;

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

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    applyBackdrop((UIView *)self);
}
%end

%hook UIImageView
- (void)setImage:(UIImage *)image {
    %orig;
    if (!image || self.bounds.size.width < 200 || !SGFlag(SGKeyAlbumBackdrop, NO)) return;
    UIView *page = albumPageOf(self);
    if (page) applyBackdrop(page);
}
%end

#pragma mark - sections

static const struct { __unsafe_unretained NSString *title, *key; BOOL prefix; } sections[] = {
    {@"More by ", SGHideAlbumMoreBy, YES},
    {@"Related Music Videos", SGHideAlbumVideos, NO},
    {@"Concerts", SGHideAlbumConcerts, NO},
    {@"Merch", SGHideAlbumMerch, NO},
    {@"You might also like", SGHideAlbumYouMightLike, NO},
};

static BOOL sectionHidden(NSString *title) {
    for (size_t i = 0; i < sizeof(sections) / sizeof(sections[0]); i++) {
        NSString *wanted = sections[i].title;
        BOOL match = sections[i].prefix
            ? [title.lowercaseString hasPrefix:wanted.lowercaseString]
            : [title caseInsensitiveCompare:wanted] == NSOrderedSame;
        if (match) return SGHidden(sections[i].key);
    }
    return NO;
}

static BOOL anySectionSwitch(void) {
    for (size_t i = 0; i < sizeof(sections) / sizeof(sections[0]); i++) {
        if (SGHidden(sections[i].key)) return YES;
    }
    return NO;
}

// The heading's title, the copyright's identifier, or @"" for any other cell.
static NSString *headingIn(UIView *cell) {
    __block NSString *title = nil;
    SGForEachView(cell, ^(UIView *v) {
        if (title) return;
        if ([v.accessibilityIdentifier isEqualToString:@"Album.Copyright"]) title = v.accessibilityIdentifier;
        else if (v.accessibilityLabel.length && [NSStringFromClass(v.class) containsString:@"SectionHeadingHome"]) title = v.accessibilityLabel;
    });
    return title ?: @"";
}

static NSMutableDictionary<NSIndexPath *, NSString *> *headingsOf(UICollectionView *list) {
    static char key;
    NSMutableDictionary *headings = objc_getAssociatedObject(list, &key);
    if (!headings) {
        headings = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(list, &key, headings, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return headings;
}

// nil above the first heading, or where a cell between this one and its heading is not sized yet.
static NSString *sectionOf(NSIndexPath *path, NSDictionary<NSIndexPath *, NSString *> *headings) {
    for (NSInteger item = path.item; item >= 0; item--) {
        NSString *title = headings[[NSIndexPath indexPathForItem:item inSection:path.section]];
        if (!title) return nil;
        if (title.length) return title;
    }
    return nil;
}

static BOOL collapsed(UICollectionViewCell *cell, NSIndexPath *path) {
    if (!path || !anySectionSwitch()) return NO;
    UICollectionView *list = nil;
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return NO;   // a card inside a carousel: its row decides
        if (!list && [v isKindOfClass:UICollectionView.class]) list = (UICollectionView *)v;
    }
    if (!list || !albumPageOf(list)) return NO;
    NSMutableDictionary *headings = headingsOf(list);
    headings[path] = headingIn(cell);
    NSString *section = sectionOf(path, headings);
    return section && sectionHidden(section);
}

%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    if (!collapsed((UICollectionViewCell *)self, attributes.indexPath)) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    return result;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC12Element_List18CollectionViewCell",
    ]);
}
