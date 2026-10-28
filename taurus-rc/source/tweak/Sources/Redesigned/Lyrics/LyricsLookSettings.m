// The Lyrics page in the redesign leads with its lyrics playing: a live preview of the lines in the look
// the page sets, the presets under it as a row of glass buttons, and the sliders behind the button after them
// in a sheet that rests at half height without dimming the page, so the preview shows every change as
// it is made. The rest of the page is App/Pages.m's sections, under them.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "LyricsLook.h"
#import "Shared/Fonts/Fonts.h"
#import "SGRKaraokeView.h"

static const CGFloat kPreviewHeight = 230, kCardRadius = 26;
static const CGFloat kPillHeight = 48;
static const CGFloat kChipHeight = 36, kChipGap = 8, kStripGap = 12, kStripPad = 6, kNoteGap = 14;

#pragma mark - the sliders

// A page of the five sliders, each storing as it moves. A preset picked on the page while the sheet is up
// is read back into them; their own changes are not, so a slider is never reloaded under the finger.
@interface SGRLyricsStyleSheet : SGModPage
@property (nonatomic, readonly) CGFloat fittedHeight;   // the table's content once laid out, 0 before
@end

@implementation SGRLyricsStyleSheet {
    CGFloat _fitted;
}

// The sheet's own glass shows through, rather than the black every page is given.
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.clearColor;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(lookChanged:) name:SGRLyricsLookDidChangeNotification object:nil];
}

// The sheet rests as tall as its sliders and note, measured once the table has laid them out.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat height = self.tableView.contentSize.height;
    if (height <= 0 || height == _fitted) return;
    _fitted = height;
    [self.navigationController.sheetPresentationController animateChanges:^{
        [self.navigationController.sheetPresentationController invalidateDetents];
    }];
}

- (CGFloat)fittedHeight {
    return _fitted;
}

