// Edit info, in the player's ⋯ menu while a local file plays, under either look: a row that opens an
// editor for the file's title, artist, album and cover, stored by the mod (LocalFiles.h).
//
// The menu is Spotify's context menu sheet, ContextMenu_InternalImpl.ContextMenuViewController, whose
// rows come from Swift item factories with no way in (Shared/Player/SpeedPitchMenu.x says more). So the
// row is the table's footer, as Speed and pitch is its header, and the sheet is the player's by
// Speed and pitch's own test. Speed and pitch takes the footer when Spotify has a header of its own in
// the table, so then the footer is left to it and Edit info is left out.
//
// The menu says nothing of the track it is for, so the row is only offered on the player's own menu,
// which is for the track playing.
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "LocalFiles.h"

// The sheet's own measures, as Speed and pitch has them.
static const CGFloat kRowHeight = 56, kSideMargin = 16, kIconSide = 24;

static char kRowKey, kDecidedKey;

static UIFont *rowFont(void) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (UIContentSizeCategoryCompareToCategory(current, UIContentSizeCategoryExtraLarge) == NSOrderedDescending) current = UIContentSizeCategoryExtraLarge;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    return [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:traits].pointSize];
}

#pragma mark - the editor

// A form sheet over the player: the three names, the cover with a menu to change it, and a row that puts
// the file's own info back. Nothing is stored until Save, so Cancel undoes everything, a cover picked
// or removed and a restore too; a swipe down with changes asks first.

typedef NS_ENUM(NSInteger, SGCoverChange) { SGCoverKept, SGCoverPicked, SGCoverRemoved };

static NSArray<NSString *> *fieldKeys(void) {
    return @[@"title", @"artist", @"album"];
}

static NSArray<NSString *> *fieldLabels(void) {
    return @[@"Title", @"Artist", @"Album"];
}

static NSString *trimmed(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

@interface SGLocalFileEditor : UITableViewController <UITextFieldDelegate, UIAdaptivePresentationControllerDelegate,
                                                      UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
- (instancetype)initWithURI:(NSString *)uri;
@end

@implementation SGLocalFileEditor {
    NSString *_uri;
    NSDictionary<NSString *, id> *_tags, *_shown;   // the file's own names, and the ones it goes by now
    NSArray<UITextField *> *_fields;
    NSArray<UILabel *> *_labels;
    NSArray<UIStackView *> *_stacks;
    NSArray<NSLayoutConstraint *> *_labelWidths;
    UITableViewCell *_coverCell, *_restoreCell;
    UIButton *_coverButton;
    UIImage *_cover;            // the cover the row shows: the stored one, or the one just picked
    SGCoverChange _coverChange;
    BOOL _hasStoredCover;
}

- (instancetype)initWithURI:(NSString *)uri {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _uri = [uri copy];
    _tags = SGLocalFileTags(uri) ?: @{};
    _shown = SGLocalFileInfo(uri) ?: @{};
    NSString *path = SGLocalFileCoverPath(SGLocalFileEditFor(uri));
    _cover = path ? [UIImage imageWithContentsOfFile:path] : nil;
    _hasStoredCover = _cover != nil;

    NSMutableArray *fields = [NSMutableArray array], *labels = [NSMutableArray array], *stacks = [NSMutableArray array], *widths = [NSMutableArray array];
    for (NSUInteger i = 0; i < fieldKeys().count; i++) {
        NSString *key = fieldKeys()[i];
        UILabel *label = [UILabel new];
        label.text = fieldLabels()[i];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.isAccessibilityElement = NO;   // the field reads its own label
        UITextField *field = [UITextField new];
        field.text = _shown[key];
        field.placeholder = _tags[key] ?: fieldLabels()[i];
        field.accessibilityLabel = fieldLabels()[i];
        field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        field.adjustsFontForContentSizeCategory = YES;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeWords;
        field.returnKeyType = i + 1 < fieldKeys().count ? UIReturnKeyNext : UIReturnKeyDone;
        field.delegate = self;
        [field addTarget:self action:@selector(changed) forControlEvents:UIControlEventEditingChanged];
        [field setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, field]];
        stack.spacing = 12;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [fields addObject:field];
        [labels addObject:label];
        [stacks addObject:stack];
        [widths addObject:[label.widthAnchor constraintEqualToConstant:0]];
    }
    _fields = fields;
    _labels = labels;
    _stacks = stacks;
    _labelWidths = widths;

    self.title = @"Edit info";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(save)];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _coverCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    _coverCell.selectionStyle = UITableViewCellSelectionStyleNone;
    UIButtonConfiguration *change = [UIButtonConfiguration plainButtonConfiguration];
    change.title = @"Change";
    _coverButton = [UIButton buttonWithConfiguration:change primaryAction:nil];
    _coverButton.showsMenuAsPrimaryAction = YES;
    _coverButton.accessibilityLabel = @"Change cover";
    _coverCell.accessoryView = _coverButton;
    _restoreCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [self fitLabels];
    [self showCover];
    [self changed];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitLabels) name:UIContentSizeCategoryDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// The names' labels share one width so the fields line up; at the accessibility sizes each label goes
