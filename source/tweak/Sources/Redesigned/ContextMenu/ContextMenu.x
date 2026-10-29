// The redesign's ⋯ as the system menu (ContextMenu.h says what and why).
//
// The player's ⋯ is a pull-down button of the mod's (SGRMenuFront) and its sheet lives in a window of the
// mod's (SGRSheetWindow); everything below about opening the menu over a sheet already up is a page's ⋯.
//
// The sheet is ContextMenu_InternalImpl.ContextMenuViewController, presented on its own or as the root of
// ContextMenuNativeNavigationController; its rows are a table sized to its content (Shared/Player/
// SpeedPitchMenu.x and harness/menu say more), each a ContextMenuTableViewCell whose only ivar is the
// containedView Spotify draws the row in (nm on 9.1.78). So a row is read off the cell it fills -- its words
// from its labels, its glyph from its image view or else drawn off the small view at its leading edge -- and
// picked through the table's own delegate, as a tap on it would be.
//
// What UIKit does was checked in the simulator against harness/system-menu/ (iOS 27): a presentation's
// container exists from the presented controller's viewWillAppear: on, not when presentViewController: returns,
// so that is where the sheet is hidden; a menu asked for while the sheet's presentation is still under way
// comes up only some of the time (most of the time on a first showing, not on a second right after a first),
// and the presentation takes 0.2 s and more to end even unanimated, so the menu is asked for a turn after
// viewWillAppear: and, when that does not come, again from the presentation's completion, the sheet going up
// unanimated for that to be soon; -performPrimaryAction brings the menu up over the hidden sheet and calls
// willDisplayMenuForConfiguration: before it returns; a pick runs the action's handler before
// willEndForConfiguration:, so by the end of the menu's dismissal it is known whether there was one; a deferred
// element in a submenu is asked for its items when that submenu opens, not with the menu, so More's rows are
// not kept from one menu to the next: by the time More is opened the sheet has nearly always read them.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "ContextMenu.h"

// After a pick of Spotify's, how long its sheet has to start going, or to push a page of its own (which shows
// it at once), before it is taken to have stayed up for some other reason and is shown.
static const NSTimeInterval kSettle = 1;
// How often the sheet is asked for its rows until it has them.
static const NSTimeInterval kRowsPoll = 0.1;
// How long a pick made before the sheet has its live rows waits for them before the sheet is shown.
static const NSTimeInterval kQuickWait = 4;
// How long the player's menu waits for Spotify's sheet once its ⋯ action has been run for it.
static const NSTimeInterval kRequestWindow = 3;

static NSString *const kSheetClass = @"_TtC24ContextMenu_InternalImpl25ContextMenuViewController";
static NSString *const kTopMenu = @"com.pweevee.systemmenu.top";
static NSString *const kQuickMenu = @"com.pweevee.systemmenu.quick";
static NSString *const kMoreMenu = @"com.pweevee.systemmenu.more";
// The last complete set of Spotify's rows for each kind of sheet, for More to show before the live ones come.
static NSString *const kStoredRowsKey = @"spotifyglass.redesign.player.menuRows";

static char kAnchorKey, kFrontKey, kPlacedKey, kSessionKey;

@class SGRMenuSession;
// The session whose pick is being fired on its hidden sheet, for a page the row pushes inside the sheet.
static __weak SGRMenuSession *sg_firing;
// The player's menu asking Spotify for its sheet, and when: the next presentation is that sheet.
static __weak SGRMenuSession *sg_requesting;
static CFTimeInterval sg_requestedAt;
// The session whose sheet is in the mod's own window, and the presentation the mod is making itself.
static __weak SGRMenuSession *sg_hosted;
static BOOL sg_redirecting;

// The player's quick items: what the item says, its symbol, the title of Spotify's row it fires (compared
// without case) and that row's item number, the accessibility identifier of its Encore ListRow on 9.1.78. The
// number is matched first, so a sheet in another language still finds them; the title is the fallback.
static NSArray<NSArray<NSString *> *> *quickItems(void) {
    return @[@[@"Share", @"square.and.arrow.up", @"share", @"9"],
             @[@"Add to Playlist", @"text.badge.plus", @"add to playlist", @"19"],
             @[@"Add to Queue", @"text.line.last.and.arrowtriangle.forward", @"add to queue", @"11"]];
}

// Which quick items (their rows' titles) the last sheet of each kind had.
static NSMutableDictionary<NSString *, NSArray<NSString *> *> *sg_quickSeen;

#pragma mark - the sheet

// Spotify's ContextMenuViewController in what was presented: itself, the root of its navigation controller, or
// a child of a controller wrapped around either.
// Matched by class, not by name: NSStringFromClass gives a Swift class's readable name ("Module.Class") on
// iOS 27, never the mangled one kSheetClass holds.
static UIViewController *sheetIn(UIViewController *presented) {
    static Class sheetClass;
    if (!sheetClass) sheetClass = NSClassFromString(kSheetClass);
    if (!presented || !sheetClass) return nil;
    if ([presented isKindOfClass:sheetClass]) return presented;
    if ([presented isKindOfClass:UINavigationController.class]) {
        UIViewController *root = ((UINavigationController *)presented).viewControllers.firstObject;
        if ([root isKindOfClass:sheetClass]) return root;
    }
    for (UIViewController *child in presented.childViewControllers) {
        UIViewController *sheet = sheetIn(child);
        if (sheet) return sheet;
    }
    return nil;
}

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (!root || depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

static NSInteger rowCount(UITableView *table) {
    NSInteger rows = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) rows += [table numberOfRowsInSection:section];
    return rows;
}

static BOOL shows(UIView *view) {
    return !view.hidden && view.alpha > 0.01;
}

// The visible labels' words in reading order: the row's title first, a line under it second.
static NSArray<UILabel *> *labelsIn(UIView *root) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    SGForEachView(root, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] && shows(view) && ((UILabel *)view).text.length) [labels addObject:(UILabel *)view];
    });
    [labels sortUsingComparator:^NSComparisonResult(UILabel *a, UILabel *b) {
        CGRect ra = [a convertRect:a.bounds toView:root], rb = [b convertRect:b.bounds toView:root];
        if (fabs(CGRectGetMinY(ra) - CGRectGetMinY(rb)) > 4) return CGRectGetMinY(ra) < CGRectGetMinY(rb) ? NSOrderedAscending : NSOrderedDescending;
        return CGRectGetMinX(ra) < CGRectGetMinX(rb) ? NSOrderedAscending : NSOrderedDescending;
    }];
    return labels;
}

// The first accessibility identifier in the row, for the log.
static NSString *identifierIn(UIView *root) {
    __block NSString *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (!found && view.accessibilityIdentifier.length) found = view.accessibilityIdentifier;
    });
    return found;
}