// Translucent cards, so the sheet reads as glass all through.
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)lookChanged:(NSNotification *)note {
    if (note.object != self) [self.tableView reloadData];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

typedef void (^SGRLookChange)(SGRLyricsLook *look, double value);

static NSString *share(double value) {
    return value <= 0 ? @"Off" : [NSString stringWithFormat:@"%.0f%%", value * 100];
}

static NSString *points(double value) {
    return [NSString stringWithFormat:@"%.0f pt", value];
}

static SGModRow *lookSlider(NSString *title, double least, double most, double step, CGFloat (^read)(SGRLyricsLook look),
                            SGRLookChange change, NSString *(^format)(double value), id __weak *changer) {
    return SGSliderRow(title, nil, least, most, step, ^double { return read(SGRLyricsLookNow()); }, ^(double value) {
        SGRLyricsLook look = SGRLyricsLookNow();
        change(&look, value);
        SGRSetLyricsLook(look, *changer);
    }, format);
}

static void presentStyleSheet(UIViewController *owner) {
    static __weak id sheetPage;
    NSArray<SGModRow *> *rows = @[
        lookSlider(@"Text size", 22, 40, 1, ^CGFloat(SGRLyricsLook l) { return l.size; },
                   ^(SGRLyricsLook *l, double v) { l->size = v; }, ^NSString *(double v) { return points(v); }, &sheetPage),
        lookSlider(@"Line spacing", 12, 40, 2, ^CGFloat(SGRLyricsLook l) { return l.spacing; },
                   ^(SGRLyricsLook *l, double v) { l->spacing = v; }, ^NSString *(double v) { return points(v); }, &sheetPage),
        lookSlider(@"Blur", 0, 2, 0.1, ^CGFloat(SGRLyricsLook l) { return l.blur; },
                   ^(SGRLyricsLook *l, double v) { l->blur = v; }, ^NSString *(double v) { return share(v); }, &sheetPage),
        lookSlider(@"Glow", 0, 2, 0.1, ^CGFloat(SGRLyricsLook l) { return l.glow; },
                   ^(SGRLyricsLook *l, double v) { l->glow = v; }, ^NSString *(double v) { return share(v); }, &sheetPage),
        lookSlider(@"Wave", 0, 2, 0.1, ^CGFloat(SGRLyricsLook l) { return l.wave; },
                   ^(SGRLyricsLook *l, double v) { l->wave = v; }, ^NSString *(double v) { return share(v); }, &sheetPage),
    ];
    NSArray<NSString *> *fonts = SGRLyricsFontChoices();
    SGModRow *font = SGMenuRow(@"Font", fonts, ^NSString *{ return SGRLyricsFontChoice(); }, ^(NSInteger index) {
        SGRSetLyricsFontChoice(fonts[(NSUInteger)index], sheetPage);
    });
    SGModRow *import = SGActionRow(@"Import a font", @"A .ttf or .otf from Files, only for the lyrics", ^{
        SGPickFontForLyrics(^{
            NSString *family = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyAppFontName];
            if (family.length && [SGRLyricsFontChoices() containsObject:family]) SGRSetLyricsFontChoice(family, nil);
        });
    });
    NSArray<NSString *> *motions = SGRLyricsAnimationNames();
    SGModRow *animation = SGMenuRow(@"Animation", motions, ^NSString *{ return motions[(NSUInteger)SGRLyricsAnimationIndex()]; }, ^(NSInteger index) {
        SGRSetLyricsAnimationIndex(index, sheetPage);
    });
    rows = [rows arrayByAddingObjectsFromArray:@[font, import, animation]];
    SGModRow *reset = SGActionRow(@"Reset to default", @"Apple Music's look, the system font and its animation", ^{
        SGRResetLyricsLook(nil);   // the sheet and the page both read the look again
    });
    NSString *footer = @"Blur is how much the lines away from the one sung soften. Glow and Wave are how strongly a held "
                       @"word glows and its letters rise. 100% is Apple Music's. Font and Animation are for the lyrics only. Wave, Glow, Bounce and Ripple move each letter as it is sung (Glow and Wave above set how much); Float lifts the whole word.";
    SGRLyricsStyleSheet *page = [[SGRLyricsStyleSheet alloc] initWithTitle:@"Lyrics Style" intro:nil
                                                                 sections:@[SGNotedSection(nil, rows, footer),
                                                                           SGSection(nil, @[reset])] footer:nil];
    sheetPage = page;
    page.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                                                          target:page action:@selector(close)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    nav.view.backgroundColor = UIColor.clearColor;
    // Outside Spotify's own stacks the sheet would take the system's appearance, light in light mode.
    SGPresentDark(nav);
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    // As tall as the sliders, half the screen until they are measured, so the preview at the top of the page stays
    // in sight and undimmed, and its buttons live.
    NSString *fit = @"fit";
    __weak SGRLyricsStyleSheet *weakPage = page;
    sheet.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:fit resolver:^CGFloat(id<UISheetPresentationControllerDetentResolutionContext> context) {
        CGFloat measured = weakPage.fittedHeight;
        return measured > 0 ? MIN(measured + 56, context.maximumDetentValue * 0.55) : context.maximumDetentValue * 0.5;
    }], UISheetPresentationControllerDetent.largeDetent];   // pull it up to reach Font, Animation and Reset
    sheet.largestUndimmedDetentIdentifier = fit;
    sheet.prefersGrabberVisible = YES;
    sheet.prefersScrollingExpandsWhenScrolledToEdge = YES;
    [owner presentViewController:nav animated:YES completion:nil];
}

#pragma mark - the page

// Black text on a light accent, white on a dark one.
static UIColor *readableOn(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.55 ? UIColor.blackColor : UIColor.whiteColor;
}

static UIButtonConfiguration *chipConfiguration(NSString *title, NSString *symbol, BOOL chosen) {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) {
        config = chosen ? [UIButtonConfiguration prominentGlassButtonConfiguration] : [UIButtonConfiguration glassButtonConfiguration];
    } else {
        config = chosen ? [UIButtonConfiguration filledButtonConfiguration] : [UIButtonConfiguration grayButtonConfiguration];
    }
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    if (chosen) config.baseBackgroundColor = SGRAccent();
    config.baseForegroundColor = chosen ? readableOn(SGRAccent()) : UIColor.whiteColor;
    config.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 0, 14);
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]}];
    if (symbol) {
        config.image = [UIImage systemImageNamed:symbol];
        config.preferredSymbolConfigurationForImage = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        config.imagePadding = 6;
    }
    return config;
}

