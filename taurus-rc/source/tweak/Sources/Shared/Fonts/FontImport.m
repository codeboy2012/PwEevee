// A font family of the user's own for Fonts.x: the .ttf, .otf, .ttc or .otc files of one family picked together in
// Files are copied into Application Support, registered with Core Text for this process and named by the
// family name read from them. Like every other font choice it takes over when Spotify starts again, and
// Fonts.x registers the files again on each launch.
#import <CoreText/CoreText.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fonts/Fonts.h"

static NSURL *fontFolder(void) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"spoti.pw" isDirectory:YES] URLByAppendingPathComponent:@"Fonts" isDirectory:YES];
}

// The family name of every face in the file, "" for a face without one; empty when Core Text finds no font. A
// collection gives one per face.
static NSArray<NSString *> *familiesIn(NSURL *url) {
    NSArray *faces = CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id face in faces) {
        NSString *name = CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)face, kCTFontFamilyNameAttribute));
        [names addObject:name ?: @""];
    }
    return names;
}

// The one family name all the faces share, or nil when they differ, one has none, or there are no faces.
NSString *SGFontSingleFamily(NSArray<NSString *> *names) {
    NSSet<NSString *> *distinct = [NSSet setWithArray:names];
    return distinct.count == 1 && distinct.anyObject.length ? distinct.anyObject : nil;
}

// An import from before families is one file under SGKeyAppFontFile and a PostScript name under
// SGKeyAppFontName. It becomes a list of one file and its family name, on first use after the update.
static void migrate(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSString *file = [store stringForKey:SGKeyAppFontFile];
    if (!file.length) return;
    NSString *family = familiesIn([fontFolder() URLByAppendingPathComponent:file.lastPathComponent]).firstObject;
    if (family.length) {
        [store setObject:@[file] forKey:SGKeyAppFontFiles];
        [store setObject:family forKey:SGKeyAppFontName];
    }
    [store removeObjectForKey:SGKeyAppFontFile];
}

// The imported files still in the folder.
static NSArray<NSURL *> *storedFiles(void) {
    migrate();
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *file in [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyAppFontFiles]) {
        NSURL *url = [fontFolder() URLByAppendingPathComponent:file.lastPathComponent];
        if ([NSFileManager.defaultManager fileExistsAtPath:url.path]) [urls addObject:url];
    }
    return urls;
}

static NSString *importedFamily(void) {
    return storedFiles().count ? [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName] : nil;
}

// A face iOS already carries under the same name (Chalkduster, say) is refused as a duplicate and is there
// all the same, so what counts is whether the family has faces afterward. Files that are gone are skipped.
NSString *SGRegisterCustomFont(void) {
    NSString *family = importedFamily();
    for (NSURL *url in storedFiles()) {
        CFErrorRef error = NULL;
        if (!CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error)) {
            NSError *failure = CFBridgingRelease(error);
            SGLog(@"fonts: %@ not registered: %@", url.lastPathComponent, failure.localizedDescription);
        }
    }
    return family && [UIFont fontNamesForFamilyName:family].count ? family : nil;
}

// The imported files unregistered and deleted, and the choice forgotten.
static void removeImported(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    for (NSURL *url in storedFiles()) {
        CTFontManagerUnregisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
    for (NSString *key in @[SGKeyAppFontFiles, SGKeyAppFontName]) [store removeObjectForKey:key];
    if (SGAppFontChosen() == SGAppFontCustom) SGSetInt(SGKeyAppFont, SGAppFontSpotify);
}

static void tell(NSString *title, NSString *message, BOOL restart) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    if (restart) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    } else {
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    }
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// The files are checked and copied aside before the ones in use are touched, so files Core Text will not read,
// of more than one family, or that fail to copy change nothing.
static BOOL sg_lyricsOnly;   // an import for the lyrics' font alone leaves the app's font as it is

