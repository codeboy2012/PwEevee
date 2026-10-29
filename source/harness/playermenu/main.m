// The redesign's player menu (Redesigned/Player/PlayerMenu.x) run for real over a mock of Spotify's context
// menu sheet: a player with its ⋯ (id=Context menu), and the sheet presented from it the way Spotify nests
// it -- a container presented as a sheet, holding a navigation controller, holding a page, holding
// ContextMenu_InternalImpl.ContextMenuViewController under its own class name -- whose table rows are
// ListRow-like controls carrying the item's number as their accessibility identifier, as 9.1.78's do
// (trees/continuous/1.txt:648). The table has no didSelectRowAtIndexPath:, like Spotify's binder; a row
// fires through its control. Share (9) pushes a page onto the sheet and Lyrics (28) turns itself on in place.
// Speed and pitch, Canvas Lyrics, and Background Style are harness stubs.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/PlayerMenuHarness.app
//     xcrun simctl launch --console-pty <udid> com.vojta.playermenuharness [scenario] [loading|slow|stuck]
//
// Scenarios, each starting with a tap on the ⋯ at 1 s: hold (nothing more), more (opens More at 3 s),
// speed (opens Speed and pitch at 3 s), follow (opens it, then turns pitch following speed on at 4.5 s and
// off at 9 s: the panel folds its pitch slider away and back, the card with it), tile (Add to playlist at 3 s), share (Share at 3 s: Spotify's page
// is pushed and its sheet shown), lyrics (More, then Lyrics: the row reads On), canvas (toggle Canvas Lyrics),
// background (choose Visualiser), outside (a tap beside the
// card at 3 s), pending (Add to playlist tapped before Spotify's rows are in: fired once they are with
// `loading`, Spotify's sheet shown 4 s after the tap with `stuck`). `loading` hands the sheet its rows 1.5 s
// after it is up, `slow` 7 s after, later than the card once waited; `stuck` never does. The card opens on
// the rows of the run before, which the harness keeps in its defaults like the phone does.
#import <UIKit/UIKit.h>
#import "Redesigned/Player/Player.h"

#pragma mark - what the hooks call and the harness does not build

static double sg_speed = 1;
static float sg_pitch;
void SGPlayFeedback(NSInteger feedback) {}
void SGPrepareFeedback(NSInteger feedback) {}
double SGPlayerSpeed(void) { return sg_speed; }
BOOL SGPlayerSpeedAllowed(void) { return YES; }
void SGSetPlayerSpeed(double speed) { sg_speed = speed; NSLog(@"[harness] speed %.2f", speed); }
float SGPlayerPitch(void) { return sg_pitch; }
void SGSetPlayerPitch(float semitones) { sg_pitch = semitones; NSLog(@"[harness] pitch %.0f", semitones); }
BOOL SGPlayerPitchAvailable(void) { return YES; }
static BOOL sg_follows;
BOOL SGPlayerPitchFollowsSpeed(void) { return sg_follows; }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) {
    sg_follows = follows;
    if (follows) sg_pitch = 0;
    NSLog(@"[harness] pitch follows speed %d", follows);
}
UIColor *SGRAccentColor(void) { return nil; }
static BOOL sg_canvasLyrics;
BOOL SGLockScreenCanvasLyricsEnabled(void) { return sg_canvasLyrics; }
void SGLockScreenCanvasLyricsSetEnabled(BOOL enabled) {
    sg_canvasLyrics = enabled;
    NSLog(@"[harness] Canvas Lyrics %@", enabled ? @"on" : @"off");
}
static SGRPlayerBackgroundKind sg_background = SGRPlayerBackgroundStill;
SGRPlayerBackgroundKind SGRPlayerBackground(void) { return sg_background; }
NSArray<NSString *> *SGRPlayerBackgroundNames(void) { return @[@"Still", @"Colors", @"Fluid", @"Animated", @"Visualiser"]; }
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind) {
    sg_background = kind;
    NSLog(@"[harness] Background Style %@", SGRPlayerBackgroundNames()[(NSUInteger)kind]);
}

