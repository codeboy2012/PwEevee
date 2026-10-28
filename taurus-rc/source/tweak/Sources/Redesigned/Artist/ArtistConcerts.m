// The artist page's upcoming concerts: a card of glass under the name and the row of buttons, the ticket
// mark and "Upcoming Concerts" on top, the next two concerts under it, and when there are more the total
// under those; a touch anywhere on it opens the full list as a sheet. The words come in the language the app
// runs in (Shared/Concerts/ConcertsStrings.m), the dates in that language's own format.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Concerts/Concerts.h"
#import "Settings/SGPageStyle.h"
#import "Artist.h"

// The concerts the card itself lists; the rest are behind its touch.
static const NSUInteger kCardRows = 2;
static const CGFloat kPad = 16, kHeaderHeight = 28, kRowHeight = 48, kFooterHeight = 26, kRadius = 24, kDateWidth = 40;

static char kGlassKey, kStateKey;

#pragma mark - one concert

static UILabel *label(UIFont *font, UIColor *color, NSTextAlignment alignment) {
    UILabel *l = [UILabel new];
    l.font = font;
    l.textColor = color;
    l.textAlignment = alignment;
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.userInteractionEnabled = NO;
    return l;
}

// "Cambrils, Spain" / "Spain" / nil, then the time when the concert has one.
static NSString *placeLine(SGConcert *concert) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (concert.city.length) [parts addObject:concert.city];
    if (concert.country.length) [parts addObject:concert.country];
    NSString *place = [parts componentsJoinedByString:@", "];
    NSString *time = concert.hasTime ? SGConcertFormat(concert, @"jmm") : nil;
    if (place.length && time.length) return [NSString stringWithFormat:@"%@ · %@", place, time];
    return place.length ? place : time;
}

@interface SGRConcertRow : UIView
- (instancetype)initWithConcert:(SGConcert *)concert;
@end

@implementation SGRConcertRow {
    UILabel *_month, *_day, *_venue, *_place;
}

- (instancetype)initWithConcert:(SGConcert *)concert {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.userInteractionEnabled = NO;
    _month = label(SGRFont(UIFontTextStyleCaption2, UIFontWeightSemibold, UIContentSizeCategoryLarge), SGRAccent(), NSTextAlignmentCenter);
    _day = label(SGRMonospacedDigitsFont(SGRFont(UIFontTextStyleTitle3, UIFontWeightBold, UIContentSizeCategoryLarge)), SGRPrimary(), NSTextAlignmentCenter);
    _venue = label(SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge), SGRPrimary(), NSTextAlignmentNatural);
    _place = label(SGRFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryLarge), SGRSecondary(), NSTextAlignmentNatural);
    _month.text = [SGConcertFormat(concert, @"MMM") uppercaseStringWithLocale:SGConcertLocale()];
    _day.text = SGConcertFormat(concert, @"d");
    _venue.text = concert.venue ?: concert.title;
    _place.text = placeLine(concert);
    for (UIView *v in @[_month, _day, _venue, _place]) [self addSubview:v];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@, %@", SGConcertFormat(concert, @"EEEEdMMMM"),
                               _venue.text ?: @"", _place.text ?: @""];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = self.bounds.size.height, width = self.bounds.size.width;
    CGFloat monthHeight = ceil(_month.font.lineHeight), dayHeight = ceil(_day.font.lineHeight);
    CGFloat dateTop = round((height - monthHeight - dayHeight) / 2);
    _month.frame = CGRectMake(0, dateTop, kDateWidth, monthHeight);
    _day.frame = CGRectMake(0, dateTop + monthHeight, kDateWidth, dayHeight);
    CGFloat x = kDateWidth + 10, text = MAX(0, width - x);
    CGFloat venueHeight = ceil(_venue.font.lineHeight), placeHeight = _place.text.length ? ceil(_place.font.lineHeight) : 0;
    CGFloat top = round((height - venueHeight - placeHeight) / 2);
    _venue.frame = CGRectMake(x, top, text, venueHeight);
    _place.frame = CGRectMake(x, top + venueHeight, text, placeHeight);
}

@end

#pragma mark - the full list

@interface SGRConcertsListController : UITableViewController
- (instancetype)initWithConcerts:(NSArray<SGConcert *> *)concerts;
@end

@implementation SGRConcertsListController {
    NSArray<NSArray<SGConcert *> *> *_months;
    NSArray<NSString *> *_titles;
}