@interface SGRLyricsPage : SGModPage
- (instancetype)initWithTitle:(NSString *)title note:(NSString *)note sections:(NSArray<SGModSection *> *)sections;
@end

@implementation SGRLyricsPage {
    UIView *_header, *_card;
    SGRKaraokeView *_preview;
    UIScrollView *_strip;          // the presets, scrolled sideways when they do not all fit
    NSArray<UIButton *> *_chips;
    UIButton *_adjust;             // the sliders' button, after the last preset
    UIButton *_reset;              // Default: the look, font and animation back to Apple Music's
    SGRLyricsSongPill *_pill;      // the glass player above the card, to search a song to try the look on
    UILabel *_note;
    UISelectionFeedbackGenerator *_feedback;
    BOOL _stripPlaced, _showChosen;
}

- (instancetype)initWithTitle:(NSString *)title note:(NSString *)note sections:(NSArray<SGModSection *> *)sections {
    if (!(self = [super initWithTitle:title intro:nil sections:sections footer:nil])) return nil;
    _note = [UILabel new];
    _note.text = note;
    _note.font = SGSubtitleFont();
    _note.textColor = SGGrey();
    _note.numberOfLines = 0;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _header = [UIView new];
    _card = [UIView new];
    _card.backgroundColor = SGCardBackground();
    _card.layer.cornerRadius = kCardRadius;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.clipsToBounds = YES;
    _card.isAccessibilityElement = YES;
    _card.accessibilityLabel = @"Preview of the lyrics";
    _preview = [[SGRKaraokeView alloc] initWithSampleLines:SGRLyricsSampleLines() length:SGRLyricsSampleLength()];
    _preview.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_card addSubview:_preview];
    [_header addSubview:_card];
    _pill = [SGRLyricsSongPill new];
    _pill.resultsHost = _card;
    __weak SGRKaraokeView *weakPreview = _preview;
    _pill.picked = ^(NSArray<SGKaraokeLine *> *lines, NSTimeInterval length, NSString *title, NSString *artist) {
        [weakPreview setSampleLines:lines length:length];
    };
    _pill.togglePlay = ^(BOOL playing) { weakPreview.samplePaused = !playing; };
    [_header addSubview:_pill];

    _strip = [UIScrollView new];
    _strip.showsHorizontalScrollIndicator = NO;
    _strip.alwaysBounceHorizontal = YES;
    NSMutableArray<UIButton *> *chips = [NSMutableArray array];
    for (NSUInteger i = 0; i < SGRLyricsLookPresetNames().count; i++) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        chip.tag = (NSInteger)i;
        [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventPrimaryActionTriggered];
        [_strip addSubview:chip];
        [chips addObject:chip];
    }
    _chips = chips;
    _adjust = [UIButton buttonWithType:UIButtonTypeSystem];
    [_adjust addTarget:self action:@selector(adjustTapped) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_strip addSubview:_adjust];
    _reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [_reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventPrimaryActionTriggered];
    [_strip addSubview:_reset];
    [_header addSubview:_strip];
    [_header addSubview:_note];
    _feedback = [UISelectionFeedbackGenerator new];
    [self showLook];
    self.tableView.tableHeaderView = _header;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(showLook) name:SGRLyricsLookDidChangeNotification object:nil];
}

