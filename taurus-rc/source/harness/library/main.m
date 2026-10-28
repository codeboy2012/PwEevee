// A mock of Spotify's Your Library page under its own class names and accessibility identifiers, built from
// trees/clean/library/03.txt (recorded 2026-09-16), so Redesigned/Library/LibraryHeader.x can be laid out and
// looked at on the Mac. It plays issue #21: the header's model arriving after the page has laid out, the buttons
// it shows placed by Spotify's stack on a pass of its own. `first` on the launch line stops there, `back` then
// gives the page the pass it gets on the way back from a playlist, `steady` builds the header with the model
// already in it. `nocreate` leaves Create out of the model, `norecents` Recents (the account the tree is of).
#import <UIKit/UIKit.h>
#import <os/log.h>

#define HLog(fmt, ...) os_log(OS_LOG_DEFAULT, "[harness] %{public}s", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String)

static const CGFloat kHeaderHeight = 159.33;

#pragma mark - Spotify's classes, by name

@interface _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView : UIView @end
@implementation _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView @end

@interface _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer : UIView @end
@implementation _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer @end

@interface _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView : UIView @end
@implementation _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView @end

@interface _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView : UIView @end
@implementation _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView @end

@interface _TtC22YourLibrary_FolderImpl10FolderView : UIView @end
@implementation _TtC22YourLibrary_FolderImpl10FolderView @end

@interface _TtC21YourLibrary_CommonKit25YourLibraryCollectionView : UICollectionView @end
@implementation _TtC21YourLibrary_CommonKit25YourLibraryCollectionView @end

// Encore's button: a 48pt box with its 24pt glyph in the middle.
@interface MockEncoreButton : UIControl @end
@implementation MockEncoreButton @end

// LegacyUI_ECMCoreKit.AutoLayoutStackView: the arranged views in a plain container view, chained by constraints
// the stack rebuilds when one of them shows or hides. The real one watches its views' hidden and folds the
// changes into one update (its ivars: observationsDictionary, needsCoalescedLayoutUpdate); the mock folds them
// into the next turn of the main queue, so a page laying out in the turn the header's model lands in still
// sees each button where it stood before. A hidden view leaves the chain and sits at the container's origin,
// where 03.txt has the hidden Recents.
@interface _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView : UIView
@property (nonatomic, readonly) UIView *containerView;
@property (nonatomic, copy) NSArray<UIView *> *arrangedSubviews;
@end

@implementation _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView {
    NSArray<NSLayoutConstraint *> *_layoutConstraints;
    BOOL _needsCoalescedLayoutUpdate;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _containerView = [[UIView alloc] initWithFrame:self.bounds];
    _containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_containerView];
    return self;
}

- (void)setArrangedSubviews:(NSArray<UIView *> *)views {
    _arrangedSubviews = [views copy];
    for (UIView *view in views) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [_containerView addSubview:view];
        [view addObserver:self forKeyPath:@"hidden" options:0 context:NULL];
    }
    [self rebuild];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (_needsCoalescedLayoutUpdate) return;
    _needsCoalescedLayoutUpdate = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_needsCoalescedLayoutUpdate = NO;
        [self rebuild];
        HLog(@"stack rebuilt its constraints");
    });
}

- (void)rebuild {
    if (_layoutConstraints) [NSLayoutConstraint deactivateConstraints:_layoutConstraints];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray array];
    UIView *previous = nil;
    for (UIView *view in _arrangedSubviews) {
        if (view.hidden) {
            [constraints addObject:[view.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor]];
            [constraints addObject:[view.topAnchor constraintEqualToAnchor:_containerView.topAnchor]];
            continue;
        }
        [constraints addObject:[view.centerYAnchor constraintEqualToAnchor:_containerView.centerYAnchor]];
        [constraints addObject:[view.leadingAnchor constraintEqualToAnchor:previous ? previous.trailingAnchor : _containerView.leadingAnchor]];
        previous = view;
    }
    if (previous) [constraints addObject:[previous.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor]];
    _layoutConstraints = constraints;
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)dealloc {
    for (UIView *view in _arrangedSubviews) [view removeObserver:self forKeyPath:@"hidden"];
}
@end

// The header lays its own children out by frame: the scrim over all of it, the control row off the safe area,
// the chips under the row.
@interface _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView : UIView
@property (nonatomic, strong) UIView *gradient, *row, *filters;
@end

