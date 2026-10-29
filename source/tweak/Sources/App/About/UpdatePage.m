// What the Updates row opens: where this build stands against GitHub's releases, and the changelog of
// every release newer than it -- a section per release and heading, a row per line, each opening the
// commit it came from. Everything here is read out of what the last check stored (Update.m), so the
// page draws whatever is known the moment it opens and asks GitHub only if the six hours are up.
// A check that lands rebuilds it where it stands, which is what makes Check now worth having: the
// changelog of a release nobody had heard of a second ago fills the page in without leaving it.
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "SGUpdateChannels.h"

// A row of this page: a line of a changelog, or one of the three at the top that do something.
@interface SGUpdateRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *key;              // a switch row, on until it is switched off
@property (nonatomic, copy) NSString *(^value)(void);   // read out on the right, again once a second
@property (nonatomic, copy) void (^action)(void);
@end

@interface SGUpdateGroup : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *footer;
@property (nonatomic, copy) NSArray<SGUpdateRow *> *rows;
@end

@implementation SGUpdateRow
@end

@implementation SGUpdateGroup
@end

static SGUpdateRow *linkRow(NSString *title, NSString *subtitle, NSString *symbol, NSString *url) {
    SGUpdateRow *row = [SGUpdateRow new];
    row.title = title;
    row.subtitle = subtitle;
    row.symbol = symbol;
    row.action = ^{ SGOpenURL(url); };
    return row;
}

static SGUpdateGroup *group(NSString *title, NSArray<SGUpdateRow *> *rows) {
    SGUpdateGroup *section = [SGUpdateGroup new];
    section.title = title;
    section.rows = rows;
    return section;
}

// "2026-09-18T17:25:02Z" written out, and the empty string for a release GitHub never dated. Every
// word of the mod's is English, so the month is too, whatever the phone is set to.
static NSString *dateInWords(NSString *published, NSString *format) {
    static NSISO8601DateFormatter *reader;
    static NSDateFormatter *writer;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reader = [NSISO8601DateFormatter new];
        writer = [NSDateFormatter new];
        writer.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSDate *date = published.length ? [reader dateFromString:published] : nil;
    if (!date) return @"";
    writer.dateFormat = format;
    return [writer stringFromDate:date];
}

static NSString *shortDate(NSString *published) {   // 18 Sep 2026
    return dateInWords(published, @"d MMM yyyy");
}

static NSString *longDate(NSString *published) {    // 18 September 2026
    return dateInWords(published, @"d MMMM yyyy");
}

#pragma mark - the page

@interface SGUpdatePageController : SGPage
@end

@implementation SGUpdatePageController {
    NSArray<SGUpdateGroup *> *_groups;
    UIView *_intro;
    NSTimer *_ticker;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Updates";
    _groups = [self build];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(checkLanded)
                                               name:SGUpdateCheckedNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_ticker invalidate];
}

// The releases whose changelog this page shows: everything newer than the build, newest first.
// Nothing newer means the build is the newest release, and its own notes are what there is to read.
static NSArray<SGUpdateRelease *> *releasesToShow(void) {
    NSArray<SGUpdateRelease *> *releases = SGUpdateReleases();
    NSMutableArray<SGUpdateRelease *> *shown = [NSMutableArray array];
    for (SGUpdateRelease *release in releases) {
        if (!SGUpdateIsNewer(release.version)) break;
        [shown addObject:release];
    }
    if (!shown.count && releases.firstObject) [shown addObject:releases.firstObject];
    return shown;
}

- (NSString *)introText {
    NSString *channel = [NSString stringWithFormat:@"The build listens to the %@ channel.",
                         SGUpdateChannelTitle(SGUpdateChannelNow())];
    SGUpdateRelease *newest = SGUpdateNewestRelease();
    if (!newest) {
        if (SGUpdateChannelCheckedAt(SGUpdateChannelNow()) <= 0)
            return [NSString stringWithFormat:@"%@ This build is %s. Nothing has been asked of GitHub yet.",
                    channel, SG_VERSION];
        // A check landed and the channel answered with nothing: say that, rather than
        // letting an empty channel read as if it had been asked and come back even.
        return [NSString stringWithFormat:@"%@ This build is %s. This channel has no releases to hand out yet; it answers nothing until one is published.",
                channel, SG_VERSION];
    }
    NSString *date = longDate(newest.date);
    NSString *when = date.length ? [@" came out on " stringByAppendingString:date] : @" is out";
    if (SGUpdateVersion())
        return [NSString stringWithFormat:@"%@ %@%@, and this build is %s. Everything in between is below.",
                channel, newest.version, when, SG_VERSION];
    if (SGVersionCompare(newest.version, @(SG_VERSION)) == NSOrderedSame)
        return [NSString stringWithFormat:@"%@ This build, %s, is the newest release of the channel; it%@. What went into it is below.",
                channel, SG_VERSION, when];
    // The channel's newest is older than this build, the standing case after a move to
    // an edge channel on a build that shipped first: nothing older is offered as an
    // update here, and the way back is named.
    return [NSString stringWithFormat:@"%@ This build, %s, is newer than everything the %@ channel has published, so nothing here asks it to move. Switching back to Stable from the channel list brings those releases back to this page.",
            channel, SG_VERSION, SGUpdateChannelTitle(SGUpdateChannelNow())];
}

