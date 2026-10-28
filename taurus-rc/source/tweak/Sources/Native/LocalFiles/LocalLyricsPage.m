// The lyrics page for a local file in the native look (LocalLyrics.h): the title and the artist, then
// the lines on black, the one being sung white and a little larger, the rest gray, scrolled to keep it
// in the middle. Read four times a second from the player's state, which is plenty for lines; the clock
// stops when the page goes. A new track while it is open brings its lines, or says it has none.
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/Player/PlayerState.h"
#import "LocalLyrics.h"

static const NSTimeInterval kTick = 0.25;
static const CGFloat kSide = 24;
// The line being sung grows this much; the rest are dimmed to gray, #808080 on black, 5.3:1.
static const CGFloat kCurrentScale = 1.06, kOtherAlpha = 0.5;

@interface SGLocalLyricsViewer : UIViewController
@end

@implementation SGLocalLyricsViewer {
    UIButton *_close;
    UILabel *_title, *_artist, *_status;
    UIScrollView *_scroll;
    UIStackView *_stack;
    NSTimer *_timer;
    NSString *_uri;
    NSArray<SGKaraokeLine *> *_lines;
    NSArray<UILabel *> *_labels;
    BOOL _timed;
    NSInteger _current;
}

static char kCloseGlassKey;

static UILabel *label(UIFontTextStyle style, UIFontWeight weight, CGFloat size, UIColor *color) {
    UILabel *label = [UILabel new];
    label.font = [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = color;
    label.numberOfLines = 0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _current = -1;
    return self;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *view = self.view;
    view.backgroundColor = UIColor.blackColor;

    _close = [UIButton buttonWithType:UIButtonTypeSystem];
    [_close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold]]
            forState:UIControlStateNormal];
    _close.tintColor = UIColor.whiteColor;
    _close.accessibilityLabel = @"Close";
    _close.translatesAutoresizingMaskIntoConstraints = NO;
    [_close addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];

    _title = label(UIFontTextStyleTitle2, UIFontWeightBold, 22, UIColor.whiteColor);
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    _artist = label(UIFontTextStyleBody, UIFontWeightRegular, 17, [UIColor colorWithWhite:1 alpha:kOtherAlpha]);

    _scroll = [UIScrollView new];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 20;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    _status = label(UIFontTextStyleBody, UIFontWeightRegular, 17, [UIColor colorWithWhite:1 alpha:kOtherAlpha]);
    _status.textAlignment = NSTextAlignmentCenter;

    for (UIView *sub in @[_scroll, _title, _artist, _status, _close]) [view addSubview:sub];
    UILayoutGuide *safe = view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_close.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [_close.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_close.widthAnchor constraintEqualToConstant:44],
        [_close.heightAnchor constraintEqualToConstant:44],
        [_title.topAnchor constraintEqualToAnchor:_close.bottomAnchor constant:16],
        [_title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:kSide],
        [_title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-kSide],
        [_artist.topAnchor constraintEqualToAnchor:_title.bottomAnchor constant:2],
        [_artist.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
        [_artist.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
        [_scroll.topAnchor constraintEqualToAnchor:_artist.bottomAnchor constant:16],
        [_scroll.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:kSide],
        [_stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-kSide],
        [_status.centerYAnchor constraintEqualToAnchor:_scroll.centerYAnchor],
        [_status.leadingAnchor constraintEqualToAnchor:_title.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:_title.trailingAnchor],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIVisualEffectView *glass = SGGlassFor(_close, &kCloseGlassKey);
    glass.frame = _close.bounds;
    SGShapeGlass(glass, _close.bounds.size.height / 2, YES);
    // Room above the first line and below the last for either to be scrolled to the middle.
    CGFloat half = _scroll.bounds.size.height / 2;
    _scroll.contentInset = UIEdgeInsetsMake(24, 0, half, 0);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self tick];
    [_timer invalidate];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:kTick repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    // Common modes, so the line still moves on while the lines are dragged.
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - the lines

- (void)load:(SPTPlayerState *)state uri:(NSString *)uri {
    _uri = uri;
    _lines = nil;
    _current = -1;
    for (UIView *line in _stack.arrangedSubviews) [line removeFromSuperview];
    _labels = @[];
    NSString *title = state.track.trackTitle, *artist = state.track.artistName;
    _title.text = title;
    _artist.text = artist;
    _status.text = @"Loading lyrics…";
    _status.hidden = NO;
    // The file is read off the main thread the first time; after that it is kept.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        SGLyricsResult *lyrics = SGImportedLRCFor(uri, title, artist);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([uri isEqualToString:self->_uri]) [self show:lyrics];
        });
    });
}

- (void)show:(SGLyricsResult *)lyrics {
    _lines = lyrics.karaokeLines;
    _timed = SGKaraokeLinesTiming(_lines) != SGKaraokeTimingNone;
    if (!_lines.count) {
        _status.text = SGImportedLRCLinkedTo(_uri) ? @"This LRC file has no lines to show." : @"No imported lyrics for this track.";
        return;
    }
    _status.hidden = YES;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    for (SGKaraokeLine *line in _lines) {
        UILabel *text = label(UIFontTextStyleTitle2, UIFontWeightBold, 24, UIColor.whiteColor);
        text.text = SGKaraokeLineText(line);
        text.textAlignment = NSTextAlignmentCenter;
        text.alpha = _timed ? kOtherAlpha : 1;
        [_stack addArrangedSubview:text];
        [labels addObject:text];
    }
    _labels = labels;
    [_stack layoutIfNeeded];
    [_scroll setContentOffset:CGPointMake(0, -_scroll.contentInset.top) animated:NO];
}

// Fades and scales only, a short ease out; with Reduce Motion the line is not scaled and the list jumps.
- (void)light:(NSInteger)current {
    NSInteger previous = _current;
    _current = current;
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    void (^change)(void) = ^{
        for (NSInteger i = 0; i < (NSInteger)self->_labels.count; i++) {
            if (i != previous && i != current) continue;
            UILabel *text = self->_labels[(NSUInteger)i];
            BOOL lit = i == current;
            text.alpha = lit ? 1 : kOtherAlpha;
            text.transform = lit && !still ? CGAffineTransformMakeScale(kCurrentScale, kCurrentScale) : CGAffineTransformIdentity;
        }
    };
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:change completion:nil];
    // A finger on the lines has them; the page follows again once they come to rest.
    if (current < 0 || _scroll.isTracking || _scroll.isDecelerating) return;
    UILabel *text = _labels[(NSUInteger)current];
    CGFloat middle = [_scroll convertPoint:text.center fromView:_stack].y - _scroll.bounds.size.height / 2;
    CGFloat lowest = MAX(_scroll.contentSize.height + _scroll.contentInset.bottom - _scroll.bounds.size.height, -_scroll.contentInset.top);
    middle = MIN(MAX(middle, -_scroll.contentInset.top), lowest);
    [_scroll setContentOffset:CGPointMake(0, middle) animated:!still];
}

- (void)tick {
    SPTPlayerState *state = SGPlayerState();
    NSString *uri = SGURIString(state.track.URI);
    if (uri && ![uri isEqualToString:_uri]) [self load:state uri:uri];
    if (!_timed || !_labels.count) return;
    NSInteger ms = (NSInteger)((state.isPaused ? state.positionAsOfTimestamp : state.position) * 1000) - SGKaraokeDelayMs();
    NSInteger current = SGKaraokeLeadLine(_lines, ms);
    if (current != _current && current < (NSInteger)_labels.count) [self light:current];
}

@end

UIViewController *SGLocalLyricsPage(void) {
    return [SGLocalLyricsViewer new];
}
