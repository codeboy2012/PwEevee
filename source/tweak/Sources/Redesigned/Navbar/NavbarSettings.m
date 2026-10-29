#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Navbar.h"
#import "Shared/Navigation/AddTabSheet.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Navigation/TabIcons.h"

static NSArray<NSDictionary *> *tabPresets(void) {
    return @[
        @{SGRNavbarTitle: @"Home", SGRNavbarURI: @"spotify:home", SGRNavbarIcon: @"home"},
        @{SGRNavbarTitle: @"Search", SGRNavbarURI: @"spotify:search", SGRNavbarIcon: @"search"},
        @{SGRNavbarTitle: @"Your Library", SGRNavbarURI: @"spotify:collection", SGRNavbarIcon: @"collection"},
        @{SGRNavbarTitle: @"Liked Songs", SGRNavbarURI: @"spotify:collection:tracks", SGRNavbarIcon: @"heart"},
        @{SGRNavbarTitle: @"Playlists", SGRNavbarURI: @"spotify:playlists", SGRNavbarIcon: @"playlist"},
        @{SGRNavbarTitle: @"Albums", SGRNavbarURI: @"spotify:collection:albums", SGRNavbarIcon: @"album"},
        @{SGRNavbarTitle: @"Artists", SGRNavbarURI: @"spotify:collection:artists", SGRNavbarIcon: @"artist"},
        @{SGRNavbarTitle: @"Podcasts", SGRNavbarURI: @"spotify:collection:podcasts", SGRNavbarIcon: @"podcasts"},
        @{SGRNavbarTitle: @"Audiobooks", SGRNavbarURI: @"spotify:collection:audiobooks", SGRNavbarIcon: @"audiobook"},
        @{SGRNavbarTitle: @"Downloads", SGRNavbarURI: @"spotify:collection:downloads", SGRNavbarIcon: @"downloaded"},
        @{SGRNavbarTitle: @"Your Episodes", SGRNavbarURI: @"spotify:collection:your-episodes", SGRNavbarIcon: @"bookmark"},
        @{SGRNavbarTitle: @"Browse", SGRNavbarURI: @"spotify:browse", SGRNavbarIcon: @"browse"},
        @{SGRNavbarTitle: @"New Releases", SGRNavbarURI: @"spotify:new-releases", SGRNavbarIcon: @"star"},
        @{SGRNavbarTitle: @"Made For You", SGRNavbarURI: @"spotify:made-for-you", SGRNavbarIcon: @"user"},
        @{SGRNavbarTitle: @"Concerts", SGRNavbarURI: @"spotify:concerts", SGRNavbarIcon: @"events"},
        @{SGRNavbarTitle: @"Queue", SGRNavbarURI: @"spotify:now-playing:queue", SGRNavbarIcon: @"queue"},
        @{SGRNavbarTitle: @"Create", SGRNavbarURI: @"spotify:create-menu", SGRNavbarIcon: @"plus"},
    ];
}

static NSMutableArray<NSMutableDictionary *> *navbarEntries(void) {
    NSArray<NSString *> *stock = SGRNavbarStock();
    NSSet<NSString *> *removed = [NSSet setWithArray:SGRNavbarRemovedStock()];
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *entry in SGRNavbarLayout()) {
        NSString *ident = entry[SGRNavbarID];
        if (![ident isKindOfClass:NSString.class] || [seen containsObject:ident]) continue;
        if (!entry[SGRNavbarURI] && [removed containsObject:ident]) continue;
        if (!entry[SGRNavbarURI] && ![stock containsObject:ident]) continue;
        [seen addObject:ident];
        [entries addObject:[entry mutableCopy]];
    }
    for (NSString *ident in stock) {
        if ([seen containsObject:ident] || [removed containsObject:ident]) continue;
        [entries addObject:[@{SGRNavbarID: ident, SGRNavbarTitle: ident} mutableCopy]];
    }
    return entries;
}

static void appendTab(NSDictionary *tab) {
    NSMutableDictionary *entry = [tab mutableCopy];
    entry[SGRNavbarID] = NSUUID.UUID.UUIDString;
    if (tab[SGTabTitle]) entry[SGRNavbarTitle] = tab[SGTabTitle];
    if (tab[SGTabURI]) entry[SGRNavbarURI] = tab[SGTabURI];
    if (tab[SGTabIcon]) entry[SGRNavbarIcon] = tab[SGTabIcon];
    if (tab[SGTabIconSet]) entry[SGRNavbarIconSet] = tab[SGTabIconSet];
    SGRSetNavbarLayout([navbarEntries() arrayByAddingObject:entry]);
    SGRRefreshTabBar();
}