- (instancetype)initWithConcerts:(NSArray<SGConcert *> *)concerts {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    NSMutableArray<NSMutableArray<SGConcert *> *> *months = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (SGConcert *concert in concerts) {
        NSString *title = [SGConcertFormat(concert, @"LLLL yyyy") capitalizedStringWithLocale:SGConcertLocale()];
        if (![titles.lastObject isEqualToString:title]) {
            [titles addObject:title];
            [months addObject:[NSMutableArray array]];
        }
        [months.lastObject addObject:concert];
    }
    _months = months;
    _titles = titles;
    self.title = SGConcertString(SGConcertTextUpcoming);
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = SGRNeutralField();
    self.tableView.backgroundColor = SGRNeutralField();
    self.tableView.separatorColor = SGRHairline();
    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain
                                                              target:self action:@selector(sgr_close)];
    close.accessibilityLabel = @"Close";
    self.navigationItem.rightBarButtonItem = close;
}

- (void)sgr_close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _months.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _months[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _titles[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const kReuse = @"concert";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kReuse] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kReuse];
    SGConcert *concert = _months[indexPath.section][indexPath.row];
    for (UIView *old in [cell.contentView.subviews copy]) [old removeFromSuperview];
    cell.backgroundColor = SGRElevated(SGRNeutralField());
    SGRConcertRow *row = [[SGRConcertRow alloc] initWithConcert:concert];
    row.frame = CGRectInset(cell.contentView.bounds, 16, 0);
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:row];
    // The ticket link, in the app's language, at the trailing edge.
    UILabel *tickets = label(SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge), SGRAccent(), NSTextAlignmentNatural);
    tickets.text = concert.ticketURL ? SGConcertString(SGConcertTextTickets) : nil;
    [tickets sizeToFit];
    cell.accessoryView = concert.ticketURL ? tickets : nil;
    cell.selectionStyle = concert.ticketURL ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kRowHeight + 8;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *link = _months[indexPath.section][indexPath.row].ticketURL;
    NSURL *url = link ? [NSURL URLWithString:link] : nil;
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end

