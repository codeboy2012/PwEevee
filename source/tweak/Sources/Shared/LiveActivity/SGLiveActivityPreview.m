// The card is built again for every step, from stack views that follow the widget's SwiftUI stacks one for one
// (FamilyView, LyricsView, QueueView, PanelView and its pages), at the sizes its text styles have at the default
// text size: it is a picture of the lock screen, so it does not grow with the page's text. The new card
// crossfades over the old one. The step timer runs only while the page shows and Spotify is in front.
#import "Core/SGCore.h"
#import "LiveActivity.h"
#import "SGLiveActivityPreview.h"

static const NSTimeInterval kStep = 3, kFade = 0.35;
static const CGFloat kTop = 4, kBottom = 16;           // around the slice, inside the table's header
static const CGFloat kCorner = 30, kDateTop = 16, kCardGap = 8, kCardInset = 12, kSliceBottom = 14;
// iOS clips a lock screen Live Activity at this height, and the card here with it.
static const CGFloat kClip = 160;

// The widget's colors: Spotify's green, the chips' idle fill, and the made-up cover's color as LiveActivity.x
// works it out: darkened behind the card, lightened as Colors' Artwork accent.
static UIColor *green(void) { return [UIColor colorWithRed:0.12 green:0.84 blue:0.38 alpha:1]; }
static UIColor *idle(void) { return [UIColor colorWithWhite:1 alpha:0.08]; }
static UIColor *dim(CGFloat alpha) { return [UIColor colorWithWhite:1 alpha:alpha]; }
static UIColor *sampleTint(void) { return [UIColor colorWithRed:0x54 / 255.0 green:0x2C / 255.0 blue:0x32 / 255.0 alpha:1]; }
static UIColor *sampleAccent(void) { return [UIColor colorWithRed:0xD7 / 255.0 green:0xB0 / 255.0 blue:0xB5 / 255.0 alpha:1]; }

// The text styles the widget uses, at the default text size.
static UIFont *font(CGFloat size, UIFontWeight weight) { return [UIFont systemFontOfSize:size weight:weight]; }
static const CGFloat kHeadline = 17, kTitle3 = 20, kTitle2 = 22, kSubheadline = 15, kFootnote = 13, kCaption = 12, kCaption2 = 11;

// A made-up song.
static NSString *const kTitle = @"Paper Lanterns", *const kArtist = @"The Quiet Harbor";
static NSString *const kQuietTitle = @"Low Tide (Interlude)";
typedef struct { __unsafe_unretained NSString *line, *next, *translation; } Line;
static const Line kLines[] = {
    {@"We hung our wishes on paper lanterns", @"and watched them drift across the bay", @"Colgamos nuestros deseos en farolillos de papel"},
    {@"and watched them drift across the bay", @"Every light a little promise", @"y los vimos flotar por la bahía"},
    {@"Every light a little promise", @"the morning couldn't take away", @"Cada luz, una pequeña promesa"},
};
static const NSInteger kLineCount = 3;
static NSString *const kQueue[][2] = {
    {@"Salt and Static", @"Mira Vale"},
    {@"Northbound Lights", @"The Quiet Harbor"},
    {@"Glasshouse", @"Juniper & Cole"},
};

typedef NS_ENUM(NSInteger, Tab) { TabControls, TabQueue, TabTimer, TabCount };

static NSInteger stepsIn(NSInteger view) {
    switch (view) {
        case SGLiveActivityLyrics: return kLineCount + 1;   // the lines, then a track with no lyrics
        case SGLiveActivityPanel: return TabCount;
        default: return 1;
    }
}

#pragma mark - pieces

static UILabel *label(NSString *text, UIFont *font, UIColor *color, NSInteger lines, NSTextAlignment alignment) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.textAlignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static UIStackView *stack(NSArray<UIView *> *views, UILayoutConstraintAxis axis, CGFloat spacing) {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = axis;
    stack.spacing = spacing;
    return stack;
}