// Which preset the look is, lit and scrolled into sight; a look of the sliders' own lights their button.
- (void)showLook {
    NSInteger chosen = SGRLyricsLookPresetIndex(SGRLyricsLookNow());
    NSArray<NSString *> *names = SGRLyricsLookPresetNames();
    for (UIButton *chip in _chips) {
        BOOL lit = chip.tag == chosen;
        chip.configuration = chipConfiguration(names[(NSUInteger)chip.tag], nil, lit);
        chip.accessibilityTraits = UIAccessibilityTraitButton | (lit ? UIAccessibilityTraitSelected : 0);
    }
    UIButtonConfiguration *adjust = chipConfiguration(@"", @"slider.horizontal.3", chosen < 0);
    adjust.attributedTitle = nil;
    adjust.contentInsets = NSDirectionalEdgeInsetsZero;
    _adjust.configuration = adjust;
    _adjust.accessibilityLabel = @"Adjust";
    _adjust.accessibilityValue = chosen < 0 ? @"Custom" : names[(NSUInteger)chosen];
    _adjust.accessibilityHint = @"Opens the sliders";
    _adjust.accessibilityTraits = UIAccessibilityTraitButton | (chosen < 0 ? UIAccessibilityTraitSelected : 0);
    _reset.configuration = chipConfiguration(@"Default", @"arrow.counterclockwise", NO);
    _reset.accessibilityLabel = @"Reset the lyrics to default";
    _showChosen = YES;
    [self.view setNeedsLayout];
}

- (void)chipTapped:(UIButton *)chip {
    NSUInteger i = (NSUInteger)chip.tag;
    if (SGRLyricsLookPresetIndex(SGRLyricsLookNow()) == (NSInteger)i) return;
    [_feedback selectionChanged];
    SGRSetLyricsLook(SGRLyricsLookPreset(i), self);
}

- (void)resetTapped {
    [_feedback selectionChanged];
    SGRResetLyricsLook(self);
}

- (void)adjustTapped {
    presentStyleSheet(self);
}

// The header keeps the height it is given, so it is measured here and handed back to the table when it
// changes: the card at the table's inset, the presets and then the sliders' button in a strip that scrolls
// from edge to edge of the screen, and the note under them.
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width, inset = table.layoutMargins.left, inner = width - 2 * inset;
    if (inner <= 0) return;
    _pill.frame = CGRectMake(inset, SGRGrid, inner, kPillHeight);
    _card.frame = CGRectMake(inset, CGRectGetMaxY(_pill.frame) + kStripGap, inner, kPreviewHeight);
    CGFloat x = 0, top = CGRectGetMaxY(_card.frame) + kStripGap;
    for (UIButton *chip in _chips) {
        CGFloat wide = ceil([chip sizeThatFits:CGSizeMake(CGFLOAT_MAX, kChipHeight)].width);
        chip.frame = CGRectMake(x, kStripPad, wide, kChipHeight);
        x += wide + kChipGap;
    }
    _adjust.frame = CGRectMake(x, kStripPad, kChipHeight, kChipHeight);
    x += kChipHeight + kChipGap;
    CGFloat resetWide = ceil([_reset sizeThatFits:CGSizeMake(CGFLOAT_MAX, kChipHeight)].width);
    _reset.frame = CGRectMake(x, kStripPad, resetWide, kChipHeight);
    x += resetWide + kChipGap;
    // Padded above and below so the glass's shadow is not cut off where the strip clips its sides.
    _strip.frame = CGRectMake(0, top, width, kChipHeight + 2 * kStripPad);
    _strip.contentInset = UIEdgeInsetsMake(0, inset, 0, inset);
    _strip.contentSize = CGSizeMake(MAX(0, x - kChipGap), _strip.bounds.size.height);
    if (!_stripPlaced) {   // the first button at the inset, where the card starts
        _strip.contentOffset = CGPointMake(-inset, 0);
        _stripPlaced = YES;
    }
    NSInteger chosen = SGRLyricsLookPresetIndex(SGRLyricsLookNow());
    if (_showChosen && chosen >= 0) {
        [_strip scrollRectToVisible:CGRectInset(_chips[(NSUInteger)chosen].frame, -kChipGap, 0) animated:self.view.window != nil];
    }
    _showChosen = NO;
    CGFloat noteHeight = _note.text.length ? ceil([_note sizeThatFits:CGSizeMake(inner, CGFLOAT_MAX)].height) : 0;
    _note.frame = CGRectMake(inset, CGRectGetMaxY(_strip.frame) + kNoteGap - kStripPad, inner, noteHeight);
    CGSize size = CGSizeMake(width, CGRectGetMaxY(_note.frame));
    if (CGSizeEqualToSize(_header.bounds.size, size)) return;
    _header.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = _header;
}

@end

UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections) {
    return [[SGRLyricsPage alloc] initWithTitle:title note:intro sections:sections];
}