@interface SGRTabPickerPage : SGPage
@end

static NSArray<NSDictionary *> *openablePresets(void) {
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *tab in tabPresets()) {
        NSString *via = nil;
        SGLinkRoute route = SGSpotifyURIRoute([NSURL URLWithString:tab[SGRNavbarURI]], &via);
        SGLog(@"navbar: preset %@ -> %@", tab[SGRNavbarURI],
              route == SGLinkRouteOpens ? via : route == SGLinkRouteNone ? @"no handler, left out" : @"unknown");
        if (route != SGLinkRouteNone) [kept addObject:tab];
    }
    return kept;
}

@implementation SGRTabPickerPage {
    UIView *_footer;
    NSArray<NSDictionary *> *_presets;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Add a Tab";
    _presets = openablePresets();
    return self;
}

// Said here rather than by Spotify's alert on the bar later, every time the tab is tapped.
- (void)refuse:(NSString *)uri {
    NSString *message = [NSString stringWithFormat:@"Spotify has nowhere to open %@, so it would not work as a tab.", uri];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Can't open that link" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(@"Paste a share link or a spotify: URI. Icons: home, search, collection, heart, "
                   "playlist, album, artist, podcasts, audiobook, downloaded, bookmark, browse, star, "
                   "user, events, queue, plus, radio, gears, spotifyLogo.");
    self.tableView.tableFooterView = _footer;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 16, 24);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)_presets.count : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return SGSectionHeader(table, section == 0 ? @"Spotify's pages" : @"Anywhere else");
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return SGSectionHeaderHeight;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"pick");
    if (path.section == 0) {
        NSDictionary *tab = _presets[(NSUInteger)path.row];
        SGFillCell(cell, tab[SGRNavbarTitle], tab[SGRNavbarURI], nil, nil);
    } else {
        SGFillCell(cell, @"Any link…", nil, nil, @"link");
    }
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == 0) {
        appendTab(_presets[(NSUInteger)path.row]);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Any link" message:@"Where the tab goes, and the glyph on it." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = @"Name"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"spotify:playlist:…";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Icon";
        field.text = @"star";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = alert.textFields[0].text, *icon = alert.textFields[2].text;
        NSString *uri = SGSpotifyURIFromText(alert.textFields[1].text).absoluteString;
        if (!uri.length) return;
        NSString *via = nil;
        SGLinkRoute route = SGSpotifyURIRoute([NSURL URLWithString:uri], &via);
        SGLog(@"navbar: custom %@ -> %@", uri, route == SGLinkRouteOpens ? via : route == SGLinkRouteNone ? @"no handler" : @"unknown");
        if (route == SGLinkRouteNone) {
            [self refuse:uri];
            return;
        }
        appendTab(@{SGRNavbarTitle: title.length ? title : uri, SGRNavbarURI: uri, SGRNavbarIcon: icon.length ? icon : @"star"});
        [self.navigationController popViewControllerAnimated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

typedef NS_ENUM(NSInteger, SGRNavbarSection) {
    SGRNavbarSectionSwitch,
    SGRNavbarSectionTabs,
    SGRNavbarSectionAdd,
    SGRNavbarSectionReset,
    SGRNavbarSectionCount,
};

@interface SGRNavbarPage : SGPage
- (void)editRow:(NSInteger)row;
@end

@implementation SGRNavbarPage {
    NSMutableArray<NSMutableDictionary *> *_entries;
    UIView *_intro;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Navbar";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.editing = YES;
    _intro = SGNote(@"Drag to reorder. Use the switch to hide a tab, or tap a tab to customize it.");
    self.tableView.tableHeaderView = _intro;
    _entries = navbarEntries();
}

// The Add page writes straight to the layout, so the list is read again on the way back.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _entries = navbarEntries();
    [self.tableView reloadData];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)save {
    SGRSetNavbarLayout(_entries);
    SGRRefreshTabBar();
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return SGRNavbarSectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGRNavbarSectionSwitch) return 3;
    return section == SGRNavbarSectionTabs ? (NSInteger)_entries.count : 1;
}