// above its field instead.
- (void)fitLabels {
    BOOL stacked = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UIFont *font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:self.traitCollection];
    CGFloat widest = 0;
    for (NSString *text in fieldLabels()) widest = MAX(widest, ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width));
    for (NSUInteger i = 0; i < _stacks.count; i++) {
        _stacks[i].axis = stacked ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
        _stacks[i].alignment = stacked ? UIStackViewAlignmentFill : UIStackViewAlignmentFirstBaseline;
        _labelWidths[i].constant = widest;
        _labelWidths[i].active = !stacked;
    }
}

#pragma mark - state

- (NSDictionary<NSString *, NSString *> *)names {
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < _fields.count; i++) names[fieldKeys()[i]] = _fields[i].text ?: @"";
    return names;
}

// A name the way it would be stored: an empty field is the file's own.
- (NSString *)effectiveName:(NSUInteger)i {
    NSString *typed = trimmed(_fields[i].text);
    return typed.length ? typed : _tags[fieldKeys()[i]] ?: @"";
}

- (BOOL)isDirty {
    if (_coverChange != SGCoverKept) return YES;
    for (NSUInteger i = 0; i < _fields.count; i++) {
        if (![[self effectiveName:i] isEqualToString:_shown[fieldKeys()[i]] ?: @""]) return YES;
    }
    return NO;
}

- (BOOL)differsFromFile {
    if (_cover) return YES;
    for (NSUInteger i = 0; i < _fields.count; i++) {
        if (![[self effectiveName:i] isEqualToString:_tags[fieldKeys()[i]] ?: @""]) return YES;
    }
    return NO;
}

- (void)changed {
    BOOL dirty = self.isDirty;
    self.navigationItem.rightBarButtonItem.enabled = dirty;
    // A swipe down then asks before the changes go (presentationControllerDidAttemptToDismiss:).
    self.modalInPresentation = dirty;
    BOOL restorable = self.differsFromFile;
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = @"Restore file's info";
    content.textProperties.color = restorable ? UIColor.systemRedColor : UIColor.tertiaryLabelColor;
    _restoreCell.contentConfiguration = content;
    _restoreCell.userInteractionEnabled = restorable;
    _restoreCell.accessibilityTraits = UIAccessibilityTraitButton | (restorable ? 0 : UIAccessibilityTraitNotEnabled);
}

