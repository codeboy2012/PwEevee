#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Settings/SGGlowSwitch.h"
#import "Native/Home/Home.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/Player/PlayerSettings.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Artist/Artist.h"
#import "Redesigned/Lyrics/Sing.h"
#import "Shared/Sing/SGSingModel.h"
#import "Shared/Flags/Flags.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/HeadGestures/HeadGestures.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Downloads/Downloads.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "App/About/About.h"
#import "Pages.h"

static const CGFloat kRowHeight = 56;
static char kRowKey, kInsetKey;

static SGModRow *pageRow(NSString *title, NSString *symbol, UIViewController *(^page)(void)) {
    return SGWithSymbol(SGPageRow(title, page), symbol);
}


@interface SGPwEeveeSettingsPage : SGModPage
- (instancetype)initWithSections:(NSArray<SGModSection *> *)sections;
@end

@implementation SGPwEeveeSettingsPage
- (instancetype)initWithSections:(NSArray<SGModSection *> *)sections {
    // PwEevee rebrand: no rainbow wordmark, no masthead logo/byline, no contributor footer.
    return [super initWithTitle:nil intro:nil sections:sections footer:nil];
}
@end

static UIViewController *miscSettingsPage(void) {
    SGModRow *hideSigning = SGHideRow(@"Hide the lock screen alert", @"Hide the notice that this build cannot be opened from the lock screen", SGKeyHideSigningWarning);
    SGModSection *banners = SGSection(nil, @[
        SGWithSymbol(hideSigning, @"lock.slash"),
    ]);
    return [[SGModPage alloc] initWithTitle:@"Misc" intro:SGRestartNote sections:@[banners] footer:nil];
}