static BOOL argument(NSString *name) {
    return [NSProcessInfo.processInfo.arguments containsObject:name];
}

static void after(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

#pragma mark - Spotify's rows

// Spotify's order on the phone (trees/continuous/1.txt) for the numbers known, then rows whose numbers the
// menu does not know, standing in for the rest of the sheet below the fold.
static NSMutableArray<NSMutableArray<NSString *> *> *spotifyRows(void) {
    static NSMutableArray *rows;
    if (!rows) rows = [@[
        [@[@"9", @"square.and.arrow.up", @"Share"] mutableCopy],
        [@[@"28", @"captions.bubble", @"Lyrics • Off"] mutableCopy],
        [@[@"19", @"plus.circle", @"Add to playlist"] mutableCopy],
        [@[@"59", @"xmark.circle", @"Exclude track from your taste profile"] mutableCopy],
        [@[@"27", @"minus.circle", @"Remove from this playlist"] mutableCopy],
        [@[@"11", @"text.append", @"Add to Queue"] mutableCopy],
        [@[@"34", @"list.bullet", @"Go to Queue"] mutableCopy],
        [@[@"3", @"dot.radiowaves.left.and.right", @"Go to song radio"] mutableCopy],
        [@[@"4", @"opticaldisc", @"Go to album"] mutableCopy],
        [@[@"5", @"person", @"Go to artist"] mutableCopy],
        [@[@"41", @"info.circle", @"View song credits"] mutableCopy],
        [@[@"12", @"barcode", @"Show Spotify Code"] mutableCopy],
        [@[@"70", @"point.3.connected.trianglepath.dotted", @"Explore Song DNA"] mutableCopy],
        [@[@"66", @"ticket", @"Go to artist's concerts"] mutableCopy],
        [@[@"22", @"moon", @"Sleep timer"] mutableCopy],
    ] mutableCopy];
    return rows;
}

// Encore's ListRow: a control, the item's number as its identifier, a 24pt glyph and a label in it.
@interface SGHarnessListRow : UIControl
@property (nonatomic, strong) UIImageView *glyph;
@property (nonatomic, strong) UILabel *label;
@end

@implementation SGHarnessListRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _glyph = [[UIImageView alloc] initWithFrame:CGRectMake(12, 16, 24, 24)];
    _glyph.tintColor = [UIColor colorWithWhite:0.7 alpha:1];
    _label = [[UILabel alloc] initWithFrame:CGRectMake(48, 0, 300, 56)];
    _label.textColor = UIColor.whiteColor;
    [self addSubview:_glyph];
    [self addSubview:_label];
    return self;
}
@end

@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic) BOOL loaded;
@end

