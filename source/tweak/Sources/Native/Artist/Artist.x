#import <objc/runtime.h>
#import <CoreImage/CoreImage.h>
#import "Core/SGCore.h"
#import "Artist.h"

static BOOL onArtistPage(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"creator-page"]) return YES;
    }
    return NO;
}

static UIView *identNamed(UIView *root, NSString *ident) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *v) {
        if (!found && [v.accessibilityIdentifier hasPrefix:ident]) found = v;
    });
    return found;
}

#pragma mark - header

static void hide(UIView *view, NSString *key) {
    if (view && SGHidden(key)) view.hidden = YES;
}

// The identifier sits on the button; the action is the view the button row arranges around it.
static UIView *actionHolding(UIView *button, UIView *header) {
    for (UIView *v = button; v.superview && v.superview != header; v = v.superview) {
        if (v.superview.superview == header) return v;
        if ([NSStringFromClass(v.superview.class) containsString:@"OverflowStackView"]) return v;
    }
    return nil;
}

static void applyHeader(UIView *header) {
    hide(identNamed(header, @"ImageHeaderView.VerifiedBadge"), SGHideArtistVerified);
    // Its AutoLayoutStackView traps like OverflowStackView below once the label goes hidden.
    if (SGHidden(SGHideArtistListeners)) identNamed(header, @"Components.Header.UI.Metadata").alpha = 0;

    static const struct { __unsafe_unretained NSString *ident, *key; } buttons[] = {
        {@"Components.UI.WatchFeedEntityExplorerButton", SGHideArtistExplore},
        {@"Curation.FollowButtonElementKit.FollowButton", SGHideArtistFollow},
        {@"Components.UI.ContextMenuButton", SGHideArtistMore},
        {@"Components.UI.ShuffleButton", SGHideArtistShuffle},
    };
    for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++) {
        if (!SGHidden(buttons[i].key)) continue;
        UIView *action = actionHolding(identNamed(header, buttons[i].ident), header);
        if (!action) continue;
        if ([NSStringFromClass(action.superview.class) containsString:@"OverflowStackView"]) {
            action.alpha = 0;
            action.userInteractionEnabled = NO;
        } else {
            action.hidden = YES;
        }
    }
}

static CGFloat bottomOf(UIView *v) {
    return v.center.y + CGRectGetHeight(v.bounds) / 2;
}

static UIView *childOfHeader(UIView *view, UIView *header) {
    for (UIView *v = view; v; v = v.superview) {
        if (v.superview == header) return v;
    }
    return nil;
}

static void closeUpTitle(UIView *header) {
    UIView *title = childOfHeader(identNamed(header, @"Encore.AdaptiveTitle"), header);
    UIView *badge = identNamed(header, @"ImageHeaderView.VerifiedBadge");
    UIView *listeners = identNamed(header, @"Components.Header.UI.Metadata");
    UIView *metadata = childOfHeader(listeners, header);
    if (!title || !badge || !metadata || badge.superview != header) return;

    CGFloat edge = listeners.alpha > 0 ? bottomOf(badge) : bottomOf(metadata);
    CGFloat move = 0;
    if (!badge.hidden) {
        move = edge - bottomOf(badge);
        badge.transform = CGAffineTransformMakeTranslation(0, move);
        edge = bottomOf(title) + move;
    }
    title.transform = CGAffineTransformMakeTranslation(0, MAX(0, edge - bottomOf(title)));
}

#pragma mark - photo fade

static UIImage *blurred(UIImage *image) {
    static CIContext *context;
    if (!context) context = [CIContext contextWithOptions:nil];
    CIImage *input = [CIImage imageWithCGImage:image.CGImage];
    if (!input) return nil;
    CIImage *output = [[input imageByClampingToExtent] imageByApplyingGaussianBlurWithSigma:MAX(input.extent.size.width / 18, 6)];
    CGImageRef cg = [context createCGImage:[output imageByCroppingToRect:input.extent] fromRect:input.extent];
    UIImage *result = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return result;
}

static CAGradientLayer *fadeMask(CALayer *host, NSArray<NSNumber *> *locations) {
    CAGradientLayer *mask = [host.mask isKindOfClass:CAGradientLayer.class] ? (CAGradientLayer *)host.mask : nil;
    if (!mask) {
        mask = [CAGradientLayer layer];
        mask.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        host.mask = mask;
    }
    mask.locations = locations;
    mask.frame = host.bounds;
    return mask;
}