static UIViewController *modSettingsPage(void) {
    // Opening the page is the only thing that asks on its own; the cache keeps it to once every six hours.
    SGCheckForUpdate(NO);
    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    SGModRow *signing = SGSigningWarningRow();
    if (signing) signing.visible = ^BOOL { return !SGFlag(SGKeyHideSigningWarning, NO); };
    NSMutableArray<SGModRow *> *topRows = [NSMutableArray array];
    SGModRow *update = SGActionRow(@"PwEevee update available", @"Tap to view the latest release", ^{
        NSString *url = SGUpdateNewestRelease().url;
        if (url.length) SGOpenURL(url);
    });
    update.symbol = @"arrow.down.circle.fill";
    update.color = SGGreen();
    update.visible = ^BOOL { return SGUpdateVersion() != nil; };
    update.refreshOn = SGUpdateCheckedNotification;
    [topRows addObject:update];
    // The page's opening check is enough for most visits; this row makes it possible to ask again.
    SGModRow *check = SGStatActionRow(@"Check for Updates", nil, ^NSString * {
        if (SGUpdateChecking()) return @"Checking now";
        if (SGUpdateVersion()) return [@"Newer " stringByAppendingString:SGUpdateNewestRelease().version];
        if (SGUpdateLastCheckFailed()) return @"Failed - GitHub gave no answer";
        NSString *newest = SGUpdateNewestRelease().version;
        return newest.length ? [@"Works, the latest is " stringByAppendingString:newest]
                             : @"Asks GitHub for the newest release";
    }, ^{ if (!SGUpdateChecking()) SGCheckForUpdate(YES); });   // a tap is an ask, whatever the six hours say
    check.refreshOn = SGUpdateCheckedNotification;
    [topRows addObject:check];
    if (signing) [topRows addObject:signing];
    [sections addObject:SGSection(nil, topRows)];
    SGModRow *mod = pageRow(@"Mod", @"info.circle", ^UIViewController *{ return SGAboutPage(); });
    mod.value = ^NSString *{ return @(SG_VERSION); };
    // The audio effects work on the sound, so both looks have them, with what they are doing beside the chevron.
    SGModRow *audioEffects = pageRow(@"Audio effects", @"slider.vertical.3", ^UIViewController *{ return SGDSPSettingsPage(); });
    audioEffects.value = ^NSString *{ return SGDSPSummary(); };
    SGModRow *downloads = pageRow(@"Downloads", @"arrow.down.circle", ^UIViewController *{ return SGDownloadsSettingsPage(); });
    downloads.value = ^NSString *{ return SGDownloadsRowSummary(); };
    downloads.refreshOn = SGDownloadsDidChangeNotification;
    NSMutableArray<SGModRow *> *parts = [NSMutableArray arrayWithArray:@[
        pageRow(@"Appearance", @"paintpalette", ^UIViewController *{ return SGAppearanceSettingsPage(); }),
        pageRow(@"Navbar", @"dock.rectangle", ^UIViewController *{ return SGNavbarPage(); }),
        pageRow(@"Player", @"play.circle", ^UIViewController *{ return SGPlayerSettingsPage(); }),
        pageRow(@"Lyrics", @"quote.bubble", ^UIViewController *{ return SGLyricsSettingsPage(); }),
        downloads,
        pageRow(@"Lock Screen", @"lock.iphone", ^UIViewController *{ return SGLockScreenSettingsPage(); }),
        audioEffects,
        pageRow(@"Vibrations", @"iphone.radiowaves.left.and.right", ^UIViewController *{ return SGVibrationsSettingsPage(); }),
    ]];
    if (@available(iOS 17.0, *)) {
        SGModRow *liveActivity = pageRow(@"Live Activity", @"platter.filled.top.iphone", ^UIViewController *{ return SGLiveActivitySettingsPage(); });
        liveActivity.value = ^NSString *{ return SGLiveActivitySummary(); };
        [parts addObject:liveActivity];
    }
    [parts addObjectsFromArray:@[
        pageRow(@"AirPods gestures", @"airpods.pro", ^UIViewController *{ return SGHeadGesturesSettingsPage(); }),
        pageRow(@"Listening stats", @"chart.bar", ^UIViewController *{ return SGListeningStatsPage(); }),
    ]];
    if (SGRedesignedUIStored()) {
        [parts addObject:pageRow(@"Albums", @"square.stack", ^UIViewController *{ return SGRAlbumSettingsPage(); })];
        [parts addObject:pageRow(@"Artists", @"person.2", ^UIViewController *{ return SGRArtistSettingsPage(); })];
    }
    else [parts addObject:pageRow(@"Home & Library", @"house", ^UIViewController *{ return SGHomeSettingsPage(); })];
    [parts addObject:pageRow(@"Misc", @"ellipsis.circle", ^UIViewController *{ return miscSettingsPage(); })];
    // Sing's microphone is the redesigned player's, so Karaoke is the redesign's; its row follows a download.
    if (SGRedesignedUIStored()) {
        SGModRow *karaoke = pageRow(@"Karaoke", @"music.mic", ^UIViewController *{ return SGRKaraokeSettingsPage(); });
        karaoke.value = ^NSString *{ return SGRKaraokeSummary(); };
        karaoke.refreshOn = SGSingModelDidChangeNotification;
        [sections addObject:SGSection(nil, @[karaoke])];
    }
    [sections addObjectsFromArray:@[
        SGSection(nil, parts),
        SGSection(nil, @[
            pageRow(@"Premium, ads & privacy", @"crown", ^UIViewController *{ return SGAdsSettingsPage(); }),
            pageRow(@"Labs", @"testtube.2", ^UIViewController *{ return SGLabsPage(); }),
        ]),
        SGSection(nil, @[
            pageRow(@"All flags", @"flag", ^UIViewController *{ return SGAllFlagsPage(); }),
            mod,
        ]),
    ]];
    return [[SGPwEeveeSettingsPage alloc] initWithSections:sections];
}

#pragma mark - row in the settings list

@interface SGModSettingsRow : UIControl
@property (nonatomic) BOOL drawer;
@end

@implementation SGModSettingsRow {
    UIImageView *_icon;
    UILabel *_title;
    UIImageView *_chevron;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _icon = SGSymbolView(@"slider.horizontal.3", 20, UIImageSymbolWeightRegular, 24);
    _title = [UILabel new];
    _title.text = @"PwEevee Settings";
    _title.textColor = UIColor.whiteColor;
    _chevron = SGSymbolView(@"chevron.right", 11, UIImageSymbolWeightSemibold, 12);
    for (UIView *v in @[_icon, _title, _chevron]) [self addSubview:v];
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _title.font = SGTitleFont();
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height, lead = self.drawer ? 4 : 0;
    _icon.frame = CGRectMake(12 + lead, (height - 24) / 2, 24, 24);
    _title.frame = CGRectMake(48 + lead, 0, width - 96, height);
    _chevron.frame = CGRectMake(width - 24, (height - 12) / 2, 12, 12);
    _chevron.hidden = self.drawer;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}