@implementation _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat top = self.window ? self.window.safeAreaInsets.top : 62;
    self.gradient.frame = CGRectMake(0, 0, width, kHeaderHeight);
    self.row.frame = CGRectMake(0, top, width, 48);
    self.filters.frame = CGRectMake(0, top + 48, width, 49.33);
}
@end

// The page: its content the size of it, the header over it at its full height and the list inset by that height,
// all three stated again on every pass the way Spotify's does.
@interface _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView : UIView
@property (nonatomic, strong) UIView *content, *header;
@property (nonatomic, strong) UICollectionView *list;
@end

@implementation _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView
- (void)layoutSubviews {
    [super layoutSubviews];
    self.content.frame = self.bounds;
    self.list.frame = self.content.bounds;
    self.header.frame = CGRectMake(0, 0, self.bounds.size.width, kHeaderHeight);
    UIEdgeInsets inset = self.list.contentInset;
    inset.top = kHeaderHeight;
    self.list.contentInset = inset;
}
@end

#pragma mark - building the page

static UIView *box(UIView *parent, Class cls, CGRect frame, NSString *identifier) {
    UIView *view = [[cls alloc] initWithFrame:frame];
    view.accessibilityIdentifier = identifier;
    if (parent) [parent addSubview:view];
    return view;
}

static void pinSize(UIView *view, CGFloat width, CGFloat height) {
    [view.widthAnchor constraintEqualToConstant:width].active = YES;
    [view.heightAnchor constraintEqualToConstant:height].active = YES;
}

static UIView *button(NSString *identifier, NSString *symbol) {
    UIView *control = box(nil, MockEncoreButton.class, CGRectMake(0, 0, 48, 48), identifier);
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightRegular];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:config]];
    glyph.frame = CGRectMake(12, 12, 24, 24);
    glyph.contentMode = UIViewContentModeCenter;
    glyph.tintColor = UIColor.whiteColor;
    [control addSubview:glyph];
    pinSize(control, 48, 48);
    return control;
}

static UIImage *avatar(void) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 64)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [[UIColor colorWithRed:0.55 green:0.85 blue:0.55 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 64, 64));
        [[UIColor colorWithRed:0.25 green:0.22 blue:0.2 alpha:1] setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(18, 10, 28, 32)] fill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(6, 40, 52, 40)] fill];
    }];
}

static UIView *face(BOOL adaptive) {
    Class containerClass = adaptive ? _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer.class : UIView.class;
    UIView *container = box(nil, containerClass, CGRectMake(0, 0, 48, 48), nil);
    UIView *drawer = box(container, MockEncoreButton.class, CGRectMake(0, 0, 48, 48), @"Components.UI.SideDrawerButton");
    UIImageView *image = [[UIImageView alloc] initWithImage:avatar()];
    image.frame = CGRectMake(8, 8, 32, 32);
    image.layer.cornerRadius = 16;
    image.clipsToBounds = YES;
    [drawer addSubview:image];
    pinSize(container, 48, 48);
    return container;
}

static UIView *spotifyTitle(void) {
    UIView *encore = box(nil, UIView.class, CGRectZero, @"YourLibraryHeader.title");
    UILabel *label = [UILabel new];
    label.text = @"Your Library";
    label.font = [UIFont boldSystemFontOfSize:21];
    label.textColor = UIColor.whiteColor;
    label.accessibilityIdentifier = @"YourLibraryHeader.title-internal";
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [encore addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:encore.leadingAnchor],
        [label.trailingAnchor constraintEqualToAnchor:encore.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:encore.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:encore.bottomAnchor],
    ]];
    return encore;
}

static UIView *chips(UIView *filters) {
    CGFloat x = 16;
    for (NSString *word in @[@"Playlists", @"Podcasts", @"Albums", @"Artists"]) {
        UILabel *chip = [UILabel new];
        chip.text = word;
        chip.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        chip.textColor = UIColor.whiteColor;
        chip.textAlignment = NSTextAlignmentCenter;
        chip.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];
        chip.layer.cornerRadius = 14.7;
        chip.clipsToBounds = YES;
        CGFloat width = ceil([word sizeWithAttributes:@{NSFontAttributeName: chip.font}].width) + 32;
        chip.frame = CGRectMake(x, 8, width, 29.33);
        [filters addSubview:chip];
        x += width + 8;
    }
    return filters;
}