// The row's glyph as a template, for the menu to draw in its own color: an image view's picture, else the
// small view at the row's leading edge drawn into one (Encore draws its icons into a view of its own,
// Redesigned/Playlist/PlaylistMenu.x).
static UIImage *glyphIn(UIView *root, NSString *title) {
    __block UIImageView *image = nil;
    __block UIView *drawn = nil;
    __block CGFloat drawnX = CGFLOAT_MAX;
    SGForEachView(root, ^(UIView *view) {
        if (view == root || !shows(view)) return;
        CGSize size = view.bounds.size;
        if (size.width < 12 || size.width > 40 || size.height < 12 || size.height > 40) return;
        if (!image && [view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) image = (UIImageView *)view;
        CGFloat x = [view convertRect:view.bounds toView:root].origin.x;
        if (![view isKindOfClass:UILabel.class] && !view.subviews.count && x < drawnX) {
            drawn = view;
            drawnX = x;
        }
    });
    // A cover (Encore's media image view, as Liked Songs' own) would draw as a solid square: a symbol in the
    // menu's color stands in for it.
    if (image && [image.superview.accessibilityIdentifier isEqualToString:@"Encore.ImageView"]) {
        NSString *name = @"music.note.list";
        if ([title containsString:@"Liked Songs"]) name = [title hasPrefix:@"Remove"] ? @"heart.fill" : @"heart";
        UIImageSymbolConfiguration *size = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
        return [UIImage systemImageNamed:name withConfiguration:size];
    }
    if (image) return [image.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (!drawn || drawnX > root.bounds.size.width / 3) return nil;
    UIImage *picture = [[[UIGraphicsImageRenderer alloc] initWithSize:drawn.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [drawn.layer renderInContext:context.CGContext];
    }];
    return [picture imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Spotify grays a row out (lyrics for a track no source has them for) rather than leaving it out.
static BOOL rowEnabled(UITableView *table, NSIndexPath *path, UITableViewCell *cell, UILabel *title) {
    if (!cell.userInteractionEnabled) return NO;
    id<UITableViewDelegate> delegate = table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:shouldHighlightRowAtIndexPath:)] && ![delegate tableView:table shouldHighlightRowAtIndexPath:path]) return NO;
    CGFloat alpha = 1;
    [title.textColor getRed:NULL green:NULL blue:NULL alpha:&alpha];
    return title.enabled && title.alpha * alpha >= 0.6;
}

// Fires a control as a tap on it would: its primary action's handlers if it has any, else its touch up inside
// ones (the mod's own watchers left out of the count), else its accessibility activation. What it did, for the log.
static NSString *fireControl(UIControl *control) {
    if (!control) return @"nothing to fire";
    __block UIControlEvents events = 0;
    if ([control respondsToSelector:@selector(enumerateEventHandlers:)]) {
        [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents handled, BOOL *stop) {
            // The mod's own watcher of the ⋯ (Shared/Player/SpeedPitchMenu.x) is not Spotify's action.
            if (!action && [NSStringFromClass([target class]) hasSuffix:@"TapWatcher"]) return;
            events |= handled;
        }];
    }
    if (events & UIControlEventPrimaryActionTriggered) {
        [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        return [NSString stringWithFormat:@"%@'s primary action", NSStringFromClass(control.class)];
    }
    if (events & UIControlEventTouchUpInside) {
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        return [NSString stringWithFormat:@"%@'s touch up inside", NSStringFromClass(control.class)];
    }
    BOOL done = [control accessibilityActivate];
    return [NSString stringWithFormat:@"%@'s accessibility activation (%@, events 0x%lx)", NSStringFromClass(control.class), done ? @"taken" : @"refused", (unsigned long)events];
}

// Picks the row as a tap would; a row that answers to no delegate is tapped through the first control in it.
// Only the cells on screen exist, so a row further down is scrolled to first (the table is hidden).
static void selectRow(UITableView *table, NSIndexPath *path) {
    id<UITableViewDelegate> delegate = table.delegate;
    if ([delegate respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)]) path = [delegate tableView:table willSelectRowAtIndexPath:path];
    if (!path) return;
    if ([delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
        [table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
        [delegate tableView:table didSelectRowAtIndexPath:path];
        return;
    }
    UITableViewCell *cell = [table cellForRowAtIndexPath:path];
    if (!cell && path.section < table.numberOfSections && path.row < [table numberOfRowsInSection:path.section]) {
        [table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        [table layoutIfNeeded];
        cell = [table cellForRowAtIndexPath:path];
    }
    __block UIControl *control = nil;
    SGForEachView(cell, ^(UIView *view) {
        if (!control && [view isKindOfClass:UIControl.class] && view.userInteractionEnabled) control = (UIControl *)view;
    });
    SGLog(@"system menu: the sheet's table has no didSelect, so %@ (row %ld%@)", fireControl(control), (long)path.row, cell ? @"" : @", no cell");
}

// The mod's own rows in the table's header or footer view: the view itself or its children, controls of the
// mod's (SG…) with a label. Spotify's own header (the track it is for) is not one.
static NSArray<UIControl *> *modRowsIn(UIView *slot) {
    if (!slot || slot.bounds.size.height < 1) return @[];
    NSMutableArray<UIControl *> *rows = [NSMutableArray array];
    for (UIView *view in [slot isKindOfClass:UIControl.class] ? @[slot] : slot.subviews) {
        if ([view isKindOfClass:UIControl.class] && shows(view) && view.accessibilityLabel.length
            && [NSStringFromClass(view.class) hasPrefix:@"SG"]) [rows addObject:(UIControl *)view];
    }
    return rows;
}

static NSString *controllersIn(UIViewController *presented);

static UIMenu *inlineGroup(NSArray<UIMenuElement *> *children) {
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:children];
}

#pragma mark - one menu

// One row of the sheet as read: a row of Spotify's table (`path`) or a control of the mod's (`control`).
@interface SGRSheetRow : NSObject
@property (nonatomic, strong) NSIndexPath *path;
@property (nonatomic, weak) UIControl *control;
@property (nonatomic, copy) NSString *title, *subtitle, *identifier;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL enabled;
// The quick item this row is, by its row title in quickItems(); nil for none.
@property (nonatomic, copy) NSString *quick;
@end
@implementation SGRSheetRow
@end

@class SGRMenuAnchor;

// One ⋯ tap: the sheet Spotify presented, the anchor the menu comes from, and what was picked.
//
// The player's ⋯ (`direct`) opens its menu itself, from a button of the mod's over Spotify's ⋯ (SGRMenuFront),
// before Spotify has done anything: Spotify's sheet is asked for (requestSheet, Spotify's ⋯ action run from
// code) once the menu is up, and presented in a window of the mod's own under the app's (adoptSheet), unseen,
// for its rows and to run them. A page's ⋯ is the other way round: Spotify's sheet comes first, from its tap,
// and the menu is opened over it, hidden (takeOver, open).
@interface SGRMenuSession : NSObject
@property (nonatomic) BOOL direct;
// Spotify's ⋯ (direct), whose action brings its sheet up, and the controller Spotify presented that sheet from.
@property (nonatomic, weak) UIControl *spotify;
@property (nonatomic, weak) UIViewController *presenter;
@property (nonatomic, weak) UIViewController *presented;
@property (nonatomic, weak) SGRMenuAnchor *anchor;
@property (nonatomic, copy) SGRMenuItems items;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic) BOOL displayed, revealed, ended, opened;
@property (nonatomic, copy) void (^pick)(void);
// When the ⋯ was touched (0 for a pinned ⋯, whose touch is the Kit's) and when the sheet was taken over, for
// the log of where the time to the menu goes.
@property (nonatomic) CFTimeInterval touchedAt, takenAt;
- (void)open;
- (void)tryEarly;
- (void)present;
- (void)shown;
- (void)reveal;
- (void)hide;
- (void)menuEnded;
- (UIView *)container;
- (void)requestSheet;
- (void)adoptSheet:(UIViewController *)presented from:(UIViewController *)presenter completion:(void (^)(void))completion;
- (void)rowPresented;
- (UIMenu *)menu;
@end

// An invisible button over the ⋯ that only hosts the menu. It takes touches only while the menu is up
// (UIKit will not present a menu from a view that takes none), so a tap on the ⋯ reaches the ⋯.
@interface SGRMenuAnchor : UIButton
@property (nonatomic, strong) SGRMenuSession *session;
@end

// The player's ⋯ as a pull-down button of the mod's own (HIG, Pull-down buttons): an invisible button over
// Spotify's ⋯ that takes its touches and opens the menu on touch down, as UIKit opens any button's menu, so the
// menu waits for nothing of Spotify's and Spotify's ⋯ action does not run on the tap. Its menu is made afresh
// as it opens, with a session of its own.
@interface SGRMenuFront : SGRMenuAnchor
@property (nonatomic, weak) UIControl *spotify;
@property (nonatomic, copy) SGRMenuItems items;
@property (nonatomic, copy) SGRMenuKind kind;
@end

@implementation SGRMenuAnchor

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willDisplayMenuForConfiguration:(UIContextMenuConfiguration *)configuration
                      animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willDisplayMenuForConfiguration:configuration animator:animator];
    [self.session shown];
}