static UINavigationController *navigationIn(UIViewController *page) {
    if ([page isKindOfClass:UINavigationController.class]) return (UINavigationController *)page;
    for (UIViewController *child in page.childViewControllers) {
        UINavigationController *found = navigationIn(child);
        if (found) return found;
    }
    return nil;
}

- (void)open {
    UIViewController *owner = nil;
    for (UIResponder *r = self; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UIViewController *presenting = self.drawer ? owner.presentingViewController : nil;
    if (presenting) {
        [presenting dismissViewControllerAnimated:YES completion:^{
            SGShowPage(navigationIn(presenting).topViewController ?: presenting, modSettingsPage());
        }];
        return;
    }
    SGShowPage(owner, modSettingsPage());
}

@end

// The tab bar's controller holds no stack itself; the selected tab's sits among its parent's children.
void SGOpenModSettings(UIView *source) {
    UIViewController *owner = nil;
    for (UIResponder *r = source; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UINavigationController *nav = nil;
    for (UIViewController *page = owner; page && !nav; page = page.parentViewController) nav = navigationIn(page);
    SGShowPage(nav.topViewController ?: SGTopController(), modSettingsPage());
}

static void placeRow(UICollectionView *list, SGModSettingsRow *row) {
    SGAdoptFonts(list, row);
    CGFloat bottom = list.contentSize.height;
    row.hidden = !row.drawer && bottom <= 0;
    row.frame = CGRectMake(0, row.drawer ? -kRowHeight : bottom, list.bounds.size.width, kRowHeight);

    UIEdgeInsets inset = list.contentInset;
    NSValue *applied = objc_getAssociatedObject(list, &kInsetKey);
    if (applied && UIEdgeInsetsEqualToEdgeInsets(inset, applied.UIEdgeInsetsValue)) return;
    if (row.drawer) inset.top += kRowHeight;
    else inset.bottom += kRowHeight;
    objc_setAssociatedObject(list, &kInsetKey, [NSValue valueWithUIEdgeInsets:inset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.contentInset = inset;
}

static SGModSettingsRow *ensureDrawerRow(UICollectionView *list) {
    SGModSettingsRow *row = objc_getAssociatedObject(list, &kRowKey);
    if (!row) {
        row = [[SGModSettingsRow alloc] initWithFrame:CGRectZero];
        row.drawer = YES;
        objc_setAssociatedObject(list, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (row.superview != list) [list addSubview:row];
    return row;
}

static UIViewController *settingsListIn(UIViewController *page, Class kind) {
    if ([page isKindOfClass:kind]) return page;
    for (UIViewController *child in page.childViewControllers) {
        UIViewController *found = settingsListIn(child, kind);
        if (found) return found;
    }
    return nil;
}

static BOOL isSettingsRoot(UIViewController *list) {
    for (UIViewController *page in list.navigationController.viewControllers) {
        UIViewController *found = settingsListIn(page, list.class);
        if (found) return found == list;
    }
    return YES;
}

%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    BOOL root = isSettingsRoot((UIViewController *)self);
    for (UIView *sub in ((UIViewController *)self).view.subviews) {
        if (![sub isKindOfClass:UICollectionView.class]) continue;
        SGModSettingsRow *row = objc_getAssociatedObject(sub, &kRowKey);
        if (!root) {
            [row removeFromSuperview];
            objc_setAssociatedObject(sub, &kRowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            continue;
        }
        if (row) continue;
        row = [[SGModSettingsRow alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(sub, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sub addSubview:row];
    }
}
%end

static UIColor *planBadgeColor(void) {
    if (!SGRedesignedUI()) return SGGreen();
    NSInteger rgb = SGInt(@"spotifyglass.redesign.accent", 0x37F200);
    if (rgb < 0 || rgb > 0xFFFFFF) return SGGreen();
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static __weak UIView *sg_drawerRoot;
static char kPlanBadgeLabelKey;

static NSString *sidebarBadgeText(void) {
    NSString *text = [NSUserDefaults.standardUserDefaults stringForKey:SGKeySidebarBadgeText];
    // PwEevee rebrand: no default badge text; Spotify's own label stays untouched.
    return text;
}

// "Spotify Free" and "Taurine" are external labels (Spotify's plan and a separate jailbreak);
// "Taurus" is what pre-rename installs may still carry in the badge preference — matched so their
// badge restyles on the next layout instead of never matching again.
static BOOL isSidebarBadgeText(NSString *text) {
    return [text isEqualToString:@"Spotify Free"] || [text isEqualToString:@"Taurine"]
        || [text isEqualToString:@"Taurus"] || [text isEqualToString:sidebarBadgeText()];
}

static BOOL isDrawerBadgeLabel(UILabel *label) {
    for (UIView *view = label; view; view = view.superview) {
        if (view == sg_drawerRoot ||
            [NSStringFromClass(view.class) containsString:@"SideDrawerListCollectionView"]) return YES;
    }
    return NO;
}

static BOOL isPlanBadgeLabel(UILabel *label) {
    return objc_getAssociatedObject(label, &kPlanBadgeLabelKey) != nil || isSidebarBadgeText(label.text);
}

static void stylePlanBadgeLabel(UILabel *label) {
    UIColor *color = planBadgeColor();
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    NSString *text = sidebarBadgeText();
    if (text.length == 0) return;  // no badge text configured: leave Spotify's native label
    if (![label.text isEqualToString:text]) label.text = text;
    label.textColor = (0.2126 * red + 0.7152 * green + 0.0722 * blue) > 0.55 ? UIColor.blackColor : UIColor.whiteColor;
    label.backgroundColor = color;
    label.layer.backgroundColor = color.CGColor;
    label.layer.cornerRadius = MIN(8, CGRectGetHeight(label.bounds) / 2);
    label.clipsToBounds = YES;
    objc_setAssociatedObject(label, &kPlanBadgeLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGRect labelBounds = label.bounds;
    for (UIView *badge = label.superview; badge && badge != sg_drawerRoot; badge = badge.superview) {
        CGRect labelFrame = [label convertRect:labelBounds toView:badge];
        if (badge.bounds.size.width > CGRectGetWidth(labelFrame) + 80 ||
            badge.bounds.size.height > CGRectGetHeight(labelFrame) + 32) break;
        badge.backgroundColor = color;
        badge.layer.backgroundColor = color.CGColor;
        badge.layer.cornerRadius = MIN(8, CGRectGetHeight(badge.bounds) / 2);
        badge.layer.masksToBounds = YES;
    }
}

static void updatePlanBadge(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (!isPlanBadgeLabel(label)) return;
        stylePlanBadgeLabel(label);
    });
}

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (![text isEqualToString:@"Spotify Free"] && ![text isEqualToString:@"Taurine"] &&
        ![text isEqualToString:@"Taurus"]) return;
    if (!isDrawerBadgeLabel(self)) return;
    stylePlanBadgeLabel(self);
}
%end

// Keep the drawer's plan badge and the PwEevee settings row current as Spotify rebuilds its view.
%hook _TtC23SideDrawer_ListPageImpl18ListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    sg_drawerRoot = ((UIViewController *)self).view;
    updatePlanBadge(sg_drawerRoot);
    SGForEachView(sg_drawerRoot, ^(UIView *view) {
        if (![view isKindOfClass:UICollectionView.class] ||
            ![NSStringFromClass(view.class) containsString:@"SideDrawerListCollectionView"]) return;
        ensureDrawerRow((UICollectionView *)view);
    });
}
%end

// The lists lay out after their controllers and again whenever their content changes.
%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    SGModSettingsRow *row = objc_getAssociatedObject(self, &kRowKey);
    BOOL drawerList = [NSStringFromClass(self.class) containsString:@"SideDrawerListCollectionView"];
    if (drawerList) updatePlanBadge(self);
    if (!row && drawerList)
        row = ensureDrawerRow(self);
    if (row && row.superview != self) [self addSubview:row];
    if (row) placeRow(self, row);
}
%end

%ctor {
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGSidebarBadgeTextDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        if (sg_drawerRoot) updatePlanBadge(sg_drawerRoot);
    }];
    SGRequireClasses(@[@"_TtC21Settings_PlatformImpl26SettingsListViewController", @"_TtC23SideDrawer_ListPageImpl18ListViewController"]);
    SGRegisterPages();
    SGCheckSigningOnce();
    SGWatchForUpdates();
}