@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
    self.loaded = !argument(@"loading") && !argument(@"slow") && !argument(@"stuck");
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.rowHeight = 56;
    self.table.dataSource = self;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.table];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ((argument(@"loading") || argument(@"slow")) && !self.loaded) after(argument(@"slow") ? 7 : 1.5, ^{
        self.loaded = YES;
        [self.table reloadData];
        NSLog(@"[harness] the sheet has its rows");
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.loaded ? spotifyRows().count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    cell.backgroundColor = UIColor.clearColor;
    SGHarnessListRow *row = (SGHarnessListRow *)[cell.contentView viewWithTag:7];
    if (!row) {
        row = [[SGHarnessListRow alloc] initWithFrame:cell.contentView.bounds];
        row.tag = 7;
        row.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [row addTarget:self action:@selector(rowFired:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:row];
    }
    NSArray<NSString *> *data = spotifyRows()[indexPath.row];
    row.accessibilityIdentifier = data[0];
    row.glyph.image = [UIImage systemImageNamed:data[1]];
    row.label.text = data[2];
    return cell;
}

- (void)rowFired:(SGHarnessListRow *)row {
    NSString *identifier = row.accessibilityIdentifier;
    NSLog(@"[harness] Spotify's row %@ \"%@\" fired", identifier, row.label.text);
    if ([identifier isEqualToString:@"9"]) {
        UIViewController *page = [UIViewController new];
        page.view.backgroundColor = [UIColor colorWithRed:0.1 green:0.2 blue:0.15 alpha:1];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, 300, 30)];
        label.text = @"Spotify's share page";
        label.textColor = UIColor.whiteColor;
        [page.view addSubview:label];
        [self.navigationController pushViewController:page animated:YES];
    } else if ([identifier isEqualToString:@"28"]) {
        for (NSMutableArray *data in spotifyRows()) {
            if ([data[0] isEqualToString:@"28"]) data[2] = @"Lyrics • On";
        }
        [self.table reloadData];
        [self.view setNeedsLayout];
    } else {
        UIViewController *top = self;
        while (top.parentViewController) top = top.parentViewController;
        [top dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

#pragma mark - Spotify's sheet presentation

static void collect(UIView *view, NSString *className, NSMutableArray<UIView *> *out) {
    if ([NSStringFromClass(view.class) isEqualToString:className]) [out addObject:view];
    for (UIView *child in view.subviews) collect(child, className, out);
}


// NavigationUI_SheetImpl.SheetPresentationController: a sheet with a dimming view of Spotify's own, black
// at 0.7 fading in with the transition, added as the presentation begins.
@interface _TtC22NavigationUI_SheetImpl27SheetPresentationController : UISheetPresentationController
@end

@implementation _TtC22NavigationUI_SheetImpl27SheetPresentationController
- (void)presentationTransitionWillBegin {
    [super presentationTransitionWillBegin];
    UIView *dimming = [[UIView alloc] initWithFrame:self.containerView.bounds];
    dimming.accessibilityIdentifier = @"Components.UI.SheetPresentation.Dimming";
    dimming.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    dimming.alpha = 0;
    dimming.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView insertSubview:dimming atIndex:0];
    [self.presentedViewController.transitionCoordinator animateAlongsideTransition:^(id context) { dimming.alpha = 1; } completion:nil];
}
- (void)containerViewDidLayoutSubviews {
    [super containerViewDidLayoutSubviews];
}
@end

@interface SGHarnessSheetDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end

@implementation SGHarnessSheetDelegate
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
    _TtC22NavigationUI_SheetImpl27SheetPresentationController *sheet = [[_TtC22NavigationUI_SheetImpl27SheetPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
    sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
    return sheet;
}
@end

// Every frame for a second from the tap on the ⋯: does anything of Spotify's sheet or its dimming show?
@interface SGHarnessFlashWatch : NSObject
@property (nonatomic, weak) UIWindow *window;
@property (nonatomic) NSInteger frames, shown;
@property (nonatomic) CFTimeInterval start;
@end

@implementation SGHarnessFlashWatch
static BOOL onScreen(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v = view; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
        if (v.layer.mask && v.layer.mask.frame.size.width <= 1) return NO;
    }
    return YES;
}
- (void)tick:(CADisplayLink *)link {
    if (!self.start) self.start = link.timestamp;
    UIPresentationController *presentation = self.window.rootViewController.presentedViewController.presentationController;
    // Spotify's dimming, and the system's UIDimmingViews wherever they are: in the sheet's container, and over
    // the view the sheet came up over.
    BOOL dim = NO;
    for (UIView *v in presentation.containerView.subviews) {
        if ([v.accessibilityIdentifier isEqualToString:@"Components.UI.SheetPresentation.Dimming"] && onScreen(v)) dim = YES;
    }
    NSMutableArray<UIView *> *system = [NSMutableArray array];
    collect(self.window, @"UIDimmingView", system);
    for (UIView *v in system) {
        CGFloat white = 0, alpha = 0;
        [v.backgroundColor getWhite:&white alpha:&alpha];
        if (onScreen(v) && alpha > 0.01) dim = YES;
    }
    BOOL sheet = presentation && onScreen(presentation.presentedView);
    self.frames++;
    if (sheet || dim) {
        self.shown++;
        NSLog(@"[harness] frame %ld: %@%@ shows", (long)self.frames, sheet ? @"the sheet " : @"", dim ? @"the dimming" : @"");
    }
    if (link.timestamp - self.start > 1) {
        [link invalidate];
        NSLog(@"[harness] flash check: %ld of the first %ld frames after the tap showed Spotify's sheet or its dimming", (long)self.shown, (long)self.frames);
    }
}
@end

#pragma mark - the player

@interface NowPlayingHarnessViewController : UIViewController
@property (nonatomic, strong) UIButton *more;
@end

@implementation NowPlayingHarnessViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.32 green:0.08 blue:0.1 alpha:1];
    UIView *cover = [[UIView alloc] initWithFrame:CGRectMake(24, 160, 354, 354)];
    cover.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:1];
    cover.layer.cornerRadius = 12;
    [self.view addSubview:cover];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(24, 560, 354, 34)];
    title.text = @"máme toho moc";
    title.font = [UIFont boldSystemFontOfSize:26];
    title.textColor = UIColor.whiteColor;
    [self.view addSubview:title];

    void SGRPlayerMenuWatchMoreButton(UIView *button);
    self.more = [UIButton buttonWithType:UIButtonTypeSystem];
    self.more.frame = CGRectMake(402 - 12 - 48, 62, 48, 48);
    self.more.accessibilityIdentifier = @"Context menu";
    [self.more setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
    self.more.tintColor = UIColor.whiteColor;
    self.more.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    self.more.layer.cornerRadius = 24;
    [self.view addSubview:self.more];
    // The menu watches the button first, as PlayerHeader.x hands it over before the button is ever tapped.
    SGRPlayerMenuWatchMoreButton(self.more);
    [self.more addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
}

// The nesting Spotify's sheet has: a container presented as a sheet > navigation > page > menu.
- (void)openMenu {
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *menu = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    UIViewController *page = [UIViewController new];
    [page addChildViewController:menu];
    menu.view.frame = page.view.bounds;
    menu.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [page.view addSubview:menu.view];
    [menu didMoveToParentViewController:page];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:page];
    navigation.navigationBarHidden = YES;
    UIViewController *container = [UIViewController new];
    [container addChildViewController:navigation];
    navigation.view.frame = container.view.bounds;
    navigation.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container.view addSubview:navigation.view];
    [navigation didMoveToParentViewController:container];
    static SGHarnessSheetDelegate *delegate;
    if (!delegate) delegate = [SGHarnessSheetDelegate new];
    container.modalPresentationStyle = UIModalPresentationCustom;
    container.transitioningDelegate = delegate;
    [self presentViewController:container animated:YES completion:nil];
}