static UIImageView *symbol(NSString *name, CGFloat size, UIFontWeight weight, UIColor *color) {
    UIImageSymbolWeight symbolWeight = weight >= UIFontWeightSemibold ? UIImageSymbolWeightSemibold : UIImageSymbolWeightRegular;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:size weight:symbolWeight];
    UIImageView *view = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:name withConfiguration:config]];
    view.tintColor = color;
    view.contentMode = UIViewContentModeCenter;
    [view setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return view;
}

static void pin(UIView *view, CGFloat height) {
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
}

// A rounded fill holding `content`, centered, or along its leading edge when `inset` is above 0.
static UIView *filled(UIView *content, UIColor *fill, CGFloat corner, CGFloat height, CGFloat inset) {
    UIView *box = [UIView new];
    box.backgroundColor = fill;
    box.layer.cornerRadius = corner;
    box.layer.cornerCurve = kCACornerCurveContinuous;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:content];
    pin(box, height);
    [content.centerYAnchor constraintEqualToAnchor:box.centerYAnchor].active = YES;
    if (inset > 0) {
        [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:inset].active = YES;
        [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-inset].active = YES;
    } else {
        [content.centerXAnchor constraintEqualToAnchor:box.centerXAnchor].active = YES;
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:box.leadingAnchor constant:2].active = YES;
    }
    return box;
}

// The made-up cover: a dusk over the bay, coral into plum, with a lantern low in it.
static UIImage *coverImage(void) {
    static UIImage *image;
    if (image) return image;
    CGFloat side = 104;
    image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        NSArray *colors = @[(id)[UIColor colorWithRed:0.94 green:0.54 blue:0.36 alpha:1].CGColor,
                            (id)[UIColor colorWithRed:0.42 green:0.17 blue:0.44 alpha:1].CGColor];
        CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
        CGContextDrawLinearGradient(context.CGContext, gradient, CGPointZero, CGPointMake(side, side), 0);
        CGGradientRelease(gradient);
        CGColorSpaceRelease(space);
        [[UIColor colorWithRed:1 green:0.86 blue:0.55 alpha:0.9] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(side * 0.38, side * 0.5, side * 0.24, side * 0.28)] fill];
        [[UIColor colorWithWhite:0 alpha:0.25] setFill];
        UIRectFill(CGRectMake(0, side * 0.82, side, side * 0.18));
    }];
    return image;
}

static UIView *cover(CGFloat side) {
    UIImageView *view = [[UIImageView alloc] initWithImage:coverImage()];
    view.layer.cornerRadius = side / 6;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.clipsToBounds = YES;
    [view.widthAnchor constraintEqualToConstant:side].active = YES;
    pin(view, side);
    return view;
}

// The widget's ProgressBar: SwiftUI's linear bar tinted white, held a little further on at each step.
static UIView *progressBar(CGFloat share) {
    UIView *track = [UIView new];
    track.backgroundColor = dim(0.22);
    track.layer.cornerRadius = 2;
    pin(track, 4);
    UIView *fill = [UIView new];
    fill.backgroundColor = UIColor.whiteColor;
    fill.layer.cornerRadius = 2;
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    [track addSubview:fill];
    [NSLayoutConstraint activateConstraints:@[
        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        [fill.widthAnchor constraintEqualToAnchor:track.widthAnchor multiplier:share],
    ]];
    return track;
}

#pragma mark - the card's views

// What the page's settings ask of the card.
typedef struct {
    NSInteger view, textSize, withoutLyrics, colors;
    BOOL centered, translation, artwork, progress;
} Look;

static UIColor *accentOf(Look look) {
    switch (look.colors) {
        case SGLiveActivityColorsArtwork: return sampleAccent();
        case SGLiveActivityColorsPlain: return UIColor.whiteColor;
        default: return green();
    }
}

