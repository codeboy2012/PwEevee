#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/AdBlock/AdBlock.h"
#import "App/Eevee/SGEevee.h"

// Eevee's own stored settings, read and written under the keys its compiled code uses.
// Sources/EeveeSpotify/Shared/Models/Extensions/UserDefaults+Extension.swift (upstream v6.6.8) is the
// reference for every key and default here. Settings whose stored shape is a plain Bool are driven
// under their own key; the ones Eevee keeps as an Int or a JSON blob (patchType, the experiments and
// SponsorBlock option structs) are driven through mirror keys under spotifyglass.eevee., synced from
// Eevee's storage each time the page is built and written back by each switch.
static NSString *const kPatchType = @"patchType";                    // Int: 1 disabled, 2 requests
static NSString *const kTrueShuffle = @"trueShuffleEnabled";         // Bool, default NO
static NSString *const kOverwriteConfig = @"overwriteConfiguration"; // Bool, default NO
static NSString *const kDarkPopUps = @"darkPopUps";                  // Bool, default YES
static NSString *const kCleanShareLinks = @"cleanShareLinks";        // Bool, default NO
static NSString *const kExperiments = @"experimentsOptions";         // JSON: showInstagramDestination, liveContainerSharing, disableFeelingsForElsa
static NSString *const kSponsorBlock = @"sponsorBlockOptions";       // JSON: SponsorBlockOptions
static NSString *const kSponsorBlockUserID = @"sponsorBlockUserID";  // String, self-made on first submission
static NSString *const kLyricsSource = @"lyricsSource";              // Int: Eevee's LyricsSource; 4 = notReplaced

// Mirror keys for settings stored in a shape a switch row cannot hold.
#define EEVEE_MIRROR(name) @"spotifyglass.eevee." name

// One field of Eevee's Codable option structs, which it decodes with JSONDecoder, so the keys are the
// Swift property names. Every setter reads the struct back and writes it whole, leaving its other
// fields exactly as they are.
static NSDictionary *eeveeOptions(NSString *key) {
    id root = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [root isKindOfClass:NSDictionary.class] ? root : @{};
}

static BOOL eeveeFieldBool(NSString *key, NSString *field, BOOL fallback) {
    id value = eeveeOptions(key)[field];
    return value ? [value boolValue] : fallback;
}

static double eeveeFieldNumber(NSString *key, NSString *field, double fallback) {
    id value = eeveeOptions(key)[field];
    return value ? [value doubleValue] : fallback;
}

static NSString *eeveeFieldString(NSString *key, NSString *field, NSString *fallback) {
    id value = eeveeOptions(key)[field];
    return [value isKindOfClass:NSString.class] ? value : fallback;
}

static void eeveeSetField(NSString *key, NSString *field, id value) {
    NSMutableDictionary *options = [eeveeOptions(key) mutableCopy];
    options[field] = value;
    [NSUserDefaults.standardUserDefaults setObject:options forKey:key];
}

// What Eevee does after a patch setting changes (OfflineHelper.resetData()): its PersistentCache and
// remote-config copies go, so the next launch re-reads everything through the new patch settings.
static void eeveeResetData(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    if (!support) return;
    [[NSFileManager defaultManager] removeItemAtPath:[support stringByAppendingPathComponent:@"PersistentCache"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[support stringByAppendingPathComponent:@"remote-config"] error:nil];
}

static BOOL eeveePatchingOn(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kPatchType];
    return value ? [value integerValue] == 2 : YES;   // Eevee's own default: patch unless told not to
}

static void eeveeSetPatching(BOOL on) {
    [NSUserDefaults.standardUserDefaults setInteger:on ? 2 : 1 forKey:kPatchType];
    eeveeResetData();
}

static BOOL eeveeSBEnabledOn(void) {
    return eeveeFieldBool(kSponsorBlock, @"enabled", NO);
}