- (void)contextMenuInteraction:(UIContextMenuInteraction *)interaction willEndForConfiguration:(UIContextMenuConfiguration *)configuration
                      animator:(id<UIContextMenuInteractionAnimating>)animator {
    [super contextMenuInteraction:interaction willEndForConfiguration:configuration animator:animator];
    SGRMenuSession *session = self.session;
    self.session = nil;
    self.userInteractionEnabled = [self isKindOfClass:SGRMenuFront.class];
    // At once, not at the end of the menu's dismissal: on the phone that end never came (the animator's
    // completion never ran), so every pick and close waited out a 3 s limit with the hidden sheet over the
    // player. The pick fires a turn later, which the sheet takes while the menu is still fading.
    [session menuEnded];
    // The player's ⋯ is pressed for as long as its menu is up (the touch that opened it was canceled at once,
    // as the menu came): its targets for the press (PlayerHeader.x's circle) are told now that it is let go.
    if ([self isKindOfClass:SGRMenuFront.class]) [self sendActionsForControlEvents:UIControlEventTouchUpOutside];
}

@end

@implementation SGRMenuFront

- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction configurationForMenuAtLocation:(CGPoint)location {
    SGRMenuSession *session = [SGRMenuSession new];
    session.direct = YES;
    session.opened = YES;
    session.touchedAt = session.takenAt = CACurrentMediaTime();
    session.anchor = self;
    session.spotify = self.spotify;
    session.items = self.items;
    session.kind = self.kind ? self.kind() : nil;
    self.session = session;
    self.menu = [session menu];
    return [super contextMenuInteraction:interaction configurationForMenuAtLocation:location];
}

// One line per touch down, so the phone log says the finger reached the mod's button and what it held then.
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    SGLog(@"system menu: touch down on the mod's ⋯ at %@ in the window (menu %@, %@)", NSStringFromCGRect([self convertRect:self.bounds toView:nil]),
          self.menu ? @"held" : @"none", self.enabled && self.userInteractionEnabled ? @"taking touches" : @"not taking touches");
}

// UIKit cancels the touch as the menu comes up, and the press holds until the menu ends (willEndForConfiguration:).
// A touch canceled with no menu up is a touch let go.
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesCancelled:touches withEvent:event];
    if (!self.session) [self sendActionsForControlEvents:UIControlEventTouchUpOutside];
}

@end


#pragma mark - the mod's window for Spotify's sheet

// The player's menu is a presentation of UIKit's own from the player, so while it is up nothing else can be
// presented there: Spotify's sheet, asked for once the menu is up, would be turned down (simulator, iOS 27). It is
// presented instead in a window of the mod's under the app's, where it lays out and gets its rows unseen. Shown,
// the window comes up over the app's until the sheet is gone. A touch that lands on nothing of the sheet's goes
// through it.
@interface SGRSheetWindow : UIWindow
@end
@implementation SGRSheetWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.viewIfLoaded ? nil : hit;
}
@end

static SGRSheetWindow *sg_host;

static SGRSheetWindow *hostWindow(UIWindowScene *scene) {
    if (!scene) return nil;
    if (sg_host.windowScene != scene) {
        sg_host = [[SGRSheetWindow alloc] initWithWindowScene:scene];
        UIViewController *root = [UIViewController new];
        root.view.backgroundColor = UIColor.clearColor;
        sg_host.rootViewController = root;
        sg_host.backgroundColor = UIColor.clearColor;
        sg_host.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    sg_host.windowLevel = UIWindowLevelNormal - 1;
    sg_host.hidden = NO;
    return sg_host;
}

// The mod's window over the app's while the sheet in it is shown, and back under once it is gone.
static void lowerWhenEmpty(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_host.windowLevel < UIWindowLevelNormal) return;
        if (sg_host.rootViewController.presentedViewController) {
            lowerWhenEmpty();
            return;
        }
        sg_host.windowLevel = UIWindowLevelNormal - 1;
    });
}

static void raiseHost(UIWindow *window) {
    if (!window || window != sg_host || sg_host.windowLevel >= UIWindowLevelNormal) return;
    sg_host.windowLevel = UIWindowLevelNormal + 1;
    lowerWhenEmpty();
}

@implementation SGRMenuSession {
    // The sheet's rows in its groups (the mod's header rows, each section, the mod's footer rows), nil until
    // the sheet has them; read once.
    NSArray<NSArray<SGRSheetRow *> *> *_groups;
    __weak UITableView *_table;
    // Run once the rows are read: More's items, a quick pick waiting for its row.
    NSMutableArray<dispatch_block_t> *_whenRead;
    // A quick pick is waiting for the rows, which keeps the poll going after the menu has gone.
    BOOL _waiting;
    // The quick row as the menu shows it, to know whether the rows changed it.
    NSString *_quickShown;
    NSTimer *_poll;
    CFTimeInterval _openedAt, _askedAt;
    // The menu is asked for while the sheet's presentation is still under way, which UIKit takes only some of
    // the time; if it does not come, it is asked for again once the sheet is up.
    BOOL _early, _wasEarly;
    // Direct: Spotify's sheet asked for, and when; it did not come; the menu closed with nothing for it to do,
    // so it goes as it comes; a row picked on it presented something of Spotify's.
    BOOL _requested, _failed, _dropOnArrival, _rowPresented;
    CFTimeInterval _requestedAt;
}

- (UIViewController *)sheet {
    return sheetIn(self.presented);
}

// The presentation's container, which the sheet is hidden in. Asked of the controller UIKit presented: a
// controller inside it (the sheet, taken over as it appeared inside one of Spotify's) would answer with a
// presentation controller of its own, made then, holding nothing.
- (UIView *)container {
    UIViewController *outer = self.presented;
    while (outer.parentViewController) outer = outer.parentViewController;
    return outer.presentationController.containerView;
}

- (void)open {
    if (self.opened) return;
    self.opened = YES;
    SGRMenuAnchor *anchor = self.anchor;
    if (!anchor.window || !self.presented.presentingViewController) {
        SGLog(@"system menu: the ⋯ left the screen before its menu could open, Spotify's sheet shown");
        [self reveal];
        return;
    }
    _openedAt = CACurrentMediaTime();
    // A turn later, so the menu never comes up in the same turn as the touch that opened Spotify's sheet.
    dispatch_async(dispatch_get_main_queue(), ^{ [self present]; });
}

// The first try, a turn after the sheet starts to appear, before its presentation is over: the wait for that is
// the most the mod adds between the touch and the menu (0.2 s and more in the simulator, even unanimated). UIKit
// brings a menu up then only some of the time, so a try that does not come is let go and open asks again once
// the sheet is up.
- (void)tryEarly {
    if (self.opened || self.displayed || self.ended || self.revealed) return;
    _early = _wasEarly = YES;
    [self present];
}

// The menu up from the anchor, at once, with what needs nothing of the sheet; Spotify's rows are read after it is
// asked for, so the time they take is not the menu's.
- (void)present {
    if (self.displayed || self.ended || self.revealed) return;
    if (!_whenRead) _whenRead = [NSMutableArray array];
    SGRMenuAnchor *anchor = self.anchor;
    if (!anchor.window || !self.presented.presentingViewController) {
        SGLog(@"system menu: the ⋯ left the screen before its menu could open, Spotify's sheet shown");
        [self reveal];
        return;
    }
    if (!_askedAt) _askedAt = CACurrentMediaTime();
    anchor.session = self;
    anchor.menu = [self menu];
    anchor.userInteractionEnabled = YES;
    SEL perform = NSSelectorFromString(@"performPrimaryAction");
    if ([anchor respondsToSelector:perform]) ((void (*)(id, SEL))objc_msgSend)(anchor, perform);
    if (!self.displayed) {
        UIContextMenuInteraction *interaction = anchor.contextMenuInteraction;
        for (id<UIInteraction> each in anchor.interactions) {
            if (!interaction && [(id)each isKindOfClass:UIContextMenuInteraction.class]) interaction = (UIContextMenuInteraction *)each;
        }
        SEL present = NSSelectorFromString(@"_presentMenuAtLocation:");
        if ([interaction respondsToSelector:present]) {
            CGPoint middle = CGPointMake(CGRectGetMidX(anchor.bounds), CGRectGetMidY(anchor.bounds));
            ((void (*)(id, SEL, CGPoint))objc_msgSend)(interaction, present, middle);
        }
    }
    // Both ways answer before they return; one more turn is given for an OS that answers a moment later.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.displayed && !self.ended && self->_early) {
            self->_early = NO;
            anchor.userInteractionEnabled = NO;
            anchor.session = nil;
            static int logged;
            if (logged++ < 3) SGLog(@"system menu: the menu asked for while Spotify's sheet came up did not come, asked again once it is up");
            return;
        }
        self->_early = NO;
        if (!self.displayed && !self.ended) {
            SGLog(@"system menu: the menu did not come up, Spotify's sheet shown");
            anchor.userInteractionEnabled = NO;
            anchor.session = nil;
            [self reveal];
            return;
        }
        if (![self readRows]) [self pollRows];
    });
}