static void import(NSArray<NSURL *> *picked) {
    NSMutableArray<NSURL *> *scoped = [NSMutableArray array];
    NSMutableArray<NSString *> *families = [NSMutableArray array];
    BOOL fonts = YES;
    for (NSURL *url in picked) {
        if ([url startAccessingSecurityScopedResource]) [scoped addObject:url];
        NSArray<NSString *> *names = familiesIn(url);
        fonts = fonts && names.count;
        [families addObjectsFromArray:names];
    }
    NSString *family = fonts ? SGFontSingleFamily(families) : nil;
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *incoming = [fontFolder() URLByAppendingPathComponent:@"Incoming" isDirectory:YES];
    NSMutableArray<NSString *> *copied = [NSMutableArray array];
    if (family) {
        [files removeItemAtURL:incoming error:nil];
        [files createDirectoryAtURL:incoming withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSURL *url in picked) {
            NSString *file = url.lastPathComponent;
            if ([files copyItemAtURL:url toURL:[incoming URLByAppendingPathComponent:file] error:nil]) [copied addObject:file];
        }
    }
    for (NSURL *url in scoped) [url stopAccessingSecurityScopedResource];
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    if (family && copied.count == picked.count) {
        removeImported();
        for (NSString *file in copied) {
            NSURL *target = [fontFolder() URLByAppendingPathComponent:file];
            [files removeItemAtURL:target error:nil];
            [files moveItemAtURL:[incoming URLByAppendingPathComponent:file] toURL:target error:nil];
        }
        [files removeItemAtURL:incoming error:nil];
        [store setObject:copied forKey:SGKeyAppFontFiles];
        [store setObject:family forKey:SGKeyAppFontName];
        if (SGRegisterCustomFont()) {
            if (sg_lyricsOnly) {
                tell(@"Font imported", [NSString stringWithFormat:@"%@ is in the lyrics' Font list.", family], NO);
                return;
            }
            SGSetInt(SGKeyAppFont, SGAppFontCustom);
            tell(@"Font imported", [NSString stringWithFormat:@"%@ becomes the app's font when Spotify starts again.", family], YES);
            return;
        }
    }
    [files removeItemAtURL:incoming error:nil];
    if (family && copied.count == picked.count) removeImported();   // copied in but Core Text took none of it
    tell(@"Font not imported", fonts && !family ? @"These files are more than one family. Pick the files of one family together."
                                               : @"Choose valid .ttf, .otf, .ttc or .otc font files.", NO);
}

@interface SGFontPicker : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^done)(void);   // the page's refresh, once the files are in or refused
@end

@implementation SGFontPicker

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    // The alert waits for the picker to be gone, or it has nothing to present over.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (urls.count) import(urls);
        if (self.done) self.done();
    });
}

@end

static void pickFont(void (^done)(void)) {
    static SGFontPicker *delegate;
    if (!delegate) delegate = [SGFontPicker new];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFont] asCopy:YES];
    delegate.done = done;
    picker.delegate = delegate;
    picker.allowsMultipleSelection = YES;
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

// The Lyrics page's Import: the same picker and checks, without making the font the app's.
void SGPickFontForLyrics(void (^done)(void)) {
    sg_lyricsOnly = YES;
    pickFont(^{
        sg_lyricsOnly = NO;
        if (done) done();
    });
}

#pragma mark - the page

// Each choice is drawn in its own font. Core Text makes it, so the font chosen now (Fonts.x hooks UIFont) does
// not dress every row in itself.
static UIFont *previewFont(NSString *nameOrFamily, BOOL family, CGFloat size) {
    CTFontRef font = NULL;
    if (family) {
        CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)@{(id)kCTFontFamilyNameAttribute: nameOrFamily});
        font = CTFontCreateWithFontDescriptor(descriptor, size, NULL);
        CFRelease(descriptor);
    } else if (nameOrFamily) {
        font = CTFontCreateWithName((__bridge CFStringRef)nameOrFamily, size, NULL);
    }
    return font ? (__bridge_transfer UIFont *)font : nil;
}

static UIFont *builtInFont(SGAppFont choice, CGFloat size) {
    if (choice == SGAppFontSpotify) return previewFont(@"SpotifyMixUI-Regular", NO, size);
    UIFontDescriptor *system = ((__bridge_transfer UIFont *)CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL)).fontDescriptor;
    UIFontDescriptorSystemDesign design = choice == SGAppFontRounded ? UIFontDescriptorSystemDesignRounded
        : choice == SGAppFontSerif ? UIFontDescriptorSystemDesignSerif
        : choice == SGAppFontMono ? UIFontDescriptorSystemDesignMonospaced : UIFontDescriptorSystemDesignDefault;
    UIFontDescriptor *descriptor = [system fontDescriptorWithDesign:design] ?: system;
    return (__bridge_transfer UIFont *)CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)descriptor, size, NULL);
}

static NSString *chosenLabel(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGAppFont font = SGAppFontChosen();
    if (font == SGAppFontCustom) return importedFamily() ?: @"Your font";
    if (font == SGAppFontFamily) return [store stringForKey:SGKeyAppFontFamily] ?: SGAppFontNames()[0];
    return SGAppFontNames()[font];
}

typedef NS_ENUM(NSInteger, SGFontSection) { SGFontBuiltIn, SGFontMore, SGFontYours };

@interface SGFontPage : SGPage
@end

@implementation SGFontPage {
    NSArray<NSString *> *_families;
    UIView *_footer;
}

