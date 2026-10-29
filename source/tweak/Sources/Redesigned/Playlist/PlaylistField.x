#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

NSString *const SGRPlaylistListIdentifier = @"SPTFreeTierPlaylistTableView";

// Above for the bounce at the top of the list, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page's field

static SGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        SGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *SGRPlaylistFieldColor(UIView *view) {
    SGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: SGRNeutralField();
}

void SGRPlaylistSetArtwork(UIView *view, UIImage *image) {
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
    SGLog(@"redesign playlist: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (!page || page.bounds.size.height < 200) return;
    sgr_playlistRoot = page;
    SGRRevealHold(page, SGRRevealPage);
    SGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (page) sgr_playlistRoot = page;
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    UIScrollView *list = (UIScrollView *)self;
    if (list.backgroundColor && SGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
}
%end

%ctor {
    // Registered whatever the switch says: the flag rows elsewhere lock to these while it is on.
    SGRedesignForceFlags(@"playlist", @{
        // The page the trees were recorded with (trees/clean/playlist/02.txt).
        @"ios-feature-freetierplaylist.use_collection_view": @YES,
        @"ios-feature-freetierplaylist.context_menu_in_navigation_bar_enabled": @NO,
        // A row is a cover, a title and an artist. The video badge is none of them.
        @"ios-feature-freetierplaylist.hide_video_badge_for_tracks": @YES,
        @"ios-feature-freetierplaylist.pin_curation_actions": @NO,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl17FTPViewController",
        @"_TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView",
    ]);
}