@end

#pragma mark - reading what is on screen


static UIView *find(UIView *root, NSString *className, NSString *label) {
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    collect(root, className, found);
    for (UIView *view in found) {
        if (!label || [view.accessibilityLabel isEqualToString:label]) return view;
    }
    return nil;
}

static void tap(UIWindow *window, NSString *label) {
    UIControl *control = (UIControl *)(find(window, @"SGRPlayerMenuTile", label) ?: find(window, @"SGRPlayerMenuRow", label));
    NSLog(@"[harness] tapping \"%@\" on the card: %@", label, control ? @"found" : @"NOT FOUND");
    [control sendActionsForControlEvents:UIControlEventTouchUpInside];
}

static void report(UIWindow *window, NSString *when) {
    UIView *card = find(window, @"SGRPlayerMenuCard", nil);
    UIViewController *presented = window.rootViewController.presentedViewController;
    UIView *sheet = presented.presentationController.presentedView;
    NSMutableArray<UIView *> *controls = [NSMutableArray array];
    collect(card, @"SGRPlayerMenuTile", controls);
    collect(card, @"SGRPlayerMenuRow", controls);
    [controls sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGRect ra = [a convertRect:a.bounds toView:card], rb = [b convertRect:b.bounds toView:card];
        if (fabs(ra.origin.y - rb.origin.y) > 1) return ra.origin.y < rb.origin.y ? NSOrderedAscending : NSOrderedDescending;
        return ra.origin.x < rb.origin.x ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (UIView *control in controls) {
        CGRect frame = [control convertRect:control.bounds toView:card];
        BOOL visible = frame.size.height > 1 && control.window && CGRectIntersectsRect(frame, card.bounds);
        UIView *clip = control.superview;
        while (clip && clip != card) {
            if (clip.clipsToBounds && clip.bounds.size.height < 1) visible = NO;
            clip = clip.superview;
        }
        if (!visible) continue;
        [lines addObject:[NSString stringWithFormat:@"%@%@%@ @%.0f h%.0f", [control.class isEqual:NSClassFromString(@"SGRPlayerMenuTile")] ? @"[tile] " : @"",
                          control.accessibilityLabel, control.accessibilityValue ? [NSString stringWithFormat:@" (%@)", control.accessibilityValue] : @"",
                          frame.origin.y, frame.size.height]];
    }
    NSLog(@"[harness] %@: card %@ alpha %.2f in %@; Spotify's sheet %@ %@ touches %d; presented %@\n  %@", when,
          card ? NSStringFromCGRect(card.frame) : @"none", card.alpha, card.superview ? NSStringFromClass(card.superview.class) : @"nothing",
          sheet ? NSStringFromClass(sheet.class) : @"none",
          !sheet.hidden && sheet.alpha > 0.01 && !(sheet.layer.mask && sheet.layer.mask.frame.size.width <= 1) ? @"SHOWN" : @"out of sight", sheet.userInteractionEnabled,
          presented ? @"yes" : @"no", [lines componentsJoinedByString:@"\n  "]);
}

static void dump(UIView *view, int depth, NSMutableString *out) {
    if (!view || depth > 4) return;
    [out appendFormat:@"\n%*s%@ %@ a=%.2f%@%@", depth * 2, "", NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.alpha,
     view.hidden ? @" hidden" : @"", view.layer.mask ? [NSString stringWithFormat:@" mask=%@", NSStringFromCGRect(view.layer.mask.frame)] : @""];
    for (UIView *child in view.subviews) dump(child, depth + 1, out);
}

#pragma mark - the run

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@end

@implementation SGHarnessApp
@end

@interface SGHarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessScene

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    NowPlayingHarnessViewController *player = [NowPlayingHarnessViewController new];
    self.window.rootViewController = player;
    [self.window makeKeyAndVisible];
    UIWindow *window = self.window;

    after(1, ^{
        static SGHarnessFlashWatch *watch;
        watch = [SGHarnessFlashWatch new];
        watch.window = window;
        [[CADisplayLink displayLinkWithTarget:watch selector:@selector(tick:)] addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        [player.more sendActionsForControlEvents:UIControlEventTouchUpInside];
    });
    after(2.2, ^{ report(window, @"open"); });
    if (argument(@"dimmings")) for (NSNumber *at in @[@1.05, @1.5, @4]) after(at.doubleValue, ^{
        NSMutableArray<UIView *> *found = [NSMutableArray array];
        collect(window, @"UIDimmingView", found);
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (UIView *v in found) [lines addObject:[NSString stringWithFormat:@"in %@ (%@) hidden %d alpha %.2f", NSStringFromClass(v.superview.class),
                                                   v.superview == window.rootViewController.presentedViewController.presentationController.containerView ? @"the sheet's container" : @"elsewhere", v.hidden, v.alpha]];
        NSLog(@"[harness] %.2f s: UIDimmingViews: %@", at.doubleValue, [lines componentsJoinedByString:@"; "]);
    });
    if (argument(@"dump")) after(2.4, ^{
        NSMutableString *out = [NSMutableString string];
        dump(window.rootViewController.presentedViewController.presentationController.containerView, 0, out);
        NSLog(@"[harness] container:%@", out);
    });
    // The card stays while Spotify's rows are late or never come; only a row tapped meanwhile gives it up.
    if (argument(@"stuck")) after(6, ^{ report(window, @"no rows at 6 s"); });
    if (argument(@"slow")) {
        after(6, ^{ report(window, @"no rows yet at 6 s"); });
        after(9, ^{ report(window, @"after the slow rows"); });
    }
    if (argument(@"more")) {
        after(3, ^{ tap(window, @"More"); });
        after(4, ^{ report(window, @"More opened"); });
    } else if (argument(@"speed")) {
        after(3, ^{ tap(window, @"Speed and pitch"); });
        after(4, ^{ report(window, @"Speed and pitch opened"); });
    } else if (argument(@"follow")) {
        after(3, ^{ tap(window, @"Speed and pitch"); });
        after(4, ^{ report(window, @"Speed and pitch opened"); });
        for (NSNumber *at in @[@4.5, @9]) after(at.doubleValue, ^{
            // The card's: Speed and pitch's block is in Spotify's sheet as well, out of sight under it.
            UISwitch *toggle = (UISwitch *)find(find(window, @"SGRPlayerMenuCard", nil), @"UISwitch", @"Pitch follows speed");
            NSLog(@"[harness] switching pitch follows speed %@: %@", toggle.on ? @"off" : @"on", toggle ? @"found" : @"NOT FOUND");
            toggle.on = !toggle.on;
            [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        });
        after(5.5, ^{ report(window, @"pitch follows speed"); });
        after(10, ^{ report(window, @"pitch no longer follows"); });
    } else if (argument(@"tile")) {
        after(3, ^{ tap(window, @"Add to playlist"); });
        after(4, ^{ report(window, @"after Add to playlist"); });
    } else if (argument(@"share")) {
        after(3, ^{ tap(window, @"Share"); });
        after(4, ^{ report(window, @"after Share"); });
    } else if (argument(@"lyrics")) {
        after(3, ^{ tap(window, @"More"); });
        after(4, ^{ tap(window, @"Lyrics"); });
        after(5, ^{ report(window, @"after Lyrics"); });
    } else if (argument(@"canvas")) {
        after(3, ^{ tap(window, @"Canvas Lyrics"); });
        after(4, ^{ report(window, @"after Canvas Lyrics"); });
    } else if (argument(@"background")) {
        after(3, ^{ tap(window, @"Background Style"); });
        after(4, ^{ tap(window, @"Visualiser"); });
        after(5, ^{ report(window, @"after Background Style"); });
    } else if (argument(@"pending")) {
        // With `loading`: Add to playlist tapped on the last menu's rows before Spotify's are in.
        after(2.1, ^{ tap(window, @"Add to playlist"); });
        after(4, ^{ report(window, @"after the held tap"); });
        after(7, ^{ report(window, @"5 s after the held tap"); });
    } else if (argument(@"outside")) {
        after(3, ^{
            NSMutableArray<UIView *> *found = [NSMutableArray array];
            UIView *card = find(window, @"SGRPlayerMenuCard", nil);
            for (UIView *view in card.superview.subviews) {
                if ([view isKindOfClass:UIControl.class] && view != card) [found addObject:view];
            }
            NSLog(@"[harness] tapping beside the card: %lu catchers", (unsigned long)found.count);
            [(UIControl *)found.lastObject sendActionsForControlEvents:UIControlEventTouchDown];
        });
        after(4, ^{ report(window, @"after a tap outside"); });
    }
}

@end

// Before every %ctor, so the redesign's gate reads on.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class));
    }
}