- (void)showCover {
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = @"Cover";
    content.secondaryText = !_cover ? @"The file's own" : _coverChange == SGCoverPicked ? @"New picture" : @"Your picture";
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = _cover ?: [UIImage systemImageNamed:@"music.note"];
    content.imageProperties.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleTitle2];
    content.imageProperties.tintColor = UIColor.secondaryLabelColor;
    content.imageProperties.maximumSize = CGSizeMake(56, 56);
    content.imageProperties.reservedLayoutSize = CGSizeMake(56, 56);
    content.imageProperties.cornerRadius = 8;
    content.imageProperties.accessibilityIgnoresInvertColors = YES;
    _coverCell.contentConfiguration = content;

    __weak typeof(self) weakSelf = self;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray arrayWithArray:@[
        [UIAction actionWithTitle:@"Choose from Photos" image:[UIImage systemImageNamed:@"photo.on.rectangle"] identifier:nil handler:^(UIAction *action) {
            [weakSelf pickCoverFromFiles:NO];
        }],
        [UIAction actionWithTitle:@"Choose from Files" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *action) {
            [weakSelf pickCoverFromFiles:YES];
        }],
    ]];
    if (_cover) {
        UIAction *remove = [UIAction actionWithTitle:@"Remove cover" image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
            [weakSelf useCover:nil];
        }];
        remove.attributes = UIMenuElementAttributesDestructive;
        [items addObject:remove];
    }
    _coverButton.menu = [UIMenu menuWithChildren:items];
    [_coverButton sizeToFit];
}

// nil removes the cover: the stored one goes on Save, a picked one goes at once.
- (void)useCover:(UIImage *)image {
    _cover = image;
    _coverChange = image ? SGCoverPicked : _hasStoredCover ? SGCoverRemoved : SGCoverKept;
    [self showCover];
    [self changed];
}

#pragma mark - the actions

- (void)restore {
    for (NSUInteger i = 0; i < _fields.count; i++) _fields[i].text = _tags[fieldKeys()[i]];
    [self.view endEditing:YES];
    [self useCover:nil];
}

- (void)save {
    [self.view endEditing:YES];
    SGLocalFileSaveEdit(_uri, self.names, _coverChange == SGCoverPicked ? _cover : nil, _coverChange != SGCoverRemoved);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancel {
    if (self.isDirty) [self confirmDiscard];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)confirmDiscard {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Discard changes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Keep editing" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.leftBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)presentationControllerDidAttemptToDismiss:(UIPresentationController *)presentationController {
    [self confirmDiscard];
}

- (void)pickCoverFromFiles:(BOOL)files {
    [self.view endEditing:YES];
    UIViewController *picker;
    if (files) {
        // A copy, so it is the app's own to read.
        UIDocumentPickerViewController *documents = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES];
        documents.delegate = self;
        picker = documents;
    } else {
        // Runs out of the app's process, so no Photos permission is asked.
        UIImagePickerController *photos = [UIImagePickerController new];
        photos.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        photos.delegate = self;
        picker = photos;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    if (image) [self useCover:image];
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data = urls.firstObject ? [NSData dataWithContentsOfURL:urls.firstObject] : nil;
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    if (image) {
        [self useCover:image];
        return;
    }
    SGLog(@"local files: %@ is not an image", urls.firstObject.lastPathComponent);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Not an image" message:@"Pick a JPEG, PNG or HEIC file."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSUInteger i = [_fields indexOfObject:field];
    if (i != NSNotFound && i + 1 < _fields.count) [_fields[i + 1] becomeFirstResponder];
    else [field resignFirstResponder];
    return NO;
}

#pragma mark - the table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? (NSInteger)_fields.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"Kept by PwEevee for this file. The file itself is not changed." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) return _coverCell;
    if (indexPath.section == 2) return _restoreCell;
    // One cell per name, made once: the field keeps what was typed while the table scrolls.
    UIStackView *stack = _stacks[(NSUInteger)indexPath.row];
    if (stack.superview) return (UITableViewCell *)stack.superview.superview;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    [cell.contentView addSubview:stack];
    UILayoutGuide *margins = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:margins.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor],
    ]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) [_fields[(NSUInteger)indexPath.row] becomeFirstResponder];
    if (indexPath.section == 2) [self restore];
}

@end