// The three rows at the top, then a section per release and heading: "0.19.0 · Features".
- (NSArray<SGUpdateGroup *> *)build {
    NSMutableArray<SGUpdateGroup *> *groups = [NSMutableArray array];
    SGUpdateRow *check = [SGUpdateRow new];
    check.title = @"Check now";
    check.symbol = @"arrow.clockwise";
    check.value = ^NSString *{ return SGUpdateStatus(); };
    check.action = ^{ SGCheckForUpdate(YES); };
    NSMutableArray<SGUpdateRow *> *top = [NSMutableArray arrayWithObject:check];
    SGUpdateRelease *newest = SGUpdateNewestRelease();
    if (SGUpdateVersion() && newest.url.length)
        [top addObject:linkRow([@"Get " stringByAppendingString:newest.version],
                               @"The release on GitHub, where its .deb is", @"arrow.down.circle", newest.url)];
    [top addObject:linkRow(@"All releases", @"Every version, this one and the ones before it",
                           @"clock.arrow.circlepath", [SGRepoURL stringByAppendingString:@"/releases"])];
    [groups addObject:group(nil, top)];

    SGUpdateRow *notice = [SGUpdateRow new];
    notice.title = @"Auto check updates";
    notice.symbol = @"bell";
    notice.key = SGKeyUpdateNotice;
    [groups addObject:group(nil, @[notice])];

    // The three channels, whichever one the build listens to carrying its mark. Alpha and
    // Nightly ask before they take the check over; Stable needs no asking.
    NSMutableArray<SGUpdateRow *> *channels = [NSMutableArray array];
    for (NSInteger c = 0; c < 3; c++) {
        SGUpdateChannel channel = (SGUpdateChannel)c;
        SGUpdateRow *row = [SGUpdateRow new];
        row.title = SGUpdateChannelTitle(channel);
        row.subtitle = SGUpdateChannelDetail(channel);
        row.value = ^NSString *{ return SGUpdateChannelNow() == channel ? @"✓" : @""; };
        row.action = ^{ [self pickChannel:channel]; };
        [channels addObject:row];
    }
    [groups addObject:group(@"Update channel", channels)];

    for (SGUpdateRelease *release in releasesToShow()) {
        NSMutableArray<NSString *> *kinds = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSMutableArray<SGUpdateRow *> *> *byKind = [NSMutableDictionary dictionary];
        for (SGUpdateChange *change in release.changes) {
            NSMutableArray<SGUpdateRow *> *rows = byKind[change.kind];
            if (!rows) {
                rows = [NSMutableArray array];
                byKind[change.kind] = rows;
                [kinds addObject:change.kind];
            }
            SGUpdateRow *row = [SGUpdateRow new];
            row.title = change.text;
            if (change.url.length) row.action = ^{ SGOpenURL(change.url); };
            [rows addObject:row];
        }
        NSString *date = shortDate(release.date);
        if (!kinds.count) {
            SGUpdateRow *empty = [SGUpdateRow new];
            empty.title = @"Nothing written down";
            empty.subtitle = release.url.length ? @"Tap to read the release on GitHub" : nil;
            if (release.url.length) empty.action = ^{ SGOpenURL(release.url); };
            [groups addObject:group([NSString stringWithFormat:@"%@%@", release.version,
                                     date.length ? [@" · " stringByAppendingString:date] : @""], @[empty])];
            continue;
        }
        [kinds enumerateObjectsUsingBlock:^(NSString *kind, NSUInteger i, BOOL *stop __attribute__((unused))) {
            // The date goes on the first heading of a release, so several releases read as dated blocks.
            NSString *title = [NSString stringWithFormat:@"%@ · %@%@", release.version, kind,
                               i == 0 && date.length ? [@" · " stringByAppendingString:date] : @""];
            [groups addObject:group(title, byKind[kind])];
        }];
    }
    return groups;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _intro = SGNote([self introText]);
    self.tableView.tableHeaderView = _intro;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _intro, 24, 0);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
    // Only the status reads out on the right, and only it moves on its own while the page is open;
    // it is written into the cell so that a reload never lands under a tap.
    [_ticker invalidate];
    _ticker = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(readStatus) userInfo:nil repeats:YES];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_ticker invalidate];
    _ticker = nil;
}

- (void)readStatus {
    for (UITableViewCell *cell in self.tableView.visibleCells) {
        SGUpdateRow *row = [self rowAt:[self.tableView indexPathForCell:cell]];
        UILabel *label = (UILabel *)cell.accessoryView;
        if (!row.value || ![label isKindOfClass:UILabel.class]) continue;
        label.text = row.value();
        [label sizeToFit];
        [cell setNeedsLayout];
    }
}