static UIFont *lineFont(Look look) {
    CGFloat size = look.textSize == SGLiveActivityTextSmall ? kHeadline : look.textSize == SGLiveActivityTextLarge ? kTitle2 : kTitle3;
    return font(size, UIFontWeightBold);
}

static UIView *lyricsView(Look look, NSInteger step) {
    NSTextAlignment edge = look.centered ? NSTextAlignmentCenter : NSTextAlignmentNatural;
    if (step < kLineCount) {
        Line line = kLines[step];
        UILabel *sung = label(line.line, lineFont(look), UIColor.whiteColor, 2, edge);
        sung.adjustsFontSizeToFitWidth = YES;
        sung.minimumScaleFactor = 0.7;
        NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:sung];
        if (look.translation) [views addObject:label(line.translation, font(kSubheadline, UIFontWeightMedium), dim(0.7), 2, edge)];
        [views addObject:label(line.next, font(kSubheadline, UIFontWeightSemibold), dim(0.6), 1, edge)];
        return stack(views, UILayoutConstraintAxisVertical, 4);
    }
    // A track with no lyrics: under Note, the track at its own size over a line saying so; under Track, the
    // track in the lines' size.
    if (look.withoutLyrics == SGLiveActivityWithoutLyricsNote) {
        UIStackView *note = stack(@[label(kQuietTitle, font(kHeadline, UIFontWeightSemibold), UIColor.whiteColor, 1, edge),
                                    label(kArtist, font(kSubheadline, UIFontWeightMedium), dim(0.6), 1, edge),
                                    label(@"No synced lyrics for this song", font(kCaption, UIFontWeightMedium), dim(0.6), 1, edge)],
                                  UILayoutConstraintAxisVertical, 2);
        [note setCustomSpacing:6 afterView:note.arrangedSubviews[1]];
        return note;
    }
    return stack(@[label(kQuietTitle, lineFont(look), UIColor.whiteColor, 1, edge),
                   label(kArtist, font(kSubheadline, UIFontWeightMedium), dim(0.6), 1, edge)],
                 UILayoutConstraintAxisVertical, 2);
}

static NSAttributedString *trackLine(NSString *title, NSString *artist, CGFloat size) {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:title
        attributes:@{NSFontAttributeName: font(size, UIFontWeightSemibold), NSForegroundColorAttributeName: UIColor.whiteColor}];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:artist]
        attributes:@{NSFontAttributeName: font(size, UIFontWeightRegular), NSForegroundColorAttributeName: dim(0.6)}]];
    return text;
}

static UIView *queueView(void) {
    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObject:label(@"Up next", font(kCaption, UIFontWeightSemibold), dim(0.6), 1, NSTextAlignmentNatural)];
    for (NSInteger i = 0; i < 3; i++) {
        UILabel *row = label(nil, nil, nil, 1, NSTextAlignmentNatural);
        row.attributedText = trackLine(kQueue[i][0], kQueue[i][1], kSubheadline);
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:28].active = YES;
        [views addObject:row];
    }
    return stack(views, UILayoutConstraintAxisVertical, 4);
}

static UIView *chip(NSString *name, NSString *text, BOOL lit, Look look) {
    UIColor *color = lit ? accentOf(look) : UIColor.whiteColor;
    UIStackView *content = stack(@[symbol(name, kHeadline, UIFontWeightSemibold, color),
                                   label(text, font(kCaption2, UIFontWeightMedium), color, 1, NSTextAlignmentCenter)],
                                 UILayoutConstraintAxisVertical, 3);
    content.alignment = UIStackViewAlignmentCenter;
    return filled(content, lit ? [accentOf(look) colorWithAlphaComponent:0.22] : idle(), 12, 56, 0);
}