static void presentList(NSArray<SGConcert *> *concerts) {
    UIViewController *top = SGTopController();
    if (!top) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[SGRConcertsListController alloc] initWithConcerts:concerts]];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = navigation.sheetPresentationController;
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent, UISheetPresentationControllerDetent.largeDetent];
    sheet.prefersGrabberVisible = YES;
    [top presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - the card

@interface SGRConcertsCard : UIControl
- (instancetype)initWithConcerts:(NSArray<SGConcert *> *)concerts;
@end

@implementation SGRConcertsCard {
    NSArray<SGConcert *> *_concerts;
    UIImageView *_logo, *_chevron;
    UILabel *_title, *_total;
    NSArray<SGRConcertRow *> *_rows;
    UIView *_glass;
}

- (instancetype)initWithConcerts:(NSArray<SGConcert *> *)concerts {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _concerts = [concerts copy];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.layer.cornerRadius = kRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    if (SGRReduceTransparency()) {
        self.backgroundColor = SGRSolidGlassFill();
    } else {
        UIVisualEffectView *glass = SGGlassFor(self, &kGlassKey);
        SGShapeGlass(glass, kRadius, NO);
        glass.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _glass = glass;
    }

    _logo = [[UIImageView alloc] initWithImage:SGConcertsLogo()];
    _logo.tintColor = SGRPrimary();
    _logo.contentMode = UIViewContentModeScaleAspectFit;
    _logo.userInteractionEnabled = NO;
    _title = label(SGRFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge), SGRPrimary(), NSTextAlignmentNatural);
    _title.text = SGConcertString(SGConcertTextUpcoming);
    _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"
                                                       withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold]]];
    _chevron.tintColor = SGRTertiary();
    _chevron.contentMode = UIViewContentModeScaleAspectFit;
    _chevron.userInteractionEnabled = NO;
    if (_chevron.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) {
        _chevron.image = [_chevron.image imageWithHorizontallyFlippedOrientation];
    }
    [self addSubview:_logo];
    [self addSubview:_title];
    [self addSubview:_chevron];

    NSMutableArray<SGRConcertRow *> *rows = [NSMutableArray array];
    for (SGConcert *concert in [concerts subarrayWithRange:NSMakeRange(0, MIN(kCardRows, concerts.count))]) {
        SGRConcertRow *row = [[SGRConcertRow alloc] initWithConcert:concert];
        [rows addObject:row];
        [self addSubview:row];
    }
    _rows = rows;
    // More than the card lists: the total, under them.
    if (concerts.count > kCardRows) {
        _total = label(SGRFont(UIFontTextStyleFootnote, UIFontWeightMedium, UIContentSizeCategoryLarge), SGRSecondary(), NSTextAlignmentCenter);
        _total.text = SGConcertCountLine(concerts.count);
        [self addSubview:_total];
    }

    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = _total.text ? [NSString stringWithFormat:@"%@, %@", _title.text, _total.text] : _title.text;
    [self addTarget:self action:@selector(sgr_open) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(sgr_down) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(sgr_up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return self;
}

- (void)sgr_open {
    presentList(_concerts);
}

- (void)sgr_down {
    SGRAnimate(SGRMotionPress, ^{ self.transform = CGAffineTransformMakeScale(0.98, 0.98); }, nil);
}

- (void)sgr_up {
    SGRAnimate(SGRMotionRespond, ^{ self.transform = CGAffineTransformIdentity; }, nil);
}

- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat height = kPad / 2 + kHeaderHeight + _rows.count * kRowHeight + (_total ? kFooterHeight : 0) + kPad / 2;
    return CGSizeMake(size.width, height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    if (_glass && !CGRectEqualToRect(_glass.frame, self.bounds)) _glass.frame = self.bounds;
    CGFloat y = kPad / 2;
    // The mark is as tall as the line of text and as wide as its own proportions make it.
    CGFloat markHeight = 20, markWidth = round(markHeight * _logo.image.size.width / MAX(1, _logo.image.size.height));
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat chevron = 12, titleWidth = MAX(0, width - 2 * kPad - markWidth - 8 - chevron - 8);
    CGFloat markX = rtl ? width - kPad - markWidth : kPad;
    CGFloat titleX = rtl ? markX - 8 - titleWidth : markX + markWidth + 8;
    CGFloat chevronX = rtl ? kPad : width - kPad - chevron;
    _logo.frame = CGRectMake(markX, y + round((kHeaderHeight - markHeight) / 2), markWidth, markHeight);
    _title.frame = CGRectMake(titleX, y, titleWidth, kHeaderHeight);
    _chevron.frame = CGRectMake(chevronX, y, chevron, kHeaderHeight);
    y += kHeaderHeight;
    for (SGRConcertRow *row in _rows) {
        row.frame = CGRectMake(kPad, y, MAX(0, width - 2 * kPad), kRowHeight);
        y += kRowHeight;
    }
    if (_total) _total.frame = CGRectMake(kPad, y, MAX(0, width - 2 * kPad), kFooterHeight);
}

@end

#pragma mark - the page's hookup

static NSString *artistIdentifier(UIView *page) {
    for (UIResponder *responder = page; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class] || ![responder respondsToSelector:@selector(spt_pageURI)]) continue;
        id uri = [(id)responder performSelector:@selector(spt_pageURI)];
        NSString *text = [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : nil;
        if ([text hasPrefix:@"spotify:artist:"]) return [text substringFromIndex:@"spotify:artist:".length];
    }
    return nil;
}

// What the page remembers: the artist asked for, so a name that arrives again does not ask again.
@interface SGRConcertsState : NSObject
@property (nonatomic, copy) NSString *asked;
@end

@implementation SGRConcertsState
@end

void SGRArtistConcerts(SGRHeaderInfo *info, UIView *page, NSString *name, void (^changed)(void)) {
    if (!info || !page.window) return;
    SGRConcertsState *state = objc_getAssociatedObject(info, &kStateKey);
    if (!state) {
        state = [SGRConcertsState new];
        objc_setAssociatedObject(info, &kStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!SGEnabled(SGKeyConcerts) || !name.length) return;
    NSString *identifier = artistIdentifier(page);
    NSString *asked = [NSString stringWithFormat:@"%@|%@", identifier ?: @"", name];
    if ([state.asked isEqualToString:asked]) return;
    state.asked = asked;
    __weak SGRHeaderInfo *weakInfo = info;
    SGConcertsFetch(name, identifier, ^(NSArray<SGConcert *> *concerts) {
        SGRHeaderInfo *strong = weakInfo;
        if (!strong || ![state.asked isEqualToString:asked]) return;
        [strong showCard:concerts.count ? [[SGRConcertsCard alloc] initWithConcerts:concerts] : nil];
        if (changed) changed();
    });
}
