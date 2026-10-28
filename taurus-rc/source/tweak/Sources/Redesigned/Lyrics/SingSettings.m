// Mod Settings > Karaoke, in the redesign (App/ModSettings.x puts its row on the main page): Sing's switch and
// its voice model. The switch puts the microphone in the player's lyrics and takes it away again at once; off, Sing
// does no work at all. The model row reads out where the download is and moves along with it, over a bar
// while it runs, and the row under it is what can be done next: download it, stop the download, or remove
// the model. Below iOS 18, where the separator cannot run, the section is one row saying so.
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Sing/SGSingController.h"
#import "Shared/Sing/SGSingModel.h"
#import "Shared/Sing/SGSpatialPreview.h"
#import "Sing.h"

// The model's size as the footer and the prompts say it, to the nearest ten megabytes.
static NSString *aboutSize(void) {
    return [NSString stringWithFormat:@"about %lld MB", ((SGSingModelSize() >> 20) + 5) / 10 * 10];
}

static NSString *footer(void) {
    return @"Sing turns the vocals of the song playing down to sing over, from the microphone in its lyrics. "
           "It works on iOS 18 or later. Choose the full model for the best separation (210 MB) or the light "
           "model for a smaller download (31 MB). Each runs only on this iPhone. The switch and the download apply straight away.";
}

static void tell(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static NSString *modelStatus(void) {
    int64_t received = SGSingModelReceived(), size = SGSingModelSize();
    switch (SGSingModelCurrentState()) {
        case SGSingModelInstalled: return [@"Downloaded · " stringByAppendingString:SGSingModelBytesText(size)];
        case SGSingModelChecking: return @"Checking…";
        case SGSingModelDownloading:
            return [NSString stringWithFormat:@"Downloading %lld %% · %lld of %@", received * 100 / size,
                    (received + (1ll << 19)) >> 20, SGSingModelBytesText(size)];
        case SGSingModelMissing:
            if (SGSingModelFailure()) return @"Download failed";
            if (received > 0) return [NSString stringWithFormat:@"Paused · %lld of %@", (received + (1ll << 19)) >> 20, SGSingModelBytesText(size)];
            return @"Not downloaded";
    }
    return nil;
}

// A tap on the model row says what its value is short for.
static void explainModel(void) {
    NSString *failure = SGSingModelFailure();
    switch (SGSingModelCurrentState()) {
        case SGSingModelInstalled:
            tell(@"Voice model", [NSString stringWithFormat:@"It takes %@ on this iPhone. Remove it to free the space; Sing is unavailable without it.",
                                  SGSingModelBytesText(SGSingModelSize())]);
            break;
        case SGSingModelMissing:
            tell(failure ? @"Download failed" : @"Voice model",
                 failure ? [failure stringByAppendingString:@" Download goes on from where it stopped."]
                         : [NSString stringWithFormat:@"Sing needs its voice model, %@, before its microphone shows in the lyrics.", aboutSize()]);
            break;
        default:
            tell(@"Voice model", @"The download goes on while Spotify is in the background. Sing's microphone shows in the lyrics once it is in.");
    }
}

// Enough room first, then the network: nothing leaves on cellular without a yes.
static void startDownload(void) {
    NSString *space = SGSingModelSpaceProblem();
    if (space) { tell(@"Not enough space", space); return; }
    SGSingModelCheckNetwork(^(SGSingModelNetwork network) {
        if (network == SGSingModelOffline) {
            tell(@"No internet connection", @"Connect to Wi-Fi to download Sing's voice model.");
        } else if (network == SGSingModelMetered) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Download over cellular?"
                message:[NSString stringWithFormat:@"This iPhone isn't on Wi-Fi, and Sing's voice model is %@.", aboutSize()]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Download" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                SGSingModelDownload(YES);
            }]];
            [SGTopController() presentViewController:alert animated:YES completion:nil];
        } else {
            SGSingModelDownload(NO);
        }
    });
}