static NSString *eeveeSBUserID(void) {
    NSString *identifier = [NSUserDefaults.standardUserDefaults stringForKey:kSponsorBlockUserID];
    return identifier.length ? identifier : @"Created with your first submission";
}

static void eeveeRegenerateSBUserID(void) {
    NSMutableString *fresh = [NSMutableString stringWithCapacity:64];
    for (int i = 0; i < 32; i++) [fresh appendFormat:@"%02x", arc4random() & 0xff];
    [NSUserDefaults.standardUserDefaults setObject:fresh forKey:kSponsorBlockUserID];
}

// The mirror keys are Eevee's settings as far as the switch rows are concerned; each one is read back
// from Eevee's own storage before the rows are made, so the page always shows what the payload will do.
static void eeveeSyncMirrors(void) {
    SGSetEnabled(EEVEE_MIRROR("patching"), eeveePatchingOn());
    SGSetEnabled(EEVEE_MIRROR("instagram"), eeveeFieldBool(kExperiments, @"showInstagramDestination", NO));
    SGSetEnabled(EEVEE_MIRROR("livecontainer"), eeveeFieldBool(kExperiments, @"liveContainerSharing", YES));
    SGSetEnabled(EEVEE_MIRROR("sb.enabled"), eeveeSBEnabledOn());
    SGSetEnabled(EEVEE_MIRROR("sb.logOnly"), eeveeFieldBool(kSponsorBlock, @"logOnly", NO));
    SGSetEnabled(EEVEE_MIRROR("sb.overlay"), eeveeFieldBool(kSponsorBlock, @"showOverlay", YES));
    SGSetEnabled(EEVEE_MIRROR("sb.toast"), eeveeFieldBool(kSponsorBlock, @"showToast", NO));
    SGSetEnabled(EEVEE_MIRROR("sb.feedback"), eeveeFieldBool(kSponsorBlock, @"showSkipFeedbackButtons", YES));
    SGSetEnabled(EEVEE_MIRROR("sb.autoSkipOwn"), eeveeFieldBool(kSponsorBlock, @"autoSkipMySubmissions", YES));
    SGSetEnabled(EEVEE_MIRROR("sb.respectSeek"), eeveeFieldBool(kSponsorBlock, @"respectManualSeek", NO));
}

#pragma mark - the EeveeSpotify page