- (NSString *)headerFor:(NSInteger)section {
    return section == SGRNavbarSectionTabs ? @"Tabs" : nil;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self headerFor:section];
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    if ([self headerFor:section]) return SGSectionHeaderHeight;
    return [self tableView:table numberOfRowsInSection:section] ? SGSectionGap : CGFLOAT_MIN;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"navbar");
    switch (path.section) {
        case SGRNavbarSectionSwitch: {
            BOOL labels = path.row == 1, appleIcons = path.row == 2;
            NSString *title = appleIcons ? @"Apple Music tab icons" : labels ? @"Hide labels" : @"Custom navbar";
            NSString *detail = appleIcons ? @"Use Apple's style for built-in tabs" : labels ? @"Icons only" : nil;
            SGFillCell(cell, title, detail, nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = SGGreen();
            toggle.tag = path.row;
            toggle.on = appleIcons ? SGFlag(SGRKeyNavbarAppleIcons, NO)
                : labels ? SGFlag(SGRKeyNavbarHideLabels, YES) : SGEnabled(SGRKeyNavbar);
            [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            break;
        }
        case SGRNavbarSectionTabs: {
            NSDictionary *entry = _entries[(NSUInteger)path.row];
            BOOL hidden = [entry[SGRNavbarHidden] boolValue];
            NSString *uri = entry[SGRNavbarURI];
            BOOL customized = SGRNavbarEntryHasCustomIcon(entry)
                || ![entry[SGRNavbarTitle] isEqualToString:entry[SGRNavbarID]];
            NSString *detail = uri ? @"Tap to edit" : (customized ? @"Spotify tab · Tap to customize" : @"Spotify's own tab");
            SGFillCell(cell, entry[SGRNavbarTitle], detail, hidden ? SGGrey() : nil, nil);
            UISwitch *toggle = [UISwitch new];
            toggle.onTintColor = SGGreen();
            toggle.on = !hidden;
            toggle.tag = path.row;
            [toggle addTarget:self action:@selector(visibilityToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case SGRNavbarSectionAdd:
            SGFillCell(cell, @"Add a tab…", nil, nil, @"plus");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        default:
            SGFillCell(cell, @"Use Spotify's order", nil, nil, @"arrow.uturn.backward");
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
    }
    return cell;
}

- (BOOL)tableView:(UITableView *)table canMoveRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGRNavbarSectionTabs;
}

- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.section == SGRNavbarSectionTabs;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)table editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != SGRNavbarSectionTabs) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (NSIndexPath *)tableView:(UITableView *)table targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)from toProposedIndexPath:(NSIndexPath *)to {
    return to.section == SGRNavbarSectionTabs ? to : from;
}

- (void)tableView:(UITableView *)table moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NSMutableDictionary *entry = _entries[(NSUInteger)from.row];
    [_entries removeObjectAtIndex:(NSUInteger)from.row];
    [_entries insertObject:entry atIndex:(NSUInteger)to.row];
    [self save];
}

- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete) return;
    NSDictionary *entry = _entries[(NSUInteger)path.row];
    if (!entry[SGRNavbarURI]) {
        NSMutableSet<NSString *> *removed = [NSMutableSet setWithArray:SGRNavbarRemovedStock()];
        [removed addObject:entry[SGRNavbarID]];
        SGRSetNavbarRemovedStock(removed.allObjects);
    }
    [_entries removeObjectAtIndex:(NSUInteger)path.row];
    [self save];
    [table deleteRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGRNavbarSectionTabs) {
        [self editRow:path.row];
    } else if (path.section == SGRNavbarSectionAdd) {
        [self.navigationController pushViewController:[SGRTabPickerPage new] animated:YES];
    } else if (path.section == SGRNavbarSectionReset) {
        [self reset];
    }
}

- (void)visibilityToggled:(UISwitch *)toggle {
    if (toggle.tag < 0 || (NSUInteger)toggle.tag >= _entries.count) return;
    NSMutableDictionary *entry = _entries[(NSUInteger)toggle.tag];
    if (toggle.on) [entry removeObjectForKey:SGRNavbarHidden];
    else entry[SGRNavbarHidden] = @YES;
    [self save];
}