static UIStackView *chipRow(NSArray<UIView *> *chips, CGFloat spacing) {
    UIStackView *row = stack(chips, UILayoutConstraintAxisHorizontal, spacing);
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

static UIView *panelView(Look look, NSInteger tab) {
    NSArray<NSString *> *symbols = @[@"slider.horizontal.3", @"list.bullet", @"moon.zzz"];
    NSArray<NSString *> *titles = @[@"Controls", @"Queue", @"Timer"];
    NSMutableArray<UIView *> *tabs = [NSMutableArray array];
    for (NSInteger i = 0; i < TabCount; i++) {
        BOOL on = i == tab;
        UIColor *color = on ? accentOf(look) : dim(0.7);
        NSMutableArray<UIView *> *parts = [NSMutableArray arrayWithObject:symbol(symbols[i], kCaption, UIFontWeightSemibold, color)];
        if (on) [parts addObject:label(titles[i], font(kCaption, UIFontWeightSemibold), color, 1, NSTextAlignmentCenter)];
        UIView *capsule = filled(stack(parts, UILayoutConstraintAxisHorizontal, 4), on ? [accentOf(look) colorWithAlphaComponent:0.22] : idle(), 16, 32, 0);
        [tabs addObject:capsule];
    }
    UIView *page;
    switch (tab) {
        case TabControls: {
            UILabel *track = label(nil, nil, nil, 1, NSTextAlignmentNatural);
            track.attributedText = trackLine(kTitle, kArtist, kSubheadline);
            page = stack(@[track, chipRow(@[chip(@"backward.fill", @"Previous", NO, look), chip(@"pause.fill", @"Pause", NO, look),
                                             chip(@"forward.fill", @"Next", NO, look), chip(@"shuffle", @"Shuffle", YES, look),
                                             chip(@"repeat", @"Repeat", NO, look)], 10)],
                         UILayoutConstraintAxisVertical, 8);
            break;
        }
        case TabQueue: {
            NSMutableArray<UIView *> *rows = [NSMutableArray array];
            for (NSInteger i = 0; i < 3; i++) {
                UILabel *title = label(kQueue[i][0], font(kFootnote, UIFontWeightSemibold), UIColor.whiteColor, 1, NSTextAlignmentNatural);
                UILabel *artist = label(kQueue[i][1], font(kFootnote, UIFontWeightRegular), dim(0.6), 1, NSTextAlignmentNatural);
                [title setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 1 forAxis:UILayoutConstraintAxisHorizontal];
                [artist setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
                UIStackView *line = stack(@[symbol(@"play.fill", kCaption, UIFontWeightRegular, accentOf(look)), title, artist], UILayoutConstraintAxisHorizontal, 10);
                [rows addObject:filled(line, idle(), 10, 28, 10)];
            }
            page = stack(rows, UILayoutConstraintAxisVertical, 4);
            break;
        }
        default:
            page = chipRow(@[chip(@"moon", @"15m", NO, look), chip(@"moon", @"30m", NO, look), chip(@"moon", @"1h", NO, look),
                             chip(@"music.note", @"Track", NO, look), chip(@"square.stack", @"Album", NO, look)], 8);
    }
    UIStackView *tabRow = chipRow(tabs, 6);
    return stack(@[tabRow, page], UILayoutConstraintAxisVertical, 6);
}

// FamilyView: the cover beside what the view shows, the bar under both; the control menu without the cover.
static UIView *card(Look look, NSInteger step) {
    BOOL panel = look.view == SGLiveActivityPanel;
    UIView *content = look.view == SGLiveActivityLyrics ? lyricsView(look, step) : panel ? panelView(look, step) : queueView();
    NSMutableArray<UIView *> *top = [NSMutableArray array];
    if (look.artwork && !panel) [top addObject:cover(52)];
    [top addObject:content];
    UIStackView *row = stack(top, UILayoutConstraintAxisHorizontal, 12);
    row.alignment = UIStackViewAlignmentCenter;
    NSMutableArray<UIView *> *rows = [NSMutableArray arrayWithObject:row];
    if (look.progress) [rows addObject:progressBar(0.3 + 0.06 * step)];
    UIStackView *family = stack(rows, UILayoutConstraintAxisVertical, panel ? 6 : 10);
    family.layoutMarginsRelativeArrangement = YES;
    family.directionalLayoutMargins = panel ? NSDirectionalEdgeInsetsMake(8, 12, 8, 12) : NSDirectionalEdgeInsetsMake(12, 16, 12, 16);

    // The card's background: the cover's color, or under Plain the system's material.
    UIView *background;
    if (look.colors == SGLiveActivityColorsPlain) {
        background = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    } else {
        background = [UIView new];
        background.backgroundColor = sampleTint();
    }
    background.layer.cornerRadius = 22;
    background.layer.cornerCurve = kCACornerCurveContinuous;
    background.clipsToBounds = YES;
    family.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *holder = [background isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)background).contentView : background;
    [holder addSubview:family];
    [NSLayoutConstraint activateConstraints:@[
        [family.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],
        [family.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
        [family.topAnchor constraintEqualToAnchor:holder.topAnchor],
    ]];
    // Fitted at its width, the card's own height is the stack's; past the clip the stack runs on under it.
    NSLayoutConstraint *bottom = [family.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor];
    bottom.priority = UILayoutPriorityDefaultHigh;
    bottom.active = YES;
    return background;
}

static NSString *stepName(NSInteger view, NSInteger step) {
    switch (view) {
        case SGLiveActivityLyrics:
            return step < kLineCount ? [NSString stringWithFormat:@"Lyrics, line %ld of %ld", (long)step + 1, (long)kLineCount]
                                     : @"Lyrics, a track with no synced lyrics";
        case SGLiveActivityPanel:
            return [@"Control menu, " stringByAppendingString:@[@"Controls tab", @"Queue tab", @"Timer tab"][step]];
        default:
            return @"Queue, the tracks up next";
    }
}

#pragma mark - the preview

@implementation SGLiveActivityPreview {
    UIView *_slice;
    CAGradientLayer *_wallpaper;
    UILabel *_date, *_clock;
    UIView *_card;
    NSTimer *_timer;
    NSInteger _view, _step;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _slice = [UIView new];
    _slice.layer.cornerRadius = kCorner;
    _slice.layer.cornerCurve = kCACornerCurveContinuous;
    _slice.clipsToBounds = YES;
    _slice.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self addSubview:_slice];
    // A dusk wallpaper, for the Plain card's material to have something to blur.
    _wallpaper = [CAGradientLayer layer];
    _wallpaper.colors = @[(id)[UIColor colorWithRed:0.16 green:0.29 blue:0.48 alpha:1].CGColor,
                          (id)[UIColor colorWithRed:0.34 green:0.22 blue:0.52 alpha:1].CGColor,
                          (id)[UIColor colorWithRed:0.09 green:0.06 blue:0.17 alpha:1].CGColor];
    _wallpaper.locations = @[@0, @0.45, @1];
    [_slice.layer addSublayer:_wallpaper];
    _date = label(nil, font(17, UIFontWeightSemibold), dim(0.85), 1, NSTextAlignmentCenter);
    UIFontDescriptor *rounded = [[UIFont systemFontOfSize:72 weight:UIFontWeightSemibold].fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    _clock = label(nil, [UIFont fontWithDescriptor:rounded size:72], dim(0.9), 1, NSTextAlignmentCenter);
    [_slice addSubview:_date];
    [_slice addSubview:_clock];

    _view = -1;
    [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(advance)]];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Preview of the Live Activity on the lock screen";
    [self reload];
    return self;
}

- (CGFloat)sliceHeight {
    return kDateTop + ceil(_date.font.lineHeight) + ceil(_clock.font.lineHeight) + kCardGap + kClip + kSliceBottom;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    return kTop + [self sliceHeight] + kBottom;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inset = self.layoutMargins.left, width = self.bounds.size.width - inset - self.layoutMargins.right;
    _slice.frame = CGRectMake(inset, kTop, width, [self sliceHeight]);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wallpaper.frame = _slice.bounds;
    [CATransaction commit];
    _date.frame = CGRectMake(0, kDateTop, width, ceil(_date.font.lineHeight));
    _clock.frame = CGRectMake(0, CGRectGetMaxY(_date.frame), width, ceil(_clock.font.lineHeight));
    [self placeCard:_card];
}

- (void)placeCard:(UIView *)card {
    CGFloat width = _slice.bounds.size.width - 2 * kCardInset;
    if (!card || width <= 0) return;
    CGSize fits = [card systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                      withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    card.frame = CGRectMake(kCardInset, CGRectGetMaxY(_clock.frame) + kCardGap, width, MIN(kClip, ceil(fits.height)));
}

- (Look)look {
    NSInteger colors = SGInt(SGKeyLiveActivityColors, SGLiveActivityColorsSpotify);
    return (Look){
        .view = _view,
        .textSize = SGInt(SGKeyLiveActivityTextSize, SGLiveActivityTextMedium),
        .withoutLyrics = SGInt(SGKeyLiveActivityWithoutLyrics, SGLiveActivityWithoutLyricsNote),
        .colors = colors,
        .centered = SGInt(SGKeyLiveActivityAlignment, SGLiveActivityAlignCenter) == SGLiveActivityAlignCenter,
        .translation = SGFlag(SGKeyLiveActivityTranslation, NO),
        .artwork = SGEnabled(SGKeyLiveActivityArtwork),
        .progress = SGEnabled(SGKeyLiveActivityProgressBar),
    };
}

- (void)reload {
    NSInteger view = SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics);
    if (view < SGLiveActivityLyrics || view > SGLiveActivityPanel) view = SGLiveActivityLyrics;
    if (view != _view) {
        _view = view;
        _step = 0;
    }
    [self show];
}

- (void)advance {
    _step = (_step + 1) % stepsIn(_view);
    [self show];
}

// Builds the step's card and crossfades it over the one showing; the clock is read again with it.
- (void)show {
    NSDate *now = [NSDate date];
    NSLocale *locale = NSLocale.currentLocale;
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEEdMMMM" options:0 locale:locale];
    _date.text = [formatter stringFromDate:now];
    // The lock screen's clock leaves AM and PM out.
    NSString *format = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:locale];
    formatter.dateFormat = [[format stringByReplacingOccurrencesOfString:@"a" withString:@""]
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    _clock.text = [formatter stringFromDate:now];

    UIView *old = _card;
    _card = card([self look], _step);
    [self placeCard:_card];
    NSInteger steps = stepsIn(_view);
    self.accessibilityValue = stepName(_view, _step);
    self.accessibilityTraits = steps > 1 ? UIAccessibilityTraitButton : UIAccessibilityTraitNone;
    self.accessibilityHint = steps > 1 ? @"Shows the next step" : nil;
    if (!old || !self.window) {
        [old removeFromSuperview];
        [_slice addSubview:_card];
        return;
    }
    [UIView transitionWithView:_slice duration:kFade
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{
        [old removeFromSuperview];
        [self->_slice addSubview:self->_card];
    } completion:nil];
}

- (BOOL)accessibilityActivate {
    if (stepsIn(_view) < 2) return NO;
    [self advance];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil);
    return YES;
}

- (void)setRunning:(BOOL)running {
    _running = running;
    [_timer invalidate];
    _timer = nil;
    if (!running) return;
    [self show];
    __weak SGLiveActivityPreview *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:kStep repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
}

// Under Reduce Motion it waits for a tap; off screen or with Spotify behind another app, it waits.
- (void)tick {
    if (!self.window || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    if (UIAccessibilityIsReduceMotionEnabled() || stepsIn(_view) < 2) return;
    [self advance];
}

- (void)dealloc {
    [_timer invalidate];
}

@end