UIViewController *SGEeveeSpotifyPage(void) {
    eeveeSyncMirrors();

    // Upstream labels this patchType row Patch Premium; the unified build calls it what the
    // exclusivity contract calls it, so the two premium spoofs read as the pair they are.
    SGModRow *patching = SGSwitchRow(@"Eevee's Spoofed Premium", @"Unlocks Premium features locally, on this device", EEVEE_MIRROR("patching"));
    // Written through the exclusivity setter: when the Eevee spoof turns on, Spot.pw's Spoof
    // Premium is written off (and the other way, from that page's row).
    patching.changed = ^(BOOL on) { SGEeveePremiumSetOn(on); };

    SGModRow *overwrite = SGOptionRow(@"Overwrite configuration", @"Replaces Spotify's remote configuration with a dumped Premium one. May cause issues.", kOverwriteConfig);
    overwrite.visible = ^BOOL { return eeveePatchingOn(); };
    overwrite.changed = ^(BOOL on) {
        eeveeResetData();
        // The restart note covers it, but the value the user sees must not go stale.
        eeveeSyncMirrors();
    };

    SGModRow *trueShuffle = SGOptionRow(@"True Shuffle", @"Shuffle stays inside the playlist instead of mixing in Smart Shuffle recommendations", kTrueShuffle);
    trueShuffle.visible = ^BOOL { return eeveePatchingOn(); };

    SGModRow *cleanShare = SGOptionRow(@"Clean share links", @"Removes the device and account tracking parameter from shared links", kCleanShareLinks);

    SGModRow *instagram = SGOptionRow(@"Always show Instagram", @"Offers Instagram in the share sheet even when Spotify hides it", EEVEE_MIRROR("instagram"));
    instagram.changed = ^(BOOL on) {
        eeveeSetField(kExperiments, @"showInstagramDestination", @(on));
        eeveeResetData();
    };

    SGModRow *liveContainer = SGOptionRow(@"Share to LiveContainer", @"Offers LiveContainer as a share destination when it is installed", EEVEE_MIRROR("livecontainer"));
    liveContainer.changed = ^(BOOL on) { eeveeSetField(kExperiments, @"liveContainerSharing", @(on)); };

    SGModRow *dark = SGOptionRow(@"Dark popups", @"Popups draw dark instead of following the app's look", kDarkPopUps);

    SGModRow *sbEnabled = SGHideRow(@"SponsorBlock", @"Skips community-marked segments in podcast episodes", EEVEE_MIRROR("sb.enabled"));
    sbEnabled.changed = ^(BOOL on) {
        eeveeSetField(kSponsorBlock, @"enabled", @(on));
        eeveeSyncMirrors();
    };

    SGModRow *sbLogOnly = SGOptionRow(@"Log only", @"Marks segments as skipped without actually seeking", EEVEE_MIRROR("sb.logOnly"));
    sbLogOnly.visible = ^BOOL { return eeveeSBEnabledOn(); };
    sbLogOnly.changed = ^(BOOL on) { eeveeSetField(kSponsorBlock, @"logOnly", @(on)); };

    SGModRow *sbOverlay = SGHideRow(@"Segment overlay", @"Draws the segments on the progress bar in their category colors", EEVEE_MIRROR("sb.overlay"));
    sbOverlay.visible = ^BOOL { return eeveeSBEnabledOn(); };
    sbOverlay.changed = ^(BOOL on) { eeveeSetField(kSponsorBlock, @"showOverlay", @(on)); };

    SGModRow *sbToast = SGHideRow(@"Skip toast", @"Shows a banner whenever a segment is skipped", EEVEE_MIRROR("sb.toast"));
    sbToast.visible = ^BOOL { return eeveeSBEnabledOn(); };
    sbToast.changed = ^(BOOL on) {
        eeveeSetField(kSponsorBlock, @"showToast", @(on));
        eeveeSyncMirrors();
    };

    SGModRow *sbFeedback = SGHideRow(@"Toast actions", @"Vote, undo and hide buttons on the skip toast", EEVEE_MIRROR("sb.feedback"));
    sbFeedback.visible = ^BOOL { return eeveeSBEnabledOn() && eeveeFieldBool(kSponsorBlock, @"showToast", NO); };
    sbFeedback.changed = ^(BOOL on) { eeveeSetField(kSponsorBlock, @"showSkipFeedbackButtons", @(on)); };

    SGModRow *sbAutoSkipOwn = SGHideRow(@"Auto-skip own submissions", @"Skips segments you submitted yourself", EEVEE_MIRROR("sb.autoSkipOwn"));
    sbAutoSkipOwn.visible = ^BOOL { return eeveeSBEnabledOn(); };
    sbAutoSkipOwn.changed = ^(BOOL on) { eeveeSetField(kSponsorBlock, @"autoSkipMySubmissions", @(on)); };

    SGModRow *sbRespectSeek = SGHideRow(@"Respect manual seek", @"A segment seeked back into plays through once instead of being skipped again", EEVEE_MIRROR("sb.respectSeek"));
    sbRespectSeek.visible = ^BOOL { return eeveeSBEnabledOn(); };
    sbRespectSeek.changed = ^(BOOL on) { eeveeSetField(kSponsorBlock, @"respectManualSeek", @(on)); };

    SGModRow *sbMinSegment = SGSliderRow(@"Minimum segment length", @"Shorter segments are never skipped", 0, 30, 0.5,
        ^{ return eeveeFieldNumber(kSponsorBlock, @"minSegmentDuration", 1.0); },
        ^(double value) { eeveeSetField(kSponsorBlock, @"minSegmentDuration", @(value)); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%.1f s", value]; });

    SGModRow *sbToastDuration = SGSliderRow(@"Toast duration", nil, 1, 8, 0.2,
        ^{ return eeveeFieldNumber(kSponsorBlock, @"toastDuration", 2.2); },
        ^(double value) { eeveeSetField(kSponsorBlock, @"toastDuration", @(value)); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%.1f s", value]; });

    SGModRow *sbServer = SGActionRow(@"Server address", nil, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Server address"
            message:@"The SponsorBlock server segments come from and are submitted to."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = eeveeFieldString(kSponsorBlock, @"serverURL", @"https://sponsor.ajay.app");
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.keyboardType = UIKeyboardTypeURL;
            field.placeholder = @"https://sponsor.ajay.app";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *server = alert.textFields.firstObject.text;
            if (server.length) eeveeSetField(kSponsorBlock, @"serverURL", server);
        }]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    sbServer.value = ^NSString *{ return eeveeFieldString(kSponsorBlock, @"serverURL", @"https://sponsor.ajay.app"); };

    SGModRow *sbUserID = SGStatActionRow(@"Your SponsorBlock ID", @"Identifies your submissions and votes. Treat it like a password.", ^NSString *{
        return eeveeSBUserID();
    }, ^{
        eeveeRegenerateSBUserID();
    });

    return [[SGModPage alloc] initWithTitle:@"EeveeSpotify"
        intro:@"EeveeSpotify's features, kept as they are and presented by the mod."
        sections:@[
            SGNotedSection(@"Premium", @[
                patching,
                overwrite,
                trueShuffle,
            ], SGRestartNote),
            SGSection(@"Sharing", @[
                cleanShare,
                instagram,
                liveContainer,
            ]),
            SGSection(@"Appearance", @[
                dark,
            ]),
            SGNotedSection(@"SponsorBlock", @[
                sbEnabled,
                sbLogOnly,
                sbOverlay,
                sbToast,
                sbFeedback,
                sbAutoSkipOwn,
                sbRespectSeek,
                sbMinSegment,
                sbToastDuration,
                sbServer,
                sbUserID,
            ], @"Powered by the SponsorBlock community (sponsor.ajay.app)."),
            SGSection(nil, @[
                SGWithSymbol(SGPageRow(@"App icons", ^UIViewController *{ return SGEeveeIconsPage(); }), @"app.badge.fill"),
            ]),
        ]
        footer:nil];
}

#pragma mark - app icons

// The icon picker: the same icons the payload's picker shows (the alternates declared in the app's
// Info.plist, drawn from the 142 PNGs at the app root), the same stored key
// (EeveeSelectedAppIconName) and the same prettify setting (iconNamePrettify), so the two stay in
// step whichever one the user touches.
static NSString *const kEeveeSelectedIcon = @"EeveeSelectedAppIconName";
static NSString *const kEeveeDefaultIcon = @"__default__";

// What the payload's picker does with a raw plist key (prettifyIconKey(_:)): underscores, hyphens and
// camelCase become spaces.
static NSString *eeveePrettyIconName(NSString *key) {
    NSMutableString *spaced = [key stringByReplacingOccurrencesOfString:@"_" withString:@" "].mutableCopy;
    for (NSUInteger i = 1; i < spaced.length; i++) {
        unichar c = [spaced characterAtIndex:i], prev = [spaced characterAtIndex:i - 1];
        BOOL camel = (c >= 'A' && c <= 'Z' && prev >= 'a' && prev <= 'z');
        BOOL letterToDigit = [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:c] && [[NSCharacterSet letterCharacterSet] characterIsMember:prev];
        BOOL digitToLetter = [[NSCharacterSet letterCharacterSet] characterIsMember:c] && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:prev];
        if (camel || letterToDigit || digitToLetter) [spaced insertString:@" " atIndex:i++];
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [spaced componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])
        if (part.length) [parts addObject:part];
    NSString *out = [parts componentsJoinedByString:@" "];
    return out.length ? out : key;
}

@interface SGEeveeIconsPage : SGPage
@end

@implementation SGEeveeIconsPage {
    NSArray<NSDictionary *> *_icons;   // { key, name, alternate }
    NSString *_selected;
    NSString *_error;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"App icons";
    _selected = [NSUserDefaults.standardUserDefaults stringForKey:kEeveeSelectedIcon] ?: kEeveeDefaultIcon;
    return self;
}

- (void)loadIcons {
    NSDictionary *bundleIcons = [NSBundle mainBundle].infoDictionary[@"CFBundleIcons"];
    NSMutableArray *icons = [NSMutableArray arrayWithObject:@{@"key": kEeveeDefaultIcon, @"name": @"Default", @"alternate": NSNull.null}];
    [bundleIcons[@"CFBundleAlternateIcons"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSDictionary *info, BOOL *stop) {
        NSArray *files = info[@"CFBundleIconFiles"] ?: @[key];
        // iOS resolves the icon by its plist key, but on sideloaded builds keys with spaces or
        // parentheses fail; the payload passes the filename stem instead, and so does the page.
        NSString *alternate = files.firstObject ?: key;
        BOOL prettify = SGFlag(@"iconNamePrettify", YES);
        [icons addObject:@{@"key": key, @"name": prettify ? eeveePrettyIconName(key) : key, @"alternate": alternate}];
    }];
    _icons = [icons sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadIcons];
}

- (void)choose:(NSIndexPath *)path {
    NSDictionary *icon = _icons[(NSUInteger)path.row];
    if ([icon[@"key"] isEqualToString:_selected]) return;
    NSString *previous = _selected;
    _selected = icon[@"key"];
    [NSUserDefaults.standardUserDefaults setObject:_selected forKey:kEeveeSelectedIcon];
    NSString *alternate = [icon[@"alternate"] isKindOfClass:NSString.class] ? icon[@"alternate"] : nil;
    [UIApplication.sharedApplication setAlternateIconName:alternate completionHandler:^(NSError *error) {
        if (!error) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            _selected = previous;
            [NSUserDefaults.standardUserDefaults setObject:previous ?: @"" forKey:kEeveeSelectedIcon];
            _error = error.localizedDescription;
            [self.tableView reloadData];
        });
    }];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 1 : (NSInteger)_icons.count;
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"Names" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 0) {
        UITableViewCell *cell = SGDequeueCell(table, @"prettify");
        SGFillCell(cell, @"Prettify icon names", @"Turns underscores, hyphens and camelCase into readable spaces", nil, nil);
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen();
        toggle.on = SGFlag(@"iconNamePrettify", YES);
        toggle.accessibilityLabel = @"Prettify icon names";
        [toggle addTarget:self action:@selector(prettifyToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *icon = _icons[(NSUInteger)path.row];
    UITableViewCell *cell = SGDequeueCell(table, @"icon");
    SGFillCell(cell, icon[@"name"], nil, nil, nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if ([icon[@"key"] isEqualToString:_selected]) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    } else {
        cell.accessoryView = nil;
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (section == 0) return nil;
    return _error ?: @"Changing the icon restarts the home screen; the app keeps running.";
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) return;
    [self choose:path];
}

- (void)prettifyToggled:(UISwitch *)toggle {
    SGSetEnabled(@"iconNamePrettify", toggle.on);
    [self loadIcons];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end

UIViewController *SGEeveeIconsPage(void) {
    return [SGEeveeIconsPage new];
}

// The exclusivity policy (Shared/AdBlock/PremiumExclusivity.m) drives Eevee's patching key through
// this function, so every write takes Eevee's own path: the stored integer and the patch-data reset
// the page's own switch does. Declared in Shared/AdBlock/AdBlock.h's comments and linked across the
// layers without an import, which check-layers.sh allows.
void SGEeveeSetPatchingPrivate(BOOL on) {
    eeveeSetPatching(on);
}

#pragma mark - the standalone row, the gear button and the lyrics off-switch

static const NSInteger kEeveeRowTag = 1338;
static const CGFloat kEeveeRowHeight = 68;
static const NSInteger kEeveeNavButtonTag = 1337;

void SGEeveeRemoveStandaloneRow(UICollectionView *list) {
    // The payload's row is a direct subview of the list (a UIButton of its tag, 68pt tall, drawn above
    // the first cell); the stand-in left here after the first pass is hidden. Both carry the tag, so
    // they are told apart by scanning the subviews, not by viewWithTag: — that one recurses and could
    // answer with the stand-in, leaving the payload's row on the list for good.
    BOOL hadStandin = NO, tookRow = NO;
    for (UIView *sub in [list.subviews copy]) {
        if (sub.tag != kEeveeRowTag) continue;
        if (sub.hidden) { hadStandin = YES; continue; }
        sub.hidden = YES;
        sub.frame = CGRectZero;
        tookRow = YES;
    }
    if (!hadStandin) {
        // The payload's injection guard reads a view of its tag as "already there", so the stand-in
        // keeps its own re-injection from running while the list lays out again.
        UIView *standin = [[UIView alloc] initWithFrame:CGRectZero];
        standin.tag = kEeveeRowTag;
        standin.hidden = YES;
        standin.userInteractionEnabled = NO;
        [list addSubview:standin];
    }
    if (tookRow) {
        // The payload widened the list's top inset and the scroll indicator's to make room for its
        // row; taking both back together is what keeps a blank band from standing above the first cell.
        UIEdgeInsets inset = list.contentInset;
        if (inset.top >= kEeveeRowHeight) inset.top -= kEeveeRowHeight;
        list.contentInset = inset;
        UIEdgeInsets indicator = list.verticalScrollIndicatorInsets;
        if (indicator.top >= kEeveeRowHeight) indicator.top -= kEeveeRowHeight;
        list.verticalScrollIndicatorInsets = indicator;
    }
}

NSArray *SGEeveeFilteredBarItems(NSArray *items) {
    NSMutableArray *kept = [items mutableCopy];
    for (UIBarButtonItem *item in items)
        if (item.tag == kEeveeNavButtonTag) [kept removeObject:item];
    return kept;
}

// The payload's SettingsNavigationStackHook drops its gear button onto any pushed page whose class
// name contains "Settings" or whose title reads Settings in some forty languages — which includes
// the mod's own pages. Filtering the items of every navigation item as the bars lay out keeps the
// button off them, however late the payload added it.
%hook UINavigationItem
- (void)setRightBarButtonItems:(NSArray *)items animated:(BOOL)animated {
    %orig(SGEeveeFilteredBarItems(items), animated);
}

- (void)setRightBarButtonItems:(NSArray *)items {
    %orig(SGEeveeFilteredBarItems(items));
}
%end

void SGEeveeRestoreLyricsReplacement(void) {
    // Undoes the old integration lock, which wrote 4 (Eevee's LyricsSource.notReplaced) at every
    // launch. The key is only removed while it still holds that forced value — a source chosen in
    // Eevee's own UI afterwards is left as it is — so with the key gone the payload's own default
    // rules the lyrics pipeline again. Safe to call every launch.
    id current = [NSUserDefaults.standardUserDefaults objectForKey:kLyricsSource];
    if (current && [current integerValue] == 4)
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kLyricsSource];
}

%ctor {
    %init;
    // A state where both premium spoofs are stored on is settled before Spotify renders a settings
    // page (Shared/AdBlock/PremiumExclusivity.m); the network hooks settle their own copy first.
    SGPremiumResolveConflict();
}