- (void)editRow:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= _entries.count) return;
    NSMutableDictionary *entry = _entries[(NSUInteger)row];
    NSString *ident = entry[SGRNavbarID];
    __weak typeof(self) weakSelf = self;
    if (entry[SGRNavbarURI]) {
        SGPresentEditTabSheet(self, tabPresets(), entry, ^(NSDictionary *edited) {
            typeof(self) page = weakSelf;
            if (!page) return;
            NSMutableDictionary *current = nil;
            for (NSMutableDictionary *candidate in page->_entries) {
                if ([candidate[SGRNavbarID] isEqualToString:ident]) { current = candidate; break; }
            }
            if (!current) return;
            current[SGRNavbarTitle] = edited[SGTabTitle];
            current[SGRNavbarURI] = edited[SGTabURI];
            current[SGRNavbarIcon] = edited[SGTabIcon];
            if (edited[SGTabIconSet]) current[SGRNavbarIconSet] = edited[SGTabIconSet];
            else [current removeObjectForKey:SGRNavbarIconSet];
            [page save];
            [page.tableView reloadData];
        }, ^{
            typeof(self) page = weakSelf;
            if (!page) return;
            NSUInteger index = [page->_entries indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger idx, BOOL *stop) {
                return [candidate[SGRNavbarID] isEqualToString:ident];
            }];
            if (index == NSNotFound) return;
            [page->_entries removeObjectAtIndex:index];
            [page save];
            [page.tableView reloadData];
        });
        return;
    }

    NSString *title = entry[SGRNavbarTitle] ?: ident;
    NSString *defaultIcon = SGRNavbarDefaultIcon(ident);
    BOOL custom = SGRNavbarEntryHasCustomIcon(entry);
    NSMutableDictionary *tab = [@{
        SGTabTitle: title,
        SGTabURI: @"spotify:home",
        SGTabIcon: custom ? (entry[SGRNavbarIcon] ?: defaultIcon ?: @"star") : (defaultIcon ?: @"star")
    } mutableCopy];
    if (custom && entry[SGRNavbarIconSet]) tab[SGTabIconSet] = entry[SGRNavbarIconSet];
    SGPresentEditTabAppearanceSheet(self, tab, ^(NSDictionary *edited) {
        typeof(self) page = weakSelf;
        if (!page) return;
        NSMutableDictionary *current = nil;
        for (NSMutableDictionary *candidate in page->_entries) {
            if ([candidate[SGRNavbarID] isEqualToString:ident]) { current = candidate; break; }
        }
        if (!current) return;
        current[SGRNavbarTitle] = edited[SGTabTitle];
        NSString *icon = edited[SGTabIcon];
        NSString *iconSet = edited[SGTabIconSet];
        BOOL isCustom = SGRNavbarEntryHasCustomIcon(current)
            || iconSet != nil
            || (defaultIcon ? ![icon isEqualToString:defaultIcon] : ![icon isEqualToString:@"star"]);
        if (isCustom) {
            current[SGRNavbarIcon] = icon;
            current[SGRNavbarCustomIcon] = @YES;
            if (iconSet) current[SGRNavbarIconSet] = iconSet;
            else [current removeObjectForKey:SGRNavbarIconSet];
        } else {
            [current removeObjectForKey:SGRNavbarIcon];
            [current removeObjectForKey:SGRNavbarCustomIcon];
            [current removeObjectForKey:SGRNavbarIconSet];
        }
        [page save];
        [page.tableView reloadData];
    });
}

- (void)toggled:(UISwitch *)toggle {
    if (toggle.tag == 2) {
        SGSetEnabled(SGRKeyNavbarAppleIcons, toggle.on);
    } else {
        SGSetEnabled(toggle.tag == 1 ? SGRKeyNavbarHideLabels : SGRKeyNavbar, toggle.on);
    }
    SGRRefreshTabBar();
}

- (void)reset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Use Spotify's order"
                                                                  message:@"Every tab of Spotify's comes back where Spotify put it, and the tabs you added go."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGRSetNavbarLayout(@[]);
        SGRSetNavbarRemovedStock(@[]);
        SGRRefreshTabBar();
        self->_entries = navbarEntries();
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGRNavbarSettingsPage(void) {
    return [SGRNavbarPage new];
}

UIViewController *SGRNavbarEditorPage(void) {
    return [SGRNavbarPage new];
}
