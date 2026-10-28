// The Live Activity page (App/ModSettings.x links it from the root, under either look): a slice of the lock
// screen at the top (SGLiveActivityPreview.m) over the switch, the view it shows and the card's look.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "LiveActivity.h"
#import "SGLiveActivityPreview.h"

static NSArray<NSString *> *viewNames(void) {
    return @[@"Lyrics", @"Queue", @"Control menu"];
}

static NSArray<NSString *> *colorNames(void) {
    return @[@"Spotify", @"Artwork", @"Plain"];
}

static NSArray<NSString *> *textSizeNames(void) {
    return @[@"Small", @"Medium", @"Large"];
}

static NSArray<NSString *> *withoutLyricsNames(void) {
    return @[@"Title and note", @"Title at line size"];
}

static NSArray<NSString *> *alignNames(void) {
    return @[@"Centered", @"Leading"];
}

// The page's rows; `preview` is told when one it reads changes, so the mock under the title follows.
static NSArray<SGModSection *> *sections(SGLiveActivityPreview *preview) {
    __weak SGLiveActivityPreview *weakPreview = preview;
    SGModRow *on = SGOptionRow(@"Live Activity", nil, SGKeyLiveActivity);
    on.changed = ^(BOOL value) { SGSetLiveActivityEnabled(value); };
    SGModRow *view = SGChoiceRow(@"Shows", nil, SGKeyLiveActivityView, viewNames(), SGLiveActivityLyrics);
    view.chosen = ^(NSInteger index) { [weakPreview reload]; };
    SGModRow *colors = SGChoiceRow(@"Card color", nil, SGKeyLiveActivityColors, colorNames(), SGLiveActivityColorsSpotify);
    SGModRow *textSize = SGChoiceRow(@"Text size", nil, SGKeyLiveActivityTextSize, textSizeNames(), SGLiveActivityTextMedium);
    SGModRow *without = SGChoiceRow(@"No lyrics", nil, SGKeyLiveActivityWithoutLyrics, withoutLyricsNames(), SGLiveActivityWithoutLyricsNote);
    SGModRow *align = SGChoiceRow(@"Alignment", nil, SGKeyLiveActivityAlignment, alignNames(), SGLiveActivityAlignCenter);
    SGModRow *translation = SGOptionRow(@"Translation", @"Under the line where the lyrics have one", SGKeyLiveActivityTranslation);
    SGModRow *artwork = SGOptionRow(@"Artwork", @"The track's cover beside the lines", SGKeyLiveActivityArtwork);
    SGModRow *progress = SGOptionRow(@"Progress bar", @"Under the lines", SGKeyLiveActivityProgressBar);
    for (SGModRow *row in @[colors, textSize, without, align]) row.chosen = ^(NSInteger index) { [weakPreview reload]; };
    for (SGModRow *row in @[translation, artwork, progress]) row.changed = ^(BOOL value) { [weakPreview reload]; };
    return @[
        SGSection(nil, @[on, view]),
        SGSection(@"Card", @[colors, textSize, without, align, translation, artwork, progress]),
    ];
}

@interface SGLiveActivityPage : SGModPage
@property (nonatomic, strong) SGLiveActivityPreview *preview;
@end

@implementation SGLiveActivityPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = self.preview;
}

// The header keeps the height it is given, so it is sized here and handed back to the table only when that
// changes (a table header set on every pass lays the table out again forever).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width;
    self.preview.layoutMargins = UIEdgeInsetsMake(0, table.layoutMargins.left, 0, table.layoutMargins.right);
    CGSize size = CGSizeMake(width, [self.preview heightForWidth:width]);
    if (CGSizeEqualToSize(self.preview.bounds.size, size)) return;
    self.preview.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = self.preview;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.preview reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.preview.running = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.preview.running = NO;
}

@end

UIViewController *SGLiveActivitySettingsPage(void) {
    SGLiveActivityPreview *preview = [SGLiveActivityPreview new];
    SGLiveActivityPage *page = [[SGLiveActivityPage alloc] initWithTitle:@"Live Activity" intro:nil sections:sections(preview) footer:nil];
    page.preview = preview;
    return page;
}

NSString *SGLiveActivitySummary(void) {
    if (!SGFlag(SGKeyLiveActivity, NO)) return @"Off";
    NSInteger index = SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics);
    NSArray<NSString *> *names = viewNames();
    return index >= 0 && index < (NSInteger)names.count ? names[index] : names.firstObject;
}