@interface SGRHarnessCard : UICollectionViewCell
@property (nonatomic, strong) UIView *cover;
@property (nonatomic, strong) UILabel *title;
@end

@implementation SGRHarnessCard
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    CGFloat side = frame.size.width;
    _cover = [[UIView alloc] initWithFrame:CGRectMake(0, 0, side, side)];
    _cover.layer.cornerRadius = 6;
    [self.contentView addSubview:_cover];
    _title = [[UILabel alloc] initWithFrame:CGRectMake(0, side + 6, side, 18)];
    _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    [self.contentView addSubview:_title];
    return self;
}
@end

@interface SGRHarnessDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate, UICollectionViewDataSource>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page;
@property (nonatomic, strong) NSDictionary<NSString *, UIView *> *controls;
@end

@implementation SGRHarnessDelegate

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 12;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    SGRHarnessCard *card = [collectionView dequeueReusableCellWithReuseIdentifier:@"card" forIndexPath:indexPath];
    NSArray<NSString *> *names = @[@"Great songs", @"70s Hits", @"80s Hits", @"Early 2000's", @"Lofi Girl", @"hololive",
                                   @"Skepta", @"Real Music", @"Aitch", @"New Episodes", @"Tame Impala", @"Chill Mix"];
    card.title.text = names[indexPath.item % names.count];
    CGFloat hue = fmod(indexPath.item * 0.137, 1);
    card.cover.backgroundColor = [UIColor colorWithHue:hue saturation:0.55 brightness:0.6 alpha:1];
    return card;
}

- (UIView *)control:(NSString *)name {
    return self.controls[name];
}

// What the header's model says: which buttons it shows. Setting them is all Spotify's header does on a render;
// the stack places what changed on its own, later.
- (void)render:(NSArray<NSString *> *)shown {
    for (NSString *name in @[@"recents", @"search", @"plus"]) {
        BOOL hidden = ![shown containsObject:name];
        UIView *control = self.controls[name];
        if (control.hidden != hidden) control.hidden = hidden;
    }
    HLog(@"model: %@ shown", [shown componentsJoinedByString:@", "]);
}