- (void)refresh {
    _groups = [self build];
    UILabel *note = (UILabel *)_intro.subviews.firstObject;
    note.text = [self introText];
    [self.view setNeedsLayout];
    [UIView transitionWithView:self.tableView duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self.tableView reloadData]; } completion:nil];
}

// A check that lands may have brought a release nobody had heard of: the whole page is built again,
// intro and all, and faded in where it stands.
- (void)checkLanded {
    [self refresh];
}

// The channel rows above: a tap takes the build over to that channel, with a word first for the
// two that trade off the six hours between checks. Switching hands the check its order right
// away, so the new channel's answer is read straight off the Releases it actually owns; no
// answer the old channel stored ever gets lent to the new one.
- (void)pickChannel:(SGUpdateChannel)channel {
    if (channel == SGUpdateChannelNow()) return;
    __weak typeof(self) weakSelf = self;
    void (^take)(void) = ^{
        SGUpdateChannelSelect(channel);
        SGCheckForUpdate(YES);
        [weakSelf refresh];
    };
    if (channel == SGUpdateChannelStable) { take(); return; }

    NSString *warning;
    switch (channel) {
        case SGUpdateChannelAlpha:
            warning = @"Alpha is the earliest and most frequent channel: experimental features may be incomplete, settings could appear and disappear between builds, and bugs and regressions are expected. Moving between channels may need a reinstall when versions or data moved apart. Your settings stay saved either way. You can switch back to Stable from this list at any time, and nothing installs on its own in either direction.";
            break;
        case SGUpdateChannelNightly:
            warning = @"Nightly carries the newer features and fixes before Stable does, but the builds are less tested and bugs and regressions are still possible. Moving between channels may need a reinstall when versions or data moved apart. Your settings stay saved either way. You can switch back to Stable from this list at any time, and nothing installs on its own in either direction.";
            break;
        default:
            warning = nil;
            break;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[@"Switch to " stringByAppendingString:SGUpdateChannelTitle(channel)]
                         message:warning
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:[@"Use " stringByAppendingString:SGUpdateChannelTitle(channel)]
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *_) { take(); }]];   
    [alert addAction:[UIAlertAction actionWithTitle:@"Stay here" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (SGUpdateRow *)rowAt:(NSIndexPath *)path {
    if (!path) return nil;
    return _groups[(NSUInteger)path.section].rows[(NSUInteger)path.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return (NSInteger)_groups.count;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_groups[(NSUInteger)section].rows.count;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    NSString *title = _groups[(NSUInteger)section].title;
    return title ? SGSectionHeader(table, title) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return _groups[(NSUInteger)section].title ? SGSectionHeaderHeight : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    NSString *footer = _groups[(NSUInteger)section].footer;
    return footer ? SGSectionFooter(table, footer) : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    NSString *footer = _groups[(NSUInteger)section].footer;
    return footer ? SGSectionFooterHeight(table, footer) : CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    SGUpdateRow *row = [self rowAt:path];
    UITableViewCell *cell = SGDequeueCell(table, row.symbol ? @"tiled" : @"line");
    SGFillCell(cell, row.title, row.subtitle, nil, nil);
    if (row.symbol) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        content.image = SGTileImage(row.symbol);
        content.imageToTextPadding = 14;
        cell.contentConfiguration = content;
    }
    cell.separatorInset = UIEdgeInsetsMake(0, row.symbol ? 58 : 16, 0, 0);
    if (row.key) {
        UISwitch *toggle = [UISwitch new];
        toggle.onTintColor = SGGreen();
        toggle.on = SGEnabled(row.key);
        toggle.accessibilityLabel = row.title;
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else if (row.value) {
        UILabel *label = [UILabel new];
        label.font = SGTitleFont();
        label.textColor = SGGrey();
        label.text = row.value();
        [label sizeToFit];
        cell.accessoryView = label;
    }
    cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    cell.accessibilityTraits = row.action ? UIAccessibilityTraitButton : UIAccessibilityTraitStaticText;
    return cell;
}

// The switch is read by the cell it sits in, since a rebuilt page moves the rows under it.
- (void)toggled:(UISwitch *)toggle {
    UIView *view = toggle;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    SGUpdateRow *row = [self rowAt:[self.tableView indexPathForCell:(UITableViewCell *)view]];
    if (row.key) SGSetEnabled(row.key, toggle.on);
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return [self rowAt:path].action != nil;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    SGUpdateRow *row = [self rowAt:path];
    if (row.action) row.action();
    // Check now goes grey to "checking…" the moment it is tapped rather than on the next tick.
    if (row.value) [self readStatus];
}

@end

UIViewController *SGUpdatePage(void) {
    // Opening the page counts as asking, but the six hours still hold: Check now is the way past them.
    SGCheckForUpdate(NO);
    return [SGUpdatePageController new];
}