- (instancetype)init {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title = @"Font";
    _families = SGAppFontFamilies();
    SGRegisterCustomFont();   // so the imported family can be drawn here, whichever font is chosen
    return self;
}

// A one-face import says why bold comes out regular; otherwise the note says how to bring the bold along.
- (void)refreshFooter {
    NSString *own = self.styleCount == 1
        ? @"A font of your own is a .ttf or .otf file from Files. This one has a single style, so bold text comes out regular. Pick all the files of a family together to keep bold. "
        : @"A font of your own comes from Files: a .ttf or .otf file, or all the files of one family picked together, so bold and italic stay. ";
    _footer = SGNote([own stringByAppendingString:@"Text Spotify draws itself may keep its own font. Changes apply after you restart Spotify."]);
    self.tableView.tableFooterView = _footer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self refreshFooter];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    SGFitNote(self.tableView, _footer, 8, 24);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)refresh {
    [self refreshFooter];
    [self.tableView reloadData];
}

// The imported family, while there is one, then the row that adds one.
- (NSString *)importedName {
    return importedFamily();
}

// How many faces the imported family has on this iPhone.
- (NSUInteger)styleCount {
    NSString *name = self.importedName;
    return name ? [UIFont fontNamesForFamilyName:name].count : 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    return 3;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == SGFontBuiltIn) return (NSInteger)SGAppFontNames().count;
    if (section == SGFontMore) return (NSInteger)_families.count;
    return self.importedName.length ? 2 : 1;
}

- (UIView *)tableView:(UITableView *)table viewForHeaderInSection:(NSInteger)section {
    return section == SGFontBuiltIn ? nil : SGSectionHeader(table, section == SGFontMore ? @"More fonts" : @"Your fonts");
}

- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    return section == SGFontBuiltIn ? SGSectionGap : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"font");
    CGFloat size = SGTitleFont().pointSize;
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    SGAppFont chosen = SGAppFontChosen();
    NSString *title, *subtitle = nil;
    UIFont *font;
    BOOL selected;
    if (path.section == SGFontBuiltIn) {
        title = SGAppFontNames()[(NSUInteger)path.row];
        font = builtInFont(path.row, size);
        selected = chosen == path.row;
    } else if (path.section == SGFontMore) {
        title = _families[(NSUInteger)path.row];
        font = previewFont(title, YES, size);
        selected = chosen == SGAppFontFamily && [title isEqualToString:[store stringForKey:SGKeyAppFontFamily]];
    } else if (path.row == 0 && self.importedName.length) {
        title = self.importedName;
        font = previewFont(title, YES, size);
        selected = chosen == SGAppFontCustom;
        subtitle = [NSString stringWithFormat:@"%lu style%@", (unsigned long)self.styleCount, self.styleCount == 1 ? @"" : @"s"];
    } else {
        SGFillCell(cell, @"Add a font file", nil, SGGreen(), nil);
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessibilityTraits = UIAccessibilityTraitButton;
        return cell;
    }
    SGFillCell(cell, title, subtitle, nil, nil);
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    if (font) content.textProperties.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:font maximumPointSize:18];
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (selected) {
        UIImageView *tick = SGSymbolView(@"checkmark", 13, UIImageSymbolWeightSemibold, 16);
        tick.tintColor = SGGreen();
        cell.accessoryView = tick;
    }
    cell.accessibilityTraits = selected ? UIAccessibilityTraitButton | UIAccessibilityTraitSelected : UIAccessibilityTraitButton;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (path.section == SGFontBuiltIn) {
        SGSetInt(SGKeyAppFont, path.row);
    } else if (path.section == SGFontMore) {
        [NSUserDefaults.standardUserDefaults setObject:_families[(NSUInteger)path.row] forKey:SGKeyAppFontFamily];
        SGSetInt(SGKeyAppFont, SGAppFontFamily);
    } else if (path.row == 0 && self.importedName.length) {
        SGSetInt(SGKeyAppFont, SGAppFontCustom);
    } else {
        __weak SGFontPage *page = self;
        pickFont(^{ [page refresh]; });
        return;
    }
    [table reloadData];
}

// Swiping the imported family away deletes its files; Default comes back if it was the choice.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    if (path.section != SGFontYours || path.row != 0 || !self.importedName.length) return nil;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
            removeImported();
            [self refresh];
            done(YES);
        }];
    delete.image = [UIImage systemImageNamed:@"trash"];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

@end

NSArray<SGModRow *> *SGAppFontRows(void) {
    SGModRow *font = SGPageRow(@"Font", ^UIViewController *{ return [SGFontPage new]; });
    font.value = ^NSString *{ return chosenLabel(); };
    return @[font];
}