// Where the time from the ⋯ touch to the menu on screen went, in seconds after the touch (after the takeover for
// a pinned ⋯).
- (void)shown {
    if (self.displayed) return;
    self.displayed = YES;
    if (!_whenRead) _whenRead = [NSMutableArray array];
    if (self.direct) {
        SGLog(@"system menu: the player's menu is up %.3f s after the touch down on its ⋯ (Spotify's sheet not asked for yet)",
              CACurrentMediaTime() - self.touchedAt);
        // A turn later, so nothing of Spotify's stands in the way of the menu's first frames.
        dispatch_async(dispatch_get_main_queue(), ^{ [self requestSheet]; });
        return;
    }
    CFTimeInterval now = CACurrentMediaTime(), from = self.touchedAt ?: self.takenAt;
    SGLog(@"system menu: the menu is up %.2f s after the %@: Spotify's sheet taken over at %.2f, first asked for at %.2f%@, %@",
          now - from, self.touchedAt ? @"⋯ touch" : @"takeover", self.takenAt - from, _askedAt - from,
          _wasEarly ? @" while the sheet came up" : @"", _openedAt ? [NSString stringWithFormat:@"the sheet up at %.2f", _openedAt - from] : @"before the sheet was up");
}

#pragma mark Spotify's sheet, for the player's menu

// Runs Spotify's ⋯ action from code, as the tap the menu kept from it would have: its sheet comes up, is taken
// for this menu (the presentation hook) and goes into the mod's window.
- (void)requestSheet {
    if (!self.direct || self.presented || _requested) return;
    _requested = YES;
    _requestedAt = CACurrentMediaTime();
    sg_requesting = self;
    sg_requestedAt = _requestedAt;
    // Speed and pitch's sheet test (and Edit info's) counts the ⋯'s touch, which the menu kept from Spotify's ⋯.
    // SGPlayerMenuMarkPlayers();
    NSString *how = fireControl(self.spotify);
    SGLog(@"system menu: Spotify's sheet asked for, %.3f s after the touch down, by %@", _requestedAt - self.touchedAt, how);
    __weak SGRMenuSession *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRequestWindow * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRMenuSession *session = weakSelf;
        if (!session || session.presented) return;
        if (sg_requesting == session) sg_requesting = nil;
        session->_failed = YES;
        SGLog(@"system menu: Spotify's sheet did not come %.0f s after it was asked for", kRequestWindow);
        session->_waiting = NO;
        NSArray<dispatch_block_t> *waiting = session->_whenRead;
        session->_whenRead = [NSMutableArray array];
        for (dispatch_block_t block in waiting) block();
    });
}

