#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Album.h"

static NSString *const kPageIdentifier = @"CreativeWorkPlatform.CreativeWorkTemplateView";

// Above for the bounce at the top of the list, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page

UIView *SGRAlbumPageOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPageIdentifier]) return v;
    }
    return nil;
}

static BOOL isPageCell(UIView *cell) {
    for (UIView *v = cell.superview; v; v = v.superview) {
        if ([v isKindOfClass:UICollectionViewCell.class]) return NO;
        if ([v.accessibilityIdentifier isEqualToString:kPageIdentifier]) return YES;
    }
    return NO;
}

#pragma mark - the page's field

static SGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        SGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *SGRAlbumFieldColor(UIView *view) {
    SGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: SGRNeutralField();
}

void SGRAlbumSetArtwork(UIView *view, UIImage *image) {
    if (image) [fieldOn(view) setArtwork:image identity:nil animated:YES];
}

static SGRArtworkField *fieldIn(UIView *page) {
    SGRArtworkField *field = objc_getAssociatedObject(page, &kFieldKey);
    if (field) return field;
    field = [[SGRArtworkField alloc] initWithFrame:page.bounds];
    field.bleed = kBleed;
    objc_setAssociatedObject(page, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakPage = page;
    [field whenColored:^{ SGRRevealMark(weakPage, SGRRevealColor); }];
    SGLog(@"redesign album: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView
- (void)layoutSubviews {
    %orig;
    UIView *page = (UIView *)self;
    if (page.bounds.size.height < 200) return;
    sgr_albumRoot = page;
    SGRRevealHold(page, 0);
    SGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}
%end

%hook _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView
- (void)layoutSubviews {
    %orig;
    UIView *list = (UIView *)self;
    if (!SGRAlbumPageOf(list)) return;
    if (list.backgroundColor && SGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
    for (UIView *sub in list.subviews) {
        if (sub.backgroundColor && SGIsBaseSurface(sub.backgroundColor.CGColor)) sub.backgroundColor = UIColor.clearColor;
    }
}
%end

%hook _TtC12Element_List18CollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (isPageCell(cell)) SGRClearCellPaint(cell);
}
%end

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    SGRedesignForceFlags(@"album", @{
        @"ios-album-albumfeatureproperties-impl.context_menu_in_navigation_bar_enabled": @YES,
        @"ios-album-albumfeatureproperties-impl.share_in_action_row_enabled": @NO,
        // A row is a title and its artists. The video badge is neither.
        @"ios-creativeworkcommons-retrievalrow-impl.track_video_indicator_enabled": @NO,
        // Spotify's cover square is concealed on both pages this covers, so there is nothing left to tilt.
        @"ios-creativeworkcommons-cover-art-tilt-configuration-kit.album_playlist_and_podcast_pages_enabled": @NO,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC28CreativeWorkPlatform_PageKit24CreativeWorkTemplateView",
        @"_TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView",
        @"_TtC12Element_List18CollectionViewCell",
    ]);
}
