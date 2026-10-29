// Imported LRC files, on the Lyrics page beside the sources: the files kept (a swipe deletes one), Import
// for current track…, which links the file to the local file playing, and Import LRC…, matched by title
// and artist. Both open Files and copy the file in.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "LocalFiles.h"
#import "LocalLyrics.h"

typedef NS_ENUM(NSInteger, SGLRCImportRow) {
    SGLRCImportForTrack,
    SGLRCImportByName,
    SGLRCImportRowCount,
};

static void showAlert(UIViewController *owner, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}

// The local file playing, nil for anything else.
static NSString *playingLocalFile(void) {
    NSString *uri = SGURIString(SGPlayerState().track.URI);
    return SGLocalFileIs(uri) ? uri : nil;
}

@interface SGImportedLRCFilesPage : SGPage <UIDocumentPickerDelegate>
@end

@implementation SGImportedLRCFilesPage {
    NSArray<NSString *> *_files;
    UIView *_footer;
    // The local file playing when Files opened for Import for current track, nil for Import LRC….
    NSString *_linkTo;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Imported LRC files";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _footer = SGNote(@"Import for current track links the file to the local file playing, whatever its tags say. "
                      "Import LRC… keeps a file for any track whose title and artist match its [ti:] and [ar:] tags, "
                      "or its name as \"Artist - Title\". Swipe left on a file to delete it.");
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

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _files = SGImportedLRCFiles();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 2;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? MAX((NSInteger)_files.count, 1) : SGLRCImportRowCount;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == 0 ? SGSectionHeader(table, @"Files") : nil;
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == 0 ? UITableViewAutomaticDimension : SGSectionGap;
}

- (UIView *)tableView:(UITableView *)table viewForFooterInSection:(NSInteger)section {
    return nil;
}

- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    return CGFLOAT_MIN;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) {
        UITableViewCell *cell = SGDequeueCell(table, @"import");
        if (path.row == SGLRCImportByName) {
            SGFillCell(cell, @"Import LRC…", @"Matched by title and artist", nil, @"square.and.arrow.down");
        } else {
            NSString *uri = playingLocalFile();
            NSString *title = SGLocalFileInfo(uri)[@"title"] ?: @"The local file playing";
            SGFillCell(cell, @"Import for current track…", uri ? title : @"Start playing a local track first",
                       uri ? nil : SGGrey(), @"music.note");
        }
        BOOL enabled = path.row == SGLRCImportByName || playingLocalFile();
        cell.selectionStyle = enabled ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits = enabled ? UIAccessibilityTraitButton : UIAccessibilityTraitButton | UIAccessibilityTraitNotEnabled;
        return cell;
    }
    UITableViewCell *cell = SGDequeueCell(table, @"file");
    if (!_files.count) {
        SGFillCell(cell, @"No imported files", nil, SGGrey(), nil);
        return cell;
    }
    SGFillCell(cell, _files[(NSUInteger)path.row], nil, nil, nil);
    return cell;
}

- (BOOL)tableView:(UITableView *)table shouldHighlightRowAtIndexPath:(NSIndexPath *)path {
    return path.section == 1 && (path.row == SGLRCImportByName || playingLocalFile());
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section != 1) return;
    _linkTo = path.row == SGLRCImportForTrack ? playingLocalFile() : nil;
    if (path.row == SGLRCImportForTrack && !_linkTo) return;
    // .lrc is nobody's registered type, so Files offers any file and the name is checked after.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != 0 || !_files.count) return nil;
    NSString *name = _files[(NSUInteger)path.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            BOOL deleted = SGDeleteImportedLRC(name);
            if (deleted) [self reloadFiles];
            else showAlert(self, @"Could not delete the file", nil);
            done(deleted);
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

- (void)reloadFiles {
    _files = SGImportedLRCFiles();
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    if (![url.pathExtension.lowercaseString isEqualToString:@"lrc"]) {
        showAlert(self, @"Not an LRC file", @"Pick a file whose name ends in .lrc.");
        return;
    }
    NSError *error = nil;
    NSString *name = SGImportLRC(url, _linkTo, &error);
    if (!name) {
        showAlert(self, @"Could not import the file", error.localizedDescription);
        return;
    }
    [self reloadFiles];
    if (_linkTo) {
        NSString *title = SGLocalFileInfo(_linkTo)[@"title"];
        showAlert(self, @"Lyrics linked", [NSString stringWithFormat:@"%@ now gives the lyrics for %@.", name,
                                                                     title ? [NSString stringWithFormat:@"\"%@\"", title] : @"this local file"]);
    }
}

@end

UIViewController *SGImportedLRCPage(void) {
    return [SGImportedLRCFilesPage new];
}