- (void)report:(NSString *)moment {
    UIView *header = self.page.header;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *name in @[@"recents", @"search", @"plus", @"face"]) {
        UIView *control = self.controls[name];
        if (control.hidden) {
            [parts addObject:[NSString stringWithFormat:@"%@ hidden", name]];
            continue;
        }
        CGRect frame = [control.superview convertRect:control.frame toView:header];
        [parts addObject:[NSString stringWithFormat:@"%@ %.0f-%.0f", name, CGRectGetMinX(frame), CGRectGetMaxX(frame)]];
    }
    UILabel *title = nil;
    for (UIView *sub in header.subviews) {
        if ([sub isMemberOfClass:UILabel.class]) title = (UILabel *)sub;
    }
    CGFloat textRight = title ? CGRectGetMinX(title.frame) + MIN(title.bounds.size.width, [title.text sizeWithAttributes:@{NSFontAttributeName: title.font}].width) : 0;
    UIView *filters = [header valueForKey:@"filters"];
    NSCAssert(title.text.length && title.alpha > 0 && title.bounds.size.width > 0, @"Library title must be visible");
    for (NSString *name in @[@"recents", @"search", @"plus", @"face"]) {
        UIView *control = self.controls[name];
        if (control.hidden) continue;
        CGRect frame = [control.superview convertRect:control.frame toView:header];
        NSCAssert(!CGRectIntersectsRect(title.frame, frame), @"Library title must not cover %@", name);
    }
    NSCAssert(filters.alpha == 1 && fabs(self.page.list.contentInset.top - kHeaderHeight) < 0.5,
              @"Library filters and list inset must stay intact");
    HLog(@"%@: %@; title text %.0f-%.0f, header %.0fpt, list inset %.0f, chips %@", moment,
         [parts componentsJoinedByString:@", "], CGRectGetMinX(title.frame), textRight,
         header.bounds.size.height, self.page.list.contentInset.top,
         !filters ? @"missing" : (filters.alpha < 0.5 ? @"HIDDEN" : [NSString stringWithFormat:@"%.0fpt at y=%.0f",
                                  filters.bounds.size.height, filters.frame.origin.y]));
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:session.role];
    configuration.delegateClass = self.class;
    return configuration;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    BOOL steady = [args containsObject:@"steady"];
    BOOL back = [args containsObject:@"back"];
    NSArray<NSString *> *model = @[@"recents", @"search", @"plus"];
    if ([args containsObject:@"nocreate"]) model = @[@"recents", @"search"];
    if ([args containsObject:@"norecents"]) model = @[@"search", @"plus"];

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.backgroundColor = UIColor.blackColor;
    UIViewController *root = [UIViewController new];

    _TtC28YourLibrary_YourLibraryXImpl15YourLibraryView *page = [[_TtC28YourLibrary_YourLibraryXImpl15YourLibraryView alloc] initWithFrame:self.window.bounds];
    page.backgroundColor = UIColor.blackColor;
    self.page = page;

    page.content = box(page, _TtC28YourLibrary_YourLibraryXImpl22YourLibraryContentView.class, page.bounds, nil);
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    CGFloat side = floor((page.bounds.size.width - 32 - 2 * 14) / 3);
    layout.itemSize = CGSizeMake(side, side + 44);
    layout.minimumInteritemSpacing = 14;
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(40, 16, 0, 16);
    _TtC21YourLibrary_CommonKit25YourLibraryCollectionView *list = [[_TtC21YourLibrary_CommonKit25YourLibraryCollectionView alloc] initWithFrame:page.bounds collectionViewLayout:layout];
    list.accessibilityIdentifier = @"YourLibraryContent.collectionView";
    list.backgroundColor = UIColor.blackColor;
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [list registerClass:SGRHarnessCard.class forCellWithReuseIdentifier:@"card"];
    list.dataSource = self;
    [page.content addSubview:list];
    page.list = list;

    _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView *header = (id)box(page, _TtC28YourLibrary_YourLibraryXImpl21YourLibraryHeaderView.class, CGRectMake(0, 0, page.bounds.size.width, kHeaderHeight), nil);
    page.header = header;
    header.gradient = box(header, _TtCO22Reprise_LiquidGlassKit11LiquidGlass12GradientView.class, header.bounds, @"LiquidGlass.GradientView");
    header.gradient.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    header.row = box(header, UIView.class, CGRectMake(0, 62, header.bounds.size.width, 48), nil);
    UIView *inner = box(header.row, UIView.class, header.row.bounds, nil);
    inner.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView *stack = (id)box(inner, _TtC19LegacyUI_ECMCoreKit19AutoLayoutStackView.class, CGRectMake(8, 0, inner.bounds.size.width - 16, 48), nil);
    stack.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.filters = chips(box(header, _TtC21YourLibrary_CommonKit35YourLibraryHeaderContentFiltersView.class, CGRectMake(0, 110, header.bounds.size.width, 49.33), nil));

    UIView *avatarBox = face(![args containsObject:@"plain-avatar"]);
    UIView *title = spotifyTitle();
    UIView *spacer = [UIView new];
    [spacer.heightAnchor constraintEqualToConstant:0].active = YES;
    [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    UIView *recents = button(@"YourLibraryHeader.recents", @"clock.arrow.circlepath");
    UIView *search = button(@"YourLibraryHeader.search", @"magnifyingglass");
    UIView *plus = button(@"YourLibraryHeader.plus", @"plus");
    self.controls = @{@"recents": recents, @"search": search, @"plus": plus, @"face": avatarBox};

    // Built with what the header knows before its model arrives -- Search alone -- unless `steady`.
    NSArray<NSString *> *initial = steady ? model : @[@"search"];
    for (NSString *name in @[@"recents", @"search", @"plus"]) self.controls[name].hidden = ![initial containsObject:name];
    stack.arrangedSubviews = @[avatarBox, title, spacer, recents, search, plus];

    root.view = page;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self report:@"page up"];
        if (steady) return;
        // The model lands, and the page lays out in the same turn -- Spotify's page states its list and header
        // again from the same update -- before the stack's own pass has placed what the model showed.
        [self render:model];
        [page setNeedsLayout];
        [page layoutIfNeeded];
        [self report:@"page pass in the model's turn"];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self report:@"first look"];
    });
    if (back) {
        // Opening a playlist and coming back: the page lays out again, nothing else changes.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [page setNeedsLayout];
            [page layoutIfNeeded];
            [self report:@"back from a playlist"];
        });
    }
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRHarnessDelegate.class));
    }
}