static UIViewController *topOf(UIViewController *presenter) {
    UIViewController *top = presenter;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

void SGLocalFilePresentEditor(UIViewController *presenter, NSString *uri) {
    if (!presenter || !SGLocalFileIs(uri)) return;
    SGLocalFileEditor *editor = [[SGLocalFileEditor alloc] initWithURI:uri];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    // Outside Spotify's navigation stacks a sheet takes the system's appearance, light in light mode.
    SGPresentDark(navigation);
    navigation.presentationController.delegate = editor;
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    [topOf(presenter) presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - the row

@interface SGEditInfoRow : UIControl
@property (nonatomic, copy) NSString *uri;
@property (nonatomic, weak) UIViewController *menu;
@end

@implementation SGEditInfoRow {
    UIImageView *_icon;
    UILabel *_title;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIColor *secondary = [UIColor colorWithWhite:1 alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.80 : 0.65];
    UIImage *glyph = [UIImage systemImageNamed:@"pencil" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular]];
    // Colors drawn in, so nothing passes through the sheet's tint.
    _icon = [[UIImageView alloc] initWithImage:[glyph imageWithTintColor:secondary renderingMode:UIImageRenderingModeAlwaysOriginal]];
    _icon.contentMode = UIViewContentModeCenter;
    _title = [UILabel new];
    _title.font = rowFont();
    _title.textColor = UIColor.whiteColor;
    _title.text = @"Edit info";
    for (UIView *view in @[_icon, _title]) {
        view.userInteractionEnabled = NO;
        [self addSubview:view];
    }
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"Edit info";
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(highlight) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(unhighlight) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _icon.frame = CGRectMake(kSideMargin, (kRowHeight - kIconSide) / 2, kIconSide, kIconSide);
    CGFloat titleX = kSideMargin + kIconSide + kSideMargin;
    _title.frame = CGRectMake(titleX, 0, MAX(0, width - titleX - kSideMargin), kRowHeight);
}

- (void)highlight {
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)unhighlight {
    [UIView animateWithDuration:0.2 animations:^{ self.backgroundColor = UIColor.clearColor; }];
}

// One sheet at a time: Spotify's menu goes before the editor comes up over what presented it.
- (void)open {
    UIViewController *menu = self.menu, *host = menu.presentingViewController;
    NSString *uri = self.uri;
    if (!host) {
        SGLocalFilePresentEditor(menu, uri);
        return;
    }
    [menu dismissViewControllerAnimated:YES completion:^{ SGLocalFilePresentEditor(host, uri); }];
}

@end

#pragma mark - the menu

static UITableView *findTable(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = findTable(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static BOOL freeSlot(UIView *view) {
    return !view || view.bounds.size.height < 1;
}

static void decide(UIViewController *menu, BOOL offered) {
    objc_setAssociatedObject(menu, &kDecidedKey, @(offered), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    if (!root || [objc_getAssociatedObject(menu, &kDecidedKey) isEqual:@NO]) return;
    UITableView *table = findTable(root, 0);
    CGFloat width = table.bounds.size.width;
    if (width <= 0) return;
    SGEditInfoRow *row = objc_getAssociatedObject(menu, &kRowKey);
    if (!row) {
        NSString *uri = SGURIString(SGPlayerState().track.URI);
        if (!SGLocalFileIs(uri)) {
            decide(menu, NO);
            return;
        }
        // A header of Spotify's own sends Speed and pitch to the footer.
        UIView *header = table.tableHeaderView;
        BOOL headerOurs = freeSlot(header) || [NSStringFromClass(header.class) hasPrefix:@"SG"];
        if (!headerOurs || !freeSlot(table.tableFooterView)) {
            SGLog(@"local files: the menu's table has %@ and %@, Edit info left out",
                  header ? NSStringFromClass(header.class) : @"no header", table.tableFooterView ? NSStringFromClass(table.tableFooterView.class) : @"no footer");
            decide(menu, NO);
            return;
        }
        decide(menu, YES);
        row = [[SGEditInfoRow alloc] initWithFrame:CGRectMake(0, 0, width, kRowHeight)];
        row.uri = uri;
        row.menu = menu;
        objc_setAssociatedObject(menu, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        table.tableFooterView = row;
        [table invalidateIntrinsicContentSize];
        SGLog(@"local files: Edit info offered for %@", uri);
        return;
    }
    // Spotify replaced the footer, or the table changed width: put it back at the table's width.
    if (table.tableFooterView != row || fabs(row.frame.size.width - width) > 0.5) {
        row.frame = CGRectMake(0, row.frame.origin.y, width, kRowHeight);
        table.tableFooterView = row;
        [table invalidateIntrinsicContentSize];
    }
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController"]);
}