static void confirmRemove(void) {
    BOOL installed = SGSingModelCurrentState() == SGSingModelInstalled;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove the voice model?"
        message:installed ? [NSString stringWithFormat:@"Sing is unavailable until it is downloaded again (%@).", aboutSize()]
                          : [NSString stringWithFormat:@"The %@ downloaded so far are deleted, and the next download starts over.",
                             SGSingModelBytesText(SGSingModelReceived())]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGSingModelRemove();
    }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Below iOS 18 the switch is a row saying what is missing, the way Redesigned UI's does below iOS 26.
static SGModRow *unavailableRow(void) {
    return SGStatActionRow(@"Sing", nil, ^NSString *{ return @"Needs iOS 18"; }, ^{
        tell(@"Sing", [NSString stringWithFormat:@"Sing separates a song's vocals on this iPhone with a voice model that needs iOS 18. "
                       "This iPhone runs iOS %@.", UIDevice.currentDevice.systemVersion]);
    });
}

static SGModSection *karaokeSection(void) {
    if (!SGSingSupported()) return SGNotedSection(@"Karaoke", @[unavailableRow()], footer());
    SGModRow *sing = SGOptionRow(@"Sing", @"The microphone in the lyrics", SGRKeySing);
    sing.changed = ^(BOOL on) { SGRSingApplySwitch(); };
    SGModRow *ignoreResourceWarnings = SGSwitchRow(@"Ignore heat and memory warnings",
        @"Keep Sing running during thermal or memory pressure. This can make your iPhone unstable or cause apps to close.",
        SGKeySingIgnoreResourceWarnings);
    ignoreResourceWarnings.changed = ^(BOOL on) { SGSingResourceWarningsChanged(); };

    NSArray<NSString *> *modelChoices = @[
        [NSString stringWithFormat:@"Best quality · %@", SGSingModelSizeTextOf(SGSingModelFull)],
        [NSString stringWithFormat:@"Light · %@", SGSingModelSizeTextOf(SGSingModelLight)],
    ];
    SGModRow *modelChoice = SGMenuRow(@"Model size", modelChoices,
        ^NSString *{ return modelChoices[SGSingModelChosen()]; },
        ^(NSInteger index) { SGSingModelChoose(index == SGSingModelLight ? SGSingModelLight : SGSingModelFull); });
    modelChoice.refreshOn = SGSingModelDidChangeNotification;

    SGModRow *model = SGStatActionRow(@"Voice model", nil, ^NSString *{ return modelStatus(); }, ^{ explainModel(); });
    model.progress = ^double {
        return SGSingModelCurrentState() == SGSingModelDownloading ? (double)SGSingModelReceived() / SGSingModelSize() : -1;
    };
    model.refreshOn = SGSingModelDidChangeNotification;

    SGModRow *download = SGActionRow(@"Download voice model", nil, ^{ startDownload(); });
    download.visible = ^BOOL { return SGSingModelCurrentState() == SGSingModelMissing; };
    SGModRow *cancel = SGActionRow(@"Cancel download", nil, ^{ SGSingModelCancel(); });
    cancel.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelDownloading || state == SGSingModelChecking;
    };
    // Removing also takes what a stopped download kept, which can be most of the model.
    SGModRow *remove = SGActionRow(@"Remove voice model", nil, ^{ confirmRemove(); });
    remove.color = SGRed();
    remove.visible = ^BOOL {
        SGSingModelState state = SGSingModelCurrentState();
        return state == SGSingModelInstalled || (state == SGSingModelMissing && SGSingModelReceived() > 0);
    };
    SGModRow *spatial = SGPageRow(@"Spatial voice", ^UIViewController *{ return SGSpatialVoiceSettingsPage(); });
    spatial.value = ^NSString *{ return SGSingSpatial() ? @"On" : @"Off"; };
    spatial.visible = ^BOOL { return SGSingSpatialAvailable(); };
    return SGNotedSection(@"Karaoke",
        @[sing, ignoreResourceWarnings, modelChoice, model, download, cancel, remove, spatial], footer());
}