static void applyPhotoFade(UIView *header) {
    if (!SGFlag(SGKeyArtistPhotoFade, NO)) return;
    UIView *artwork = identNamed(header, @"Components.Header.UI.ArtworkImage");
    UIView *clip = childOfHeader(artwork, header);
    if (!artwork || !clip || clip == artwork) return;
    __block UIImageView *source = nil;
    SGForEachView(artwork, ^(UIView *v) {
        if (!source && [v isKindOfClass:UIImageView.class] && ((UIImageView *)v).image) source = (UIImageView *)v;
    });

    static char backdropKey, sourceKey;
    UIImageView *backdrop = objc_getAssociatedObject(header, &backdropKey);
    if (!backdrop) {
        backdrop = [[UIImageView alloc] init];
        backdrop.contentMode = UIViewContentModeScaleAspectFill;
        backdrop.clipsToBounds = YES;
        backdrop.userInteractionEnabled = NO;
        UIView *shade = [[UIView alloc] init];
        shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
        shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [backdrop addSubview:shade];
        objc_setAssociatedObject(header, &backdropKey, backdrop, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (header.subviews.firstObject != backdrop) [header insertSubview:backdrop atIndex:0];
    if (source.image && objc_getAssociatedObject(header, &sourceKey) != source.image) {
        UIImage *soft = blurred(source.image);
        if (soft) {
            objc_setAssociatedObject(header, &sourceKey, source.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            backdrop.image = soft;
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect photo = [artwork convertRect:artwork.bounds toView:header];
    CGFloat side = MAX(CGRectGetWidth(photo), CGRectGetHeight(header.bounds));
    backdrop.frame = CGRectMake(CGRectGetMidX(photo) - side / 2, 0, side, CGRectGetHeight(header.bounds));
    backdrop.subviews.firstObject.frame = backdrop.bounds;
    backdrop.alpha = MIN(1, MAX(0, artwork.alpha));
    fadeMask(backdrop.layer, @[@0, @0.7, @1]);
    fadeMask(clip.layer, @[@0, @0.55, @1]);
    [CATransaction commit];
}

%hook _TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView
- (void)layoutSubviews {
    %orig;
    applyHeader((UIView *)self);
    closeUpTitle((UIView *)self);
    applyPhotoFade((UIView *)self);
}
%end

%hook UIStackView
- (void)layoutSubviews {
    %orig;
    UIView *header = self.superview;
    if (![NSStringFromClass(header.class) containsString:@"ImageHeaderKit"]) return;
    applyHeader(header);
    closeUpTitle(header);
}
%end

#pragma mark - tab bar

static void hideTabBar(UIView *strip) {
    strip.alpha = 0;
    strip.userInteractionEnabled = NO;
    for (UIView *v in strip.superview.subviews) {
        if (![v isKindOfClass:UIScrollView.class]) continue;
        ((UIScrollView *)v).scrollEnabled = NO;
        v.transform = CGAffineTransformMakeTranslation(0, -CGRectGetHeight(strip.bounds));
    }
}

%hook _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton
- (void)layoutSubviews {
    %orig;
    if (!SGHidden(SGHideArtistTabBar)) return;
    for (UIView *v = ((UIView *)self).superview; v; v = v.superview) {
        if (![v.accessibilityIdentifier isEqualToString:@"Components.UI.TabsSectionHeading"]) continue;
        if (onArtistPage(v)) hideTabBar(v);
        return;
    }
}
%end

#pragma mark - sections

static const struct { __unsafe_unretained NSString *title, *key; BOOL prefix; } sections[] = {
    {@"Popular", SGHideArtistPopular, NO},
    {@"Artist pick", SGHideArtistPick, NO},
    {@"Popular releases", SGHideArtistReleases, NO},
    {@"Featuring ", SGHideArtistFeaturing, YES},
    {@"Music videos", SGHideArtistVideos, NO},
    {@"Watch more from ", SGHideArtistVideos, YES},
    {@"About", SGHideArtistAbout, NO},
    {@"Artist playlists", SGHideArtistPlaylists, NO},
    {@"Fans also like", SGHideArtistFansAlsoLike, NO},
    {@"Appears on", SGHideArtistAppearsOn, NO},
    {@"Discovered on", SGHideArtistDiscoveredOn, NO},
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

// The heading's title, or @"" for a cell that is not a heading.
static NSString *headingIn(UIView *cell) {
    __block NSString *title = nil;
    SGForEachView(cell, ^(UIView *v) {
        if (!title && v.accessibilityLabel.length && [NSStringFromClass(v.class) containsString:@"SectionHeadingHome"]) {
            title = v.accessibilityLabel;
        }
    });
    return title ?: @"";
}

// Per list: index path -> heading title, @"" for every other cell sized so far.
static NSMutableDictionary<NSIndexPath *, NSString *> *headingsOf(UICollectionView *list) {
    static char key;
    NSMutableDictionary *headings = objc_getAssociatedObject(list, &key);
    if (!headings) {
        headings = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(list, &key, headings, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return headings;
}

static NSString *sectionOf(NSIndexPath *path, NSDictionary<NSIndexPath *, NSString *> *headings) {
    for (NSInteger item = path.item; item >= 0; item--) {
        NSString *title = headings[[NSIndexPath indexPathForItem:item inSection:path.section]];
        if (!title) return nil;
        if (title.length) return title;
    }
    return nil;
}

static UICollectionView *listOf(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return (UICollectionView *)v;
    }
    return nil;
}

static BOOL collapsed(UICollectionViewCell *cell, NSIndexPath *path) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell.class]) return NO;   // a card inside a carousel: its row decides
    }
    if (!onArtistPage(cell)) return NO;
    if (SGHidden(SGHideArtistLikedSongs) && identNamed(cell, @"Components.UI.LikedSongs.Row")) return YES;
    if (!anySectionSwitch() || !path) return NO;

    UICollectionView *list = listOf(cell);
    if (!list) return NO;
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
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"artist page: collapsed the first row"); });
    return result;
}
%end

%ctor {
    if (!SGNativeUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC35CreativeWorkPlatform_ImageHeaderKit15ImageHeaderView",
        @"_TtC12Element_List18CollectionViewCell",
        @"_TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton",
    ]);
}
