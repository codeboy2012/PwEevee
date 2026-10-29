// The Vibrations page, under either look (App/ModSettings.x links it from the main page): the preview at the
// top (SGVibrationsPreview.m), then a card per kind, the way the Audio effects page has one per effect.
// Controls is a switch with its strength under it. Music Haptics is two switches in one card that work together:
// Music Haptics itself, the mod's own from the sound while Spotify is in front, with its strength and what it
// follows (a choice that also says whether the rumble plays, rather than a switch of its own that one choice would
// leave with nothing to do) under it; and In the Background, which names the song to iOS's own Music Haptics, with
// what iOS's own is doing under it, or, while Music Haptics is off in Settings > Accessibility, a row saying so.
// The rows under a switch stay where they are, grayed, while it is off. Each strength's slider plays a tap at the
// new strength with each step, and the preview ripples with it.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Haptics.h"
#import "SGVibrationsPreview.h"

static NSString *const kMusicInfo = @"The iPhone taps along with the drums and rumbles under the bass, worked out from the sound as Spotify plays it. Only while Spotify is open: iOS stops an app's own haptics in the background, and a song playing on another device through Connect has no sound here to follow.\n\nWith In the Background on too, iOS plays its own haptic track for the songs it has one for, and this waits, so the two never double up.";

static NSString *const kBackgroundInfo = @"Keeps the vibrations going on the lock screen and in other apps, where iOS stops Spotify's own. The mod tells iOS which recording is playing, by its ISRC code from Apple Music's catalog (no sound leaves the phone), and iOS's own Music Haptics, the one Apple Music uses, plays Apple's haptic track for it.\n\nIt needs Settings > Accessibility > Music Haptics on, and only songs Apple has a haptic track for vibrate. While Spotify is open, Music Haptics above plays the others, if it is on.";

NSNotificationName const SGMusicHapticsSwitchesChangedNotification = @"SGMusicHapticsSwitchesChangedNotification";
NSNotificationName const SGSystemMusicHapticsChangedNotification = @"SGSystemMusicHapticsChangedNotification";

static NSString *sg_status;
static BOOL sg_systemOff;

NSString *SGMusicHapticsStatus(void) {
    return sg_status ?: @"Waiting";
}

void SGSetMusicHapticsStatus(NSString *status) {
    sg_status = [status copy];
}

BOOL SGSystemMusicHapticsOn(void) {
    return !sg_systemOff;
}

void SGSetSystemMusicHapticsOn(BOOL on) {
    if (sg_systemOff == !on) return;
    sg_systemOff = !on;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSystemMusicHapticsChangedNotification object:nil];
}

static BOOL backgroundAvailable(void) {
    if (@available(iOS 18.0, *)) return YES;
    return NO;
}

BOOL SGMusicHapticsOn(void) {
    return SGFlag(SGKeyMusicHaptics, NO);
}

BOOL SGMusicHapticsListedByInstall(void) {
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"MusicHapticsSupported"] boolValue];
}

BOOL SGMusicHapticsInBackground(void) {
    return backgroundAvailable() && SGFlag(SGKeyMusicHapticsBackground, NO);
}

void SGMigrateMusicHaptics(void) {
    // The redesign's old key first: SGMigrateKey leaves it where it is once the new one exists.
    SGMigrateKey(SGKeyMusicHapticsWas, SGKeyMusicHaptics);
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (![store objectForKey:SGKeyMusicHapticsMode]) return;
    NSInteger mode = SGInt(SGKeyMusicHapticsMode, 0);
    SGSetEnabled(SGKeyMusicHaptics, mode == 1);
    SGSetEnabled(SGKeyMusicHapticsBackground, mode == 2);
    [store removeObjectForKey:SGKeyMusicHapticsMode];
    SGLog(@"music haptics: the choice %ld is now Music Haptics %@, In the Background %@", (long)mode, mode == 1 ? @"on" : @"off", mode == 2 ? @"on" : @"off");
}

static NSArray<NSString *> *followsNames(void) {
    return @[@"Everything", @"Beat", @"Bass"];
}

static NSArray<NSString *> *followsNotes(void) {
    return @[@"A tap on each kick and snare, and a rumble under the bass",
             @"A tap on each kick and snare, no rumble",
             @"A tap on each kick, and a rumble under the bass"];
}

static void strengthRange(NSString *key, NSInteger *minimum, NSInteger *maximum) {
    BOOL music = [key isEqualToString:SGKeyMusicStrength];
    *minimum = music ? SGMusicStrengthMin : SGControlStrengthMin;
    *maximum = music ? SGMusicStrengthMax : SGControlStrengthMax;
}

double SGHapticsStrength(NSString *key) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return MAX(minimum, MIN(maximum, SGInt(key, 100))) / 100.0;
}

SGMusicFollows SGMusicHapticsFollows(void) {
    NSInteger follows = SGInt(SGKeyMusicFollows, SGMusicFollowsEverything);
    return follows >= SGMusicFollowsEverything && follows <= SGMusicFollowsBass ? (SGMusicFollows)follows : SGMusicFollowsEverything;
}

// A percentage slider over a strength key, telling `changed` each step it stores.
static SGModRow *strengthRow(NSString *key, void (^changed)(void)) {
    NSInteger minimum, maximum;
    strengthRange(key, &minimum, &maximum);
    return SGSliderRow(@"Strength", nil, minimum, maximum, SGStrengthStep,
        ^double { return SGHapticsStrength(key) * 100; },
        ^(double value) {
            SGSetInt(key, lround(value));
            if (changed) changed();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });
}