// Spotify's sheet, asked for, on its way up from `presenter`: presented in the mod's window instead, unseen.
- (void)adoptSheet:(UIViewController *)presented from:(UIViewController *)presenter completion:(void (^)(void))completion {
    self.presented = presented;
    self.presenter = presenter;
    self.takenAt = CACurrentMediaTime();
    objc_setAssociatedObject(presented, &kSessionKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sg_hosted = self;
    SGRSheetWindow *host = hostWindow(presenter.viewIfLoaded.window.windowScene ?: self.anchor.window.windowScene);
    SGLog(@"system menu: Spotify's sheet (%@) came %.3f s after it was asked for, %.3f s after the touch down; kept in the mod's window",
          controllersIn(presented), self.takenAt - _requestedAt, self.takenAt - self.touchedAt);
    UIViewController *root = host.rootViewController;
    void (^present)(void) = ^{
        sg_redirecting = YES;
        [root presentViewController:presented animated:NO completion:^{
            if (completion) completion();
            [self sheetArrived];
        }];
        sg_redirecting = NO;
        [self hide];
    };
    // An earlier sheet still there (its menu closed while it came) goes first.
    if (root.presentedViewController) [root dismissViewControllerAnimated:NO completion:present];
    else present();
}

- (void)sheetArrived {
    if (_dropOnArrival && !_waiting) {
        [self.presented.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    if (![self readRows]) [self pollRows];
}

// Something of Spotify's was presented while a row picked on this sheet fired: the row's own sheet.
- (void)rowPresented {
    _rowPresented = YES;
}

#pragma mark the menu

// A page's ⋯: Spotify's rows, waited for. The player's: the quick row, the player's items and More, none of
// them waited for; More's rows are, when More is opened before the sheet has them.
- (UIMenu *)menu {
    if (!self.items) return [UIMenu menuWithChildren:@[[self deferredRows]]];
    NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
    UIMenu *quick = [self quickRow];
    if (quick) [children addObject:quick];
    NSArray<UIMenuElement *> *ours = self.items();
    if (ours.count) [children addObject:inlineGroup(ours)];
    UIMenu *more = [UIMenu menuWithTitle:@"More" image:[UIImage systemImageNamed:@"ellipsis.circle"] identifier:kMoreMenu options:0 children:@[[self deferredRows]]];
    [children addObject:inlineGroup(@[more])];
    return [UIMenu menuWithTitle:@"" image:nil identifier:kTopMenu options:0 children:children];
}

// The sheet's rows as menu items, but for the quick ones. Uncached: every menu reads the sheet it was opened with.
- (UIDeferredMenuElement *)deferredRows {
    __weak SGRMenuSession *weakSelf = self;
    return [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        SGRMenuSession *session = weakSelf;
        if (!session || session->_groups) {
            completion(session ? [session rowElements] : @[]);
            return;
        }
        // The player's: the rows the last sheet of this kind had, at once, the live ones put in when they come.
        NSArray<UIMenuElement *> *stored = session.direct ? [session storedElements] : nil;
        if (stored.count) {
            completion(stored);
            return;
        }
        if (session.direct) [session requestSheet];
        if (session->_failed) {
            completion([session unavailable]);
            return;
        }
        SGLog(@"system menu: Spotify's rows asked for before the sheet has them");
        [session->_whenRead addObject:^{
            SGRMenuSession *read = weakSelf;
            completion(read ? (read->_groups ? [read rowElements] : [read unavailable]) : @[]);
        }];
    }];
}

- (NSArray<UIMenuElement *> *)rowElements {
    NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
    for (NSArray<SGRSheetRow *> *group in _groups) {
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        for (SGRSheetRow *row in group) {
            if (!row.quick) [actions addObject:[self actionFor:row]];
        }
        if (actions.count) [groups addObject:inlineGroup(actions)];
    }
    return groups;
}

// Shown when Spotify's sheet never came, so More is not left loading.
- (NSArray<UIMenuElement *> *)unavailable {
    UIAction *none = [UIAction actionWithTitle:@"Spotify's options did not load" image:nil identifier:nil handler:^(UIAction *action) {}];
    none.attributes = UIMenuElementAttributesDisabled;
    return @[none];
}

static NSString *storedKey(NSString *kind) {
    return [NSString stringWithFormat:@"%@.%@", kStoredRowsKey, kind.length ? kind : @"track"];
}

// The rows the last sheet of this kind had, as stored: title, subtitle, enabled and glyph, but for the quick ones.
// Picking one waits for the live rows and fires the row of that title (fireTitle).
- (NSArray<UIMenuElement *> *)storedElements {
    NSArray<NSArray<NSDictionary *> *> *groups = [NSUserDefaults.standardUserDefaults arrayForKey:storedKey(self.kind)];
    if (![groups isKindOfClass:NSArray.class]) return nil;
    __weak SGRMenuSession *weakSelf = self;
    NSMutableArray<UIMenuElement *> *elements = [NSMutableArray array];
    for (NSArray<NSDictionary *> *group in groups) {
        if (![group isKindOfClass:NSArray.class]) continue;
        NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
        for (NSDictionary *row in group) {
            NSString *title = [row isKindOfClass:NSDictionary.class] ? row[@"title"] : nil;
            if (![title isKindOfClass:NSString.class]) continue;
            NSData *glyph = row[@"image"];
            UIImage *image = [glyph isKindOfClass:NSData.class] ? [NSKeyedUnarchiver unarchivedObjectOfClass:UIImage.class fromData:glyph error:nil] : nil;
            UIAction *action = [UIAction actionWithTitle:title image:image identifier:nil handler:^(UIAction *picked) {
                weakSelf.pick = ^{ [weakSelf fireTitle:title]; };
            }];
            NSString *subtitle = row[@"subtitle"];
            if ([subtitle isKindOfClass:NSString.class]) action.subtitle = subtitle;
            if ([row[@"enabled"] isEqual:@NO]) action.attributes = UIMenuElementAttributesDisabled;
            [actions addObject:action];
        }
        if (actions.count) [elements addObject:inlineGroup(actions)];
    }
    return elements;
}

// Keeps a complete read of the rows (all but the quick ones) for the next menu of this kind, when it differs.
- (void)storeRows {
    NSMutableArray *groups = [NSMutableArray array];
    for (NSArray<SGRSheetRow *> *group in _groups) {
        NSMutableArray *rows = [NSMutableArray array];
        for (SGRSheetRow *row in group) {
            if (row.quick || !row.title.length) continue;
            NSMutableDictionary *stored = [@{@"title": row.title, @"enabled": @(row.enabled)} mutableCopy];
            if (row.subtitle.length) stored[@"subtitle"] = row.subtitle;
            NSData *glyph = row.image ? [NSKeyedArchiver archivedDataWithRootObject:row.image requiringSecureCoding:YES error:nil] : nil;
            if (glyph.length && glyph.length < 32 * 1024) stored[@"image"] = glyph;
            [rows addObject:stored];
        }
        if (rows.count) [groups addObject:rows];
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (!groups.count || [[defaults arrayForKey:storedKey(self.kind)] isEqual:groups]) return;
    [defaults setObject:groups forKey:storedKey(self.kind)];
}

// The live rows came while More shows the stored ones or the loading row: More is put right in place.
- (void)refreshMore {
    if (!self.direct || !self.displayed || self.ended) return;
    NSArray<UIMenuElement *> *live = [self rowElements];
    [self.anchor.contextMenuInteraction updateVisibleMenuWithBlock:^UIMenu *(UIMenu *visible) {
        if (![visible.identifier isEqualToString:kMoreMenu]) return visible;
        return [visible menuByReplacingChildren:live];
    }];
}

- (UIAction *)actionFor:(SGRSheetRow *)row {
    __weak SGRMenuSession *weakSelf = self;
    UIAction *action = [UIAction actionWithTitle:row.title image:row.image identifier:nil handler:^(UIAction *picked) {
        weakSelf.pick = ^{ [weakSelf fire:row]; };
    }];
    action.subtitle = row.subtitle;
    if (!row.enabled) action.attributes = UIMenuElementAttributesDisabled;
    return action;
}

- (SGRSheetRow *)rowForQuick:(NSString *)quick {
    for (NSArray<SGRSheetRow *> *group in _groups) {
        for (SGRSheetRow *row in group) if ([row.quick isEqualToString:quick]) return row;
    }
    return nil;
}

// Share, Add to playlist and Add to queue as a row of three, those this sheet has: once it has its rows, the
// ones found in them; before, the ones the last sheet of this kind had, or all three.
- (UIMenu *)quickRow {
    NSArray<NSString *> *seen = sg_quickSeen[self.kind ?: @""];
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
    NSMutableString *shown = [NSMutableString string];
    __weak SGRMenuSession *weakSelf = self;
    for (NSArray<NSString *> *item in quickItems()) {
        NSString *quick = item[2];
        SGRSheetRow *row = [self rowForQuick:quick];
        if (_groups ? !row : (seen && ![seen containsObject:quick])) continue;
        UIAction *action = [UIAction actionWithTitle:item[0] image:[UIImage systemImageNamed:item[1]] identifier:nil handler:^(UIAction *picked) {
            weakSelf.pick = ^{ [weakSelf fireQuick:quick]; };
        }];
        if (row && !row.enabled) action.attributes = UIMenuElementAttributesDisabled;
        [actions addObject:action];
        [shown appendFormat:@"%@%@; ", quick, row && !row.enabled ? @" (grayed out)" : @""];
    }
    _quickShown = shown;
    if (!actions.count) return nil;
    UIMenu *row = [UIMenu menuWithTitle:@"" image:nil identifier:kQuickMenu options:UIMenuOptionsDisplayInline children:actions];
    // Medium, a symbol over a short label: the HIG keeps small, symbols alone, for actions as closely related
    // as Bold and Italic, and gives medium to three important ones, which these are.
    row.preferredElementSize = UIMenuElementSizeMedium;
    return row;
}

// The rows came in while the menu is up: the quick row is put right if they changed it.
- (void)refreshQuickRow {
    if (!self.items || !self.displayed || self.ended) return;
    NSString *before = _quickShown;
    UIMenu *quick = [self quickRow];
    if ([before isEqualToString:_quickShown]) return;
    SGLog(@"system menu: the quick row is now %@(was %@)", _quickShown.length ? _quickShown : @"empty ", before.length ? before : @"empty");
    [self.anchor.contextMenuInteraction updateVisibleMenuWithBlock:^UIMenu *(UIMenu *visible) {
        // Only the top level, never a submenu that happens to be showing.
        if (![visible.identifier isEqualToString:kTopMenu]) return visible;
        NSMutableArray<UIMenuElement *> *children = [visible.children mutableCopy];
        NSUInteger at = [children indexOfObjectPassingTest:^BOOL(UIMenuElement *child, NSUInteger index, BOOL *stop) {
            return [child isKindOfClass:UIMenu.class] && [((UIMenu *)child).identifier isEqualToString:kQuickMenu];
        }];
        if (at != NSNotFound && quick) children[at] = quick;
        else if (at != NSNotFound) [children removeObjectAtIndex:at];
        else if (quick) [children insertObject:quick atIndex:0];
        return [visible menuByReplacingChildren:children];
    }];
}

#pragma mark the rows

- (void)pollRows {
    if (_poll) return;
    __weak SGRMenuSession *weakSelf = self;
    // In the common modes, so a scroll through the menu does not hold the rows back.
    _poll = [NSTimer timerWithTimeInterval:kRowsPoll repeats:YES block:^(NSTimer *timer) {
        SGRMenuSession *session = weakSelf;
        if (!session || (session.ended && !session->_waiting) || [session readRows]) {
            [timer invalidate];
            if (session) session->_poll = nil;
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:_poll forMode:NSRunLoopCommonModes];
}

// Reads the sheet's rows once it has them, and runs what waited for them. Whether they are read.
- (BOOL)readRows {
    if (_groups) return YES;
    UITableView *table = tableIn(self.sheet.viewIfLoaded, 0);
    if (!table || rowCount(table) == 0) return NO;
    CFTimeInterval started = CACurrentMediaTime();
    [table layoutIfNeeded];
    _table = table;
    NSMutableArray<NSArray<SGRSheetRow *> *> *groups = [NSMutableArray array];
    NSArray<SGRSheetRow *> *header = [self modRows:modRowsIn(table.tableHeaderView)];
    if (header.count) [groups addObject:header];
    NSUInteger read = 0;
    for (NSInteger section = 0; section < table.numberOfSections; section++) {
        NSMutableArray<SGRSheetRow *> *rows = [NSMutableArray array];
        for (NSInteger index = 0; index < [table numberOfRowsInSection:section]; index++) {
            SGRSheetRow *row = [self rowAt:[NSIndexPath indexPathForRow:index inSection:section] inTable:table];
            if (row) [rows addObject:row];
        }
        read += rows.count;
        if (rows.count) [groups addObject:rows];
    }
    NSArray<SGRSheetRow *> *footer = [self modRows:modRowsIn(table.tableFooterView)];
    if (footer.count) [groups addObject:footer];
    _groups = groups;
    CFTimeInterval now = CACurrentMediaTime(), from = self.touchedAt ?: self.takenAt;
    SGLog(@"system menu: %lu of Spotify's rows and %lu of the mod's read in %.0f ms, %.2f s after the %@", (unsigned long)read,
          (unsigned long)(header.count + footer.count), (now - started) * 1000, now - from, self.touchedAt ? @"⋯ touch" : @"takeover");
    if (self.items) [self matchQuick];
    if (self.direct) [self storeRows];

    NSArray<dispatch_block_t> *waiting = _whenRead;
    _whenRead = [NSMutableArray array];
    for (dispatch_block_t block in waiting) block();
    [self refreshQuickRow];
    [self refreshMore];
    return YES;
}

- (SGRSheetRow *)rowAt:(NSIndexPath *)path inTable:(UITableView *)table {
    UITableViewCell *cell = [table cellForRowAtIndexPath:path];
    if (!cell && [table.dataSource respondsToSelector:@selector(tableView:cellForRowAtIndexPath:)]) cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
    NSArray<UILabel *> *labels = labelsIn(cell);
    if (!labels.count) return nil;
    SGRSheetRow *row = [SGRSheetRow new];
    row.path = path;
    row.title = labels[0].text;
    if (labels.count > 1) row.subtitle = labels[1].text;
    row.image = glyphIn(cell, row.title);
    row.identifier = identifierIn(cell);
    row.enabled = rowEnabled(table, path, cell, labels[0]);
    return row;
}

- (NSArray<SGRSheetRow *> *)modRows:(NSArray<UIControl *> *)controls {
    NSMutableArray<SGRSheetRow *> *rows = [NSMutableArray array];
    for (UIControl *control in controls) {
        SGRSheetRow *row = [SGRSheetRow new];
        row.control = control;
        row.title = control.accessibilityLabel;
        row.image = glyphIn(control, row.title);
        row.enabled = YES;
        [rows addObject:row];
    }
    return rows;
}

// Marks Spotify's rows that are quick items, remembers which this kind of sheet has, and says so in the log,
// once a kind.
- (void)matchQuick {
    NSString *kind = self.kind ?: @"";
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    NSMutableArray<NSString *> *every = [NSMutableArray array];
    for (NSArray<SGRSheetRow *> *group in _groups) {
        for (SGRSheetRow *row in group) {
            if (!row.path) continue;
            [every addObject:[NSString stringWithFormat:@"%@ (%@)", row.title, row.identifier ?: @"no id"]];
            NSString *title = [row.title.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            for (NSArray<NSString *> *item in quickItems()) {
                if (!([row.identifier isEqualToString:item[3]] || [title isEqualToString:item[2]]) || [found containsObject:item[2]]) continue;
                row.quick = item[2];
                [found addObject:item[2]];
            }
        }
    }
    if (!sg_quickSeen) sg_quickSeen = [NSMutableDictionary dictionary];
    sg_quickSeen[kind] = found;
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    if ([logged containsObject:kind] || logged.count >= 4) return;
    [logged addObject:kind];
    SGLog(@"system menu: the rows of a %@ sheet: %@", kind.length ? kind : @"player", [every componentsJoinedByString:@", "]);
    SGLog(@"system menu: quick items matched by number or title: %@", found.count ? [found componentsJoinedByString:@", "] : @"none");
}

#pragma mark the pick

// A quick item picked: its row fired, after the rows come in if they are not in yet, for up to kQuickWait;
// with no such row, or none in time, Spotify's sheet is shown, so the pick is never lost.
- (void)fireQuick:(NSString *)quick {
    if (_groups) {
        [self fireQuickNow:quick];
        return;
    }
    SGLog(@"system menu: %@ picked before the sheet had its rows, waiting up to %.0f s", quick, kQuickWait);
    _waiting = YES;
    __weak SGRMenuSession *weakSelf = self;
    if (!_whenRead) _whenRead = [NSMutableArray array];
    [_whenRead addObject:^{ [weakSelf fireQuickNow:quick]; }];
    if (self.direct) [self requestSheet];
    if (self.presented) [self pollRows];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kQuickWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRMenuSession *session = weakSelf;
        if (!session || !session->_waiting) return;
        session->_waiting = NO;
        SGLog(@"system menu: the sheet had no rows %.0f s after %@ was picked, Spotify's sheet shown", kQuickWait, quick);
        [session reveal];
    });
}

// A stored row picked: the live row of that title is fired once the rows are in.
- (void)fireTitle:(NSString *)title {
    if (!_groups) {
        SGLog(@"system menu: %@ picked from the stored rows, waiting up to %.0f s for Spotify's", title, kQuickWait);
        _waiting = YES;
        __weak SGRMenuSession *weakSelf = self;
        if (!_whenRead) _whenRead = [NSMutableArray array];
        [_whenRead addObject:^{ [weakSelf fireTitle:title]; }];
        [self requestSheet];
        if (self.presented) [self pollRows];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kQuickWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGRMenuSession *session = weakSelf;
            if (!session || !session->_waiting) return;
            session->_waiting = NO;
            SGLog(@"system menu: the sheet had no rows %.0f s after %@ was picked, Spotify's sheet shown", kQuickWait, title);
            [session reveal];
        });
        return;
    }
    _waiting = NO;
    for (NSArray<SGRSheetRow *> *group in _groups) {
        for (SGRSheetRow *row in group) {
            if ([row.title isEqualToString:title]) {
                [self fire:row];
                return;
            }
        }
    }
    SGLog(@"system menu: Spotify's rows no longer have %@, its sheet shown", title);
    [self reveal];
}

- (void)fireQuickNow:(NSString *)quick {
    _waiting = NO;
    SGRSheetRow *row = [self rowForQuick:quick];
    if (row) {
        [self fire:row];
        return;
    }
    SGLog(@"system menu: this sheet has no %@ row, Spotify's sheet shown", quick);
    [self reveal];
}

// A row of the sheet's fired, on the sheet still hidden under where the menu was.
- (void)fire:(SGRSheetRow *)row {
    UIViewController *presented = self.presented;
    if (!presented.presentingViewController || self.revealed) return;
    sg_firing = self;
    _rowPresented = NO;
    if (row.control) {
        [row.control sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else {
        UITableView *table = _table;
        if (table.window) selectRow(table, row.path);
    }
    // A row that pushes a page of its own inside the sheet shows it as it pushes (the push hook below); one that
    // leaves the sheet up some other way shows it after kSettle.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSettle * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_firing == self) sg_firing = nil;
        UIViewController *still = self.presented;
        if (self.revealed || !still.presentingViewController || still.isBeingDismissed || !still.viewIfLoaded.window) return;
        // Spotify put up a sheet of the row's own (Sleep timer's): that is what shows; the card it came from goes,
        // unseen, never over it.
        if (self->_rowPresented) {
            SGLog(@"system menu: the row picked (%@) put up a sheet of its own, Spotify's hidden card goes unseen", row.title);
            [still.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            return;
        }
        UINavigationController *navigation = self.sheet.navigationController;
        SGLog(@"system menu: the row picked (%@) left Spotify's sheet up without pushing a page, so it is shown (it holds %@%@)", row.title,
              navigation ? [[navigation.viewControllers valueForKey:@"class"] componentsJoinedByString:@" > "] : NSStringFromClass(self.sheet.class),
              still.presentedViewController ? [NSString stringWithFormat:@", and presents %@", NSStringFromClass(still.presentedViewController.class)] : @"");
        [self reveal];
    });
}

// The menu is gone. A pick is fired now, on the sheet still hidden under it; anything else leaves the sheet
// nothing to do, so it goes. Done a turn later, once the menu's own presentation is off the sheet.
- (void)menuEnded {
    if (self.ended) return;
    self.ended = YES;
    void (^pick)(void) = self.pick;
    self.pick = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presented = self.presented;
        if (self.revealed) return;
        // The player's menu with no sheet yet: a pick asks for it and waits for its rows; with no pick, a sheet
        // still on its way goes as it comes.
        if (self.direct && !presented) {
            if (pick) pick();
            else self->_dropOnArrival = YES;
            return;
        }
        if (!presented.presentingViewController) return;
        if (!pick) {
            [presented.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            // Never a hidden sheet left behind: should UIKit have turned the dismissal down, it is asked again.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *still = self.presented;
                if (!still.presentingViewController || still.isBeingDismissed || self.revealed) return;
                SGLog(@"system menu: Spotify's hidden sheet was still up after the menu closed, dismissed again");
                [still.presentingViewController dismissViewControllerAnimated:NO completion:nil];
            });
            return;
        }
        pick();
    });
}