@interface SGSpatialVoicePage : SGModPage
@property (nonatomic, readonly) SGSpatialPreview *preview;
@end

@implementation SGSpatialVoicePage

- (void)viewDidLoad {
    [super viewDidLoad];
    _preview = [[SGSpatialPreview alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 0)];
    self.tableView.tableHeaderView = _preview;
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGSize size = [_preview sizeThatFits:CGSizeMake(table.bounds.size.width, 0)];
    if (CGSizeEqualToSize(_preview.bounds.size, size)) return;
    _preview.frame = (CGRect){_preview.frame.origin, size};
    table.tableHeaderView = _preview;
}

@end

UIViewController *SGSpatialVoiceSettingsPage(void) {
    SGModRow *spatial = SGOptionRow(@"Spatial voice", nil, SGKeySingSpatial);
    __block __weak SGSpatialVoicePage *page;
    spatial.changed = ^(BOOL on) {
        SGSetSingSpatial(on);
        [page.preview refresh];
    };
    SGSpatialVoicePage *made = [[SGSpatialVoicePage alloc] initWithTitle:@"Spatial voice" intro:nil sections:@[
        SGNotedSection(nil, @[spatial],
                       @"The singer's voice keeps its place in front of you as you turn your head, while the rest of the song turns with "
                       @"you; stay turned, and it comes round in front again. It follows your head through headphones that track it "
                       @"and asks for Motion & Fitness the first time. While iOS's own spatial audio is on, the voice is left to it."),
        SGNotedSection(@"Sound", @[
            SGSliderRow(@"Distance", nil, 1, 6.5, 0.5, ^double { return SGSingSpatialDistance(); }, ^(double value) {
                SGSetSingSpatialSound(value, SGSingSpatialRoom(), SGSingSpatialFront(), SGSingSpatialWidth());
            }, ^NSString *(double value) { return [NSString stringWithFormat:@"%.1f m", value]; }),
            SGSliderRow(@"Room", nil, 0, 100, 5, ^double { return SGSingSpatialRoom(); }, ^(double value) {
                SGSetSingSpatialSound(SGSingSpatialDistance(), value, SGSingSpatialFront(), SGSingSpatialWidth());
            }, ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value]; }),
            SGSliderRow(@"Back in front", nil, 5, 60, 1, ^double { return SGSingSpatialFront(); }, ^(double value) {
                SGSetSingSpatialSound(SGSingSpatialDistance(), SGSingSpatialRoom(), value, SGSingSpatialWidth());
            }, ^NSString *(double value) { return [NSString stringWithFormat:@"After %.0f s", value]; }),
            SGSliderRow(@"Instruments width", nil, 0, 200, 5, ^double { return SGSingSpatialWidth(); }, ^(double value) {
                SGSetSingSpatialSound(SGSingSpatialDistance(), SGSingSpatialRoom(), SGSingSpatialFront(), value);
            }, ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value]; }),
        ], @"Distance and room set how far ahead the voice sings and how much of the room surrounds it. Back in front sets how "
           "long a head that stays turned takes to bring the voice ahead again. Instruments width widens or narrows the rest of the song."),
    ] footer:nil];
    page = made;
    return made;
}

UIViewController *SGRKaraokeSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Karaoke" intro:nil sections:@[karaokeSection()] footer:nil];
}

// Beside the main page's row: what Sing would do now, or how far its model has come.
NSString *SGRKaraokeSummary(void) {
    if (!SGSingSupported()) return @"Needs iOS 18";
    SGSingModelState state = SGSingModelCurrentState();
    if (state == SGSingModelDownloading) return [NSString stringWithFormat:@"%lld %%", SGSingModelReceived() * 100 / SGSingModelSize()];
    if (state == SGSingModelChecking) return @"Checking…";
    if (!SGFlag(SGRKeySing, NO)) return @"Off";
    return state == SGSingModelInstalled ? @"On" : @"No model";
}