// The cards, `preview` told when something it reads out changes and shown the slider's taps, `explain` run by a
// tap on the row that says iOS's Music Haptics is off.
static NSArray<SGModSection *> *sections(SGVibrationsPreview *preview, void (^explain)(void)) {
    SGMigrateMusicHaptics();
    __weak SGVibrationsPreview *weakPreview = preview;
    SGModRow *controls = SGSwitchRow(@"Controls", nil, SGKeyControlHaptics);
    controls.changed = ^(BOOL on) { [weakPreview reload]; };
    SGModRow *controlStrength = strengthRow(SGKeyControlStrength, ^{
        // Felt as it is set, and seen: a tap at the new strength with each step, and its ripple.
        SGPlayFeedback(SGFeedbackAdd);
        [weakPreview rippleAt:SGHapticsStrength(SGKeyControlStrength)];
    });
    controlStrength.waitsOn = SGKeyControlHaptics;

    void (^switched)(BOOL) = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGMusicHapticsSwitchesChangedNotification object:nil];
        [weakPreview reload];
    };
    SGModRow *music = SGOptionRow(@"Music Haptics", nil, SGKeyMusicHaptics);
    music.info = kMusicInfo;
    music.changed = switched;
    SGModRow *musicStrength = strengthRow(SGKeyMusicStrength, ^{
        // As Controls' Strength: a kick at the new strength with each step, and its ripple.
        SGMusicHapticsSettingsChanged();
        SGMusicHapticsPreview();
        [weakPreview rippleAt:SGHapticsStrength(SGKeyMusicStrength) / 2];
    });
    musicStrength.waitsOn = SGKeyMusicHaptics;
    SGModRow *follows = SGChoiceRow(@"Follows", nil, SGKeyMusicFollows, followsNames(), SGMusicFollowsEverything);
    follows.choiceNotes = followsNotes();
    follows.chosen = ^(NSInteger index) { SGMusicHapticsSettingsChanged(); };
    follows.waitsOn = SGKeyMusicHaptics;

    SGModRow *background = SGOptionRow(@"In the Background", nil, SGKeyMusicHapticsBackground);
    background.info = kBackgroundInfo;
    background.changed = switched;
    background.visible = ^BOOL { return backgroundAvailable(); };
    // What iOS's own is doing, or, while it is off in Accessibility, a row saying where to turn it on.
    SGModRow *status = SGStatRow(@"Status", ^NSString *{ return SGMusicHapticsStatus(); });
    status.visible = ^BOOL { return SGMusicHapticsInBackground() && SGSystemMusicHapticsOn(); };
    // Under In the Background while the install lacks the key iOS lists apps for Music Haptics by.
    SGModRow *unlisted = SGWarningRow(@"In the Background is missing from this install", @"Tap for why", ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"In the Background is missing"
            message:@"iOS plays Music Haptics only for apps that say they support it. PwEevee's IPA build adds that support to Spotify; injecting the .deb by itself does not, so the vibrations stop when Spotify leaves the screen. Music Haptics above still works while Spotify is open. Build the IPA with PwEevee to get both."
            preferredStyle:UIAlertControllerStyleAlert];
        alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    unlisted.visible = ^BOOL { return backgroundAvailable() && !SGMusicHapticsListedByInstall(); };
    SGModRow *systemOff = SGActionRow(@"Music Haptics is off in iOS", @"Tap to turn it on in Settings", explain);
    systemOff.visible = ^BOOL { return SGMusicHapticsInBackground() && !SGSystemMusicHapticsOn(); };

    return @[
        SGSection(nil, @[SGWithSymbol(controls, @"hand.tap"), controlStrength]),
        SGSection(nil, @[SGWithSymbol(music, @"waveform"), musicStrength, follows, background, unlisted, status, systemOff]),
    ];
}

#pragma mark - the page

@interface SGVibrationsPage : SGModPage
@property (nonatomic, strong) SGVibrationsPreview *preview;
@end

@implementation SGVibrationsPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = self.preview;
    // Music Haptics turned on or off in Accessibility while the page is open, or before coming back to it.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(systemMusicHapticsChanged:) name:SGSystemMusicHapticsChangedNotification object:nil];
}

- (void)systemMusicHapticsChanged:(NSNotification *)note {
    [self refreshVisibility];
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
    self.preview.listening = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.preview.listening = NO;
}

// The row under In the Background that says iOS's Music Haptics is off: what it needs, and the way there.
- (void)explainBackground {
    // iOS opens no Settings page but an app's own from a third-party app (App-prefs: links fail on iOS 27), so the
    // message gives the path from there.
    NSString *message = @"In the Background needs iOS's Music Haptics. Settings opens on Spotify's page: go back to Settings, then Accessibility > Music Haptics, and turn it on.";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Turn On Music Haptics" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Not Now" style:UIAlertActionStyleCancel handler:nil]];
    UIAlertAction *open = [UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
    }];
    [alert addAction:open];
    alert.preferredAction = open;
    [self presentViewController:alert animated:YES completion:nil];
}

@end

UIViewController *SGVibrationsSettingsPage(void) {
    SGVibrationsPreview *preview = [SGVibrationsPreview new];
    __block __weak SGVibrationsPage *weakPage;
    NSArray<SGModSection *> *cards = sections(preview, ^{ [weakPage explainBackground]; });
    SGVibrationsPage *page = [[SGVibrationsPage alloc] initWithTitle:@"Vibrations" intro:nil sections:cards footer:nil];
    page.preview = preview;
    weakPage = page;
    return page;
}