// Spotify's sheet as it would have been: what the menu falls back to, and what a row that opens a page of
// the sheet's own leads to. Speed and pitch's block comes back into it (SGPlayerMenuReplaced).
// The sheet unseen and out of the way of touches, so one left up for any reason never stands between a finger
// and the player.
- (void)hide {
    UIView *container = self.container;
    container.alpha = 0;
    container.userInteractionEnabled = NO;
}

- (void)reveal {
    if (self.revealed || !self.presented) return;
    self.revealed = YES;
    UIView *container = self.container;
    raiseHost(container.window);
    container.userInteractionEnabled = YES;
    SGRAnimate(SGRMotionFade, ^{ container.alpha = 1; }, nil);
    [self.sheet.viewIfLoaded setNeedsLayout];
}

@end

// The session on the sheet or a controller it is inside of. With `fresh`, as the sheet appears, a session whose
// menu has opened is an earlier showing's (a controller Spotify kept and shows again): it is let go, so this
// showing is looked at afresh rather than left to a session that is over.
static SGRMenuSession *sessionFor(UIViewController *controller, BOOL fresh) {
    for (UIViewController *vc = controller; vc; vc = vc.parentViewController) {
        SGRMenuSession *session = objc_getAssociatedObject(vc, &kSessionKey);
        if (!session) continue;
        if (!fresh || !session.opened || session.direct) return session;
        SGLog(@"system menu: a ⋯ sheet appears again holding an earlier showing's session (on %@), let go", NSStringFromClass(vc.class));
        objc_setAssociatedObject(vc, &kSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return nil;
}

BOOL SGPlayerMenuReplaced(UIViewController *menu) {
    SGRMenuSession *session = sessionFor(menu, NO);
    return session && !session.revealed;
}

#pragma mark - the ⋯

void SGRSystemMenuWatch(UIView *button, SGRMenuItems items, SGRMenuKind kind) {
    if (![button isKindOfClass:UIControl.class]) return;
    SGRMenuFront *front = objc_getAssociatedObject(button, &kFrontKey);
    if (!front) {
        front = [SGRMenuFront buttonWithType:UIButtonTypeCustom];
        front.showsMenuAsPrimaryAction = YES;
        // UIKit opens a button's menu on touch down only while the button holds one; a finger's touch on a
        // button with none is taken and opens nothing (phone, and harness/system-menu with a finger's touch,
        // 2026-10-06; -performPrimaryAction, which the harness tapped with before, opens the menu either way).
        // This one stands in until the touch down asks for the session's (configurationForMenuAtLocation:).
        front.menu = [UIMenu menuWithChildren:@[]];
        front.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        front.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        front.isAccessibilityElement = YES;
        front.accessibilityTraits = UIAccessibilityTraitButton;
        objc_setAssociatedObject(button, &kFrontKey, front, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"system menu: the player's ⋯ (%@) opens the menu from a button of the mod's over it", NSStringFromClass(button.class));
    }
    front.spotify = (UIControl *)button;
    front.items = items;
    front.kind = kind;
    // VoiceOver reaches the mod's button rather than Spotify's ⋯, with the ⋯'s own words, so it opens the menu too.
    if (button.isAccessibilityElement) {
        if (button.accessibilityLabel.length) front.accessibilityLabel = button.accessibilityLabel;
        button.isAccessibilityElement = NO;
    }
    if (!front.accessibilityLabel.length) front.accessibilityLabel = @"More";
    if (front.superview != button) [button addSubview:front];
    else if (button.subviews.lastObject != front) [button bringSubviewToFront:front];
    if (!CGRectEqualToRect(front.frame, button.bounds)) front.frame = button.bounds;
    // Where the mod's button sits in the window next to the ⋯, and what a touch at the ⋯'s middle would reach,
    // so the phone log shows the placement: once per change of the one over the other, of the ⋯'s size or of
    // what the touch reaches, not of where the header is (the player's open and close move it every frame).
    if (!button.window || button.bounds.size.width <= 0) return;
    CGRect over = [front convertRect:front.bounds toView:nil], under = [button convertRect:button.bounds toView:nil];
    CGPoint middle = CGPointMake(CGRectGetMidX(under), CGRectGetMidY(under));
    UIView *hit = [button.window hitTest:middle withEvent:nil];
    NSString *reaches = hit == front ? @"it" : NSStringFromClass(hit.class);
    NSString *key = [NSString stringWithFormat:@"%@ %@ %@", NSStringFromCGPoint(CGPointMake(over.origin.x - under.origin.x, over.origin.y - under.origin.y)),
                     NSStringFromCGSize(over.size), NSStringFromCGSize(under.size)];
    key = [key stringByAppendingFormat:@" %@", reaches];
    if (![key isEqualToString:objc_getAssociatedObject(front, &kPlacedKey)]) {
        objc_setAssociatedObject(front, &kPlacedKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        SGLog(@"system menu: the mod's ⋯ at %@ over Spotify's at %@ in the window; a touch at the ⋯'s middle reaches %@",
              NSStringFromCGRect(over), NSStringFromCGRect(under), reaches);
    }
}

UIControl *SGRSystemMenuFront(UIView *button) {
    return objc_getAssociatedObject(button, &kFrontKey);
}

static SGRMenuAnchor *anchorIn(UIView *host) {
    SGRMenuAnchor *anchor = objc_getAssociatedObject(host, &kAnchorKey);
    if (!anchor) {
        anchor = [SGRMenuAnchor buttonWithType:UIButtonTypeCustom];
        anchor.showsMenuAsPrimaryAction = YES;
        anchor.userInteractionEnabled = NO;
        // VoiceOver reaches the ⋯ itself, whose tap brings the menu up the same way.
        anchor.isAccessibilityElement = NO;
        anchor.accessibilityElementsHidden = YES;
        anchor.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        anchor.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(host, &kAnchorKey, anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (anchor.superview != host) [host addSubview:anchor];
    anchor.frame = host.bounds;
    return anchor;
}

// A page's ⋯ was touched this recently: a context menu sheet that is not taken over now is worth a line saying why.
static BOOL claimRecent(void) {
    return SGRPinnedMoreRecentPage() != nil;
}

// Why a sheet was not taken over: every time while a ⋯ touch is recent, so the next log of a ⋯ that opened
// Spotify's sheet says why; a few times otherwise, since every other context menu in the app passes here too.
static void whyNot(NSString *via, BOOL recent, NSString *reason) {
    static int logged;
    if (recent || logged++ < 4) SGLog(@"system menu: a sheet %@, not taken over: %@", via, reason);
}

// The controllers from `presented` down, for the log of a presentation that held no sheet.
static NSString *controllersIn(UIViewController *presented) {
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithObject:NSStringFromClass(presented.class)];
    if ([presented isKindOfClass:UINavigationController.class]) {
        for (UIViewController *vc in ((UINavigationController *)presented).viewControllers) [names addObject:NSStringFromClass(vc.class)];
    }
    for (UIViewController *child in presented.childViewControllers) [names addObject:NSStringFromClass(child.class)];
    return [names componentsJoinedByString:@" > "];
}

// Whether this sheet is a watched ⋯'s, and if so its session, with the sheet's presentation now the menu's.
// `via` says which way in asked, for the log.
static SGRMenuSession *takeOver(UIViewController *presented, NSString *via) {
    BOOL recent = claimRecent();
    if (!sheetIn(presented)) {
        if (recent) SGLog(@"system menu: %@ presented soon after a page's ⋯ touch holds no ⋯ sheet (%@)", NSStringFromClass(presented.class),
                          controllersIn(presented));
        return nil;
    }
    // While a row picked on a menu's sheet fires, what comes up is that row's (Sleep timer's own sheet), never
    // a new ⋯ menu.
    if (sg_firing) {
        whyNot(via, YES, @"it came while a picked row fired, so it is the row's");
        return nil;
    }
    UIView *button = SGRPinnedMoreRecentPage();
    CFTimeInterval touchedAt = 0;
    if (!button) {
        whyNot(via, recent, @"no page's ⋯ was touched");
        return nil;
    }
    if (!button.window) {
        whyNot(via, YES, [NSString stringWithFormat:@"the ⋯ touched (%@) is off screen", NSStringFromClass(button.class)]);
        return nil;
    }
    if ([button.accessibilityIdentifier isEqualToString:@"creator-page"]) {
        whyNot(via, YES, @"artist pages keep Spotify's own menu");
        return nil;
    }
    static BOOL canPresent, checked;
    if (!checked) {
        checked = YES;
        canPresent = [UIControl instancesRespondToSelector:NSSelectorFromString(@"performPrimaryAction")]
                  || [UIContextMenuInteraction instancesRespondToSelector:NSSelectorFromString(@"_presentMenuAtLocation:")];
    }
    if (!canPresent) {
        whyNot(via, YES, @"this iOS has no way to open a button's menu from code");
        return nil;
    }
    SGRMenuSession *session = [SGRMenuSession new];
    session.touchedAt = touchedAt;
    session.takenAt = CACurrentMediaTime();
    session.presented = presented;
    session.anchor = anchorIn(button);
    objc_setAssociatedObject(presented, &kSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGLog(@"system menu: the ⋯ sheet taken over %@ (%@)", via, session.items ? @"the player's" : @"a page's");
    return session;
}

// Should neither appearance call come to a sheet taken over as it laid out, its menu opens once its
// presentation is over all the same: looked at every tenth of a second for up to 3 s.
static void openWhenUp(SGRMenuSession *session, UIViewController *sheet, int tries) {
    __weak UIViewController *weakSheet = sheet;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *up = weakSheet;
        if (session.opened || !up) return;
        UIViewController *outer = up;
        while (outer.parentViewController) outer = outer.parentViewController;
        if ((!up.viewIfLoaded.window || outer.isBeingPresented) && tries < 30) {
            openWhenUp(session, up, tries + 1);
            return;
        }
        SGLog(@"system menu: the ⋯ sheet taken over as it laid out did not say it appeared, its menu opened anyway");
        [session open];
    });
}

// A row picked on the hidden sheet that pushes a page inside it (Sleep timer's options): the page goes in without
// its slide, so the sheet is shown on that page rather than on the card it covers, and the sheet is shown.
%hook UINavigationController
- (void)pushViewController:(UIViewController *)page animated:(BOOL)animated {
    SGRMenuSession *session = sg_firing;
    UIView *container = session.container;
    if (!session || session.revealed || !container || ![self.viewIfLoaded isDescendantOfView:container]) {
        %orig;
        return;
    }
    sg_firing = nil;
    SGLog(@"system menu: the row picked pushed %@ inside Spotify's sheet, which is shown on it", NSStringFromClass(page.class));
    %orig(page, NO);
    [session reveal];
}
%end

%hook UIViewController
- (void)presentViewController:(UIViewController *)presented animated:(BOOL)animated completion:(void (^)(void))completion {
    if (sg_redirecting) {
        %orig;
        return;
    }
    UIWindow *in = self.viewIfLoaded.window;
    // The sheet the player's menu asked Spotify for: into the mod's window, unseen.
    SGRMenuSession *requesting = sg_requesting;
    if (requesting && in != sg_host && CACurrentMediaTime() - sg_requestedAt <= kRequestWindow && ![presented isKindOfClass:UIAlertController.class]) {
        sg_requesting = nil;
        [requesting adoptSheet:presented from:self completion:completion];
        return;
    }
    SGRMenuSession *firing = sg_firing;
    if (firing) {
        SGLog(@"system menu: while a picked row fires, %@ presents %@", NSStringFromClass(self.class), NSStringFromClass(presented.class));
        [firing rowPresented];
    }
    // Spotify presenting from its sheet in the mod's window, or from under it, while that sheet is hidden: it goes
    // up from Spotify's own presenter instead, in Spotify's window, where it can be seen.
    SGRMenuSession *hosted = sg_hosted;
    if (in && in == sg_host && hosted && !hosted.revealed && presented != hosted.presented) {
        UIViewController *from = hosted.presenter;
        while (from.presentedViewController && !from.presentedViewController.isBeingDismissed) from = from.presentedViewController;
        if (from) {
            SGLog(@"system menu: %@ presented from Spotify's hidden sheet goes up from %@ instead", NSStringFromClass(presented.class), NSStringFromClass(from.class));
            sg_redirecting = YES;
            [from presentViewController:presented animated:animated completion:completion];
            sg_redirecting = NO;
            return;
        }
    }
    SGRMenuSession *session = takeOver(presented, @"as it is presented");
    if (!session) {
        %orig;
        return;
    }
    %orig(presented, NO, ^{
        if (completion) completion();
        [session open];
    });
}
%end

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
// A sheet Spotify puts up some other way than presentViewController: (the player's ⋯ on a phone), or inside a
// controller of its own that held no sheet yet when it was presented, is taken over as it first lays out or
// appears, from the same claim, and its menu opened once it has appeared.
//
// Its first layout can come before its presentation's container exists, so it is hidden at each layout and in
// viewWillAppear:, the first moment the container does exist, before it has drawn a frame; its dimming too, so
// the screen does not darken under the menu.
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *sheet = (UIViewController *)self;
    SGRMenuSession *session = sessionFor(sheet, NO);
    // Only a sheet on its way up, not one that was up before the ⋯ was touched laying out again.
    UIViewController *outer = sheet;
    while (outer.parentViewController) outer = outer.parentViewController;
    if (!session && claimRecent() && (!sheet.viewIfLoaded.window || outer.isBeingPresented)) {
        session = takeOver(sheet, @"as it lays out");
        if (session) openWhenUp(session, sheet, 0);
    }
    // Until its menu opens: a session that has opened hides its sheet itself, or is an earlier showing's. The
    // player's sheet stays hidden at every layout until it is shown.
    if (session && (!session.opened || session.direct) && !session.revealed) [session hide];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRMenuSession *session = sessionFor((UIViewController *)self, YES);
    if (!session) session = takeOver((UIViewController *)self, @"as it appears");
    if (session && !session.revealed) [session hide];
    if (session && !session.direct) dispatch_async(dispatch_get_main_queue(), ^{ [session tryEarly]; });
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SGRMenuSession *session = sessionFor((UIViewController *)self, NO);
    if (session && !session.opened) [session open];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[kSheetClass]);
}
