// Player redesign: the footer as the Music app's row of three glyphs, lyrics, devices and queue, spread
// evenly across the player, and no share button.
//
// Spotify's footer is Connect with the device's name at the leading edge, share, and the queue at the
// trailing edge. Connect and the queue stay Spotify's controls (the device sheet, the remote device
// tint, the Jam avatars) and are only moved, by a translation of the arranged view that holds each: a
// transform survives the stack view laying them out again, and moving the holder keeps its touches
// inside its own bounds. The device name goes transparent, since the glyph alone sits in the middle, and
// Connect's holder takes touches only in a square over the glyph (coverConnect).
// Spotify has no lyrics control down here, so that one is the Kit's glyph button, and it turns the
// lyrics in the player on and off (PlayerLyrics.x): filled while they are up, dimmed and dead for a
// track that has none.
//
// The row sits lower than Spotify puts it, just over the home indicator the way the Music app's does
// (issue #54): the footer unit's view is translated down, the controls follow it part of the way, and a
// band of the redesign's hands the touches below the bottom stack's bounds back to the row.
//
// Tree (trees/clean/player/01.txt:295-320): FooterElementsUnit's view 402x44 > UIStackView 382x44 >
// ElementView > ConnectButtonOutputSwitcherViewHolder id=Components.ConnectButtonOutputSwitcher 153x36
// (a 19x19 UIImageView glyph and a MarqueeLabel with the device name), a spacer, a hidden media trimmer,
// ElementView > EncoreButton id=ShareButtonNowPlayingView 44x44, ElementView > Queue control
// id=QueueButtonNowPlaying 47x32.
#import <substrate.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/PlayerState.h"
#import "Player.h"

static const CGFloat kLyricsGlyphSize = 20;
// Filled and at full strength while the lyrics are up, the way the Music app marks the control that is on.
static NSString *const kLyricsSymbol = @"quote.bubble", *const kLyricsSymbolOpen = @"quote.bubble.fill";
// Where the three glyphs sit, as parts of the footer's width.
static const CGFloat kLeading = 0.2, kMiddle = 0.5, kTrailing = 0.8;
static const CGFloat kGlyphMaxWidth = 30;

// Issue #54: Spotify ends its bottom stack 61pt above the screen's bottom (01.txt:127, 576.67 + 236 of
// 874), so the row's middle sat 83pt up, well clear of the home indicator, and the controls crowded it.
// The Music app keeps that row just over the home indicator: its middle this far above the safe area's
// bottom, and never less than kRowMinBottom above the screen's on a phone without a home indicator.
static const CGFloat kRowAboveSafeArea = 20, kRowMinBottom = 34;
// The controls follow a share of the row's move when nothing stands between them, so the gaps above
// and below them even out instead of all the room opening under them.
static const CGFloat kControlsShare = 0.3;
// The volume row's sides, the player's own margin.
static const CGFloat kVolumeMargin = 24;
// And the controls go up this much over it, so the gaps above and below the volume row match.
static const CGFloat kVolumeLift = 10;

static char kConnectKey, kShareKey, kTrimmerKey, kSharedByKey, kQueueKey, kLyricsGlyphKey, kReachKey;
static __weak SGRGlyphButton *sg_lyricsGlyph;
static __weak UIView *sg_footerHost;
static BOOL sg_playerIsVisible;

static void refreshFooter(void) {
    UIView *host = sg_footerHost;
    if (!sg_playerIsVisible || !host.window) return;
    [host.superview setNeedsLayout];
    [host setNeedsLayout];
    [host.superview layoutIfNeeded];
    [host layoutIfNeeded];
    UIView *connect = SGRFindByIdentifier(host, @"Components.ConnectButtonOutputSwitcher", &kConnectKey);
    [connect setNeedsLayout];
    [connect layoutIfNeeded];
}

@interface SGRFooterStateWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRFooterStateWatcher
{
    NSUInteger _refreshGeneration;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSUInteger generation = ++_refreshGeneration;
    for (NSNumber *delay in @[@0, @0.2, @0.7]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation == self->_refreshGeneration) refreshFooter();
        });
    }
}
@end

static SGRFooterStateWatcher *sg_footerStateWatcher;

static BOOL sg_idleTimerOwned;
static BOOL sg_idleTimerWasDisabled;

static void updatePlayerIdleTimer(void) {
    UIApplication *application = UIApplication.sharedApplication;
    if (sg_playerIsVisible) {
        if (!sg_idleTimerOwned) {
            sg_idleTimerWasDisabled = application.idleTimerDisabled;
            sg_idleTimerOwned = YES;
        }
        application.idleTimerDisabled = !SGEnabled(SGRKeyPlayerAllowAutoLock);
    } else if (sg_idleTimerOwned) {
        application.idleTimerDisabled = sg_idleTimerWasDisabled;
        sg_idleTimerOwned = NO;
    }
}

// The view the footer's stack view arranges around `view`.
static UIView *arrangedAround(UIView *view, UIView *host) {
    for (UIView *v = view; v && v != host; v = v.superview) {
        if ([v.superview isKindOfClass:UIStackView.class]) return v;
    }
    return nil;
}

// Where `point` of `view` is in the host with the arranged view's own transform left out.
static CGFloat untransformedX(UIView *arranged, UIView *view, CGPoint point, UIView *host) {
    CGPoint local = [view convertPoint:point toView:arranged];
    CGPoint inRow = CGPointMake(arranged.center.x + local.x - CGRectGetMidX(arranged.bounds), arranged.center.y);
    return [arranged.superview convertPoint:inRow toView:host].x;
}

static CGFloat moveTo(UIView *arranged, UIView *view, CGPoint point, UIView *host, CGFloat x) {
    if (!arranged) return -1;
    CGFloat from = untransformedX(arranged, view, point, host);
    CGAffineTransform transform = CGAffineTransformMakeTranslation(round(x - from), 0);
    if (!CGAffineTransformEqualToTransform(arranged.transform, transform)) arranged.transform = transform;
    return from;
}

#pragma mark - lyrics

void SGRPlayerLyricsChanged(void) {
    SGRPlayerMotionLyricsChanged();
    SGRPlayerVisualiserUpdate();
    SGRGlyphButton *glyph = sg_lyricsGlyph;
    if (!glyph) return;
    BOOL enabled = SGRPlayerLyricsAvailable() || SGRPlayerLyricsOpen(), open = SGRPlayerLyricsOpen();
    BOOL wasOpen = [glyph.glyph.symbol isEqualToString:kLyricsSymbolOpen];
    if (glyph.enabled == enabled && wasOpen == open) return;
    // Lyrics turn up once the player has fetched them, well after the footer laid out: a fade, not a pop.
    // While the player opens or closes the glyph and the lyrics come and go together, so nothing animates.
    BOOL animated = glyph.window && !SGRPlayerIsTransitioning();
    [glyph.glyph setSymbol:open ? kLyricsSymbolOpen : kLyricsSymbol animated:animated];
    void (^mark)(void) = ^{
        glyph.enabled = enabled;
        glyph.glyph.tintColor = open ? SGRPrimary() : SGRSecondary();
    };
    if (animated) SGRAnimate(SGRMotionFade, mark, nil);
    else mark();
}

static SGRGlyphButton *lyricsGlyphIn(UIView *host) {
    SGRGlyphButton *glyph = objc_getAssociatedObject(host, &kLyricsGlyphKey);
    if (!glyph) {
        glyph = [SGRGlyphButton buttonWithSymbol:kLyricsSymbol pointSize:kLyricsGlyphSize title:@"Lyrics"];
        glyph.glyph.tintColor = SGRSecondary();
        glyph.onTap = ^{ SGRPlayerToggleLyrics(); };
        objc_setAssociatedObject(host, &kLyricsGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (glyph.superview != host) [host addSubview:glyph];
    sg_lyricsGlyph = glyph;
    return glyph;
}

#pragma mark - the row

static UIView *connectGlyphIn(UIView *holder) {
    __block UIView *glyph = nil;
    SGForEachView(holder, ^(UIView *view) {
        if (!glyph && [view isKindOfClass:UIImageView.class] && view.bounds.size.width > 0 && view.bounds.size.width <= kGlyphMaxWidth) glyph = view;
    });
    return glyph;
}

// Connect is Spotify's control as wide as the device's name, with the glyph near its leading edge. With the
// name hidden and the glyph in the middle, its touches would reach far past the glyph, over the queue, and
// hardly before it. So the row's view that holds it takes touches only in a square over the glyph, the size
// of the row's other two; Spotify's own views inside still handle them. The square is kept on that view, and
// its class answers from it, as it does for every other view of the class.
static char kConnectHitKey;
static BOOL (*sg_origPointInside)(UIView *, SEL, CGPoint, UIEvent *);

static BOOL connectPointInside(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    NSValue *square = objc_getAssociatedObject(self, &kConnectHitKey);
    if (square) return CGRectContainsPoint(square.CGRectValue, point);
    return sg_origPointInside(self, _cmd, point, event);
}

static void coverConnect(UIView *arranged, UIView *glyph) {
    if (!arranged || !glyph) return;
    static Class hooked;
    if (!hooked) {
        hooked = arranged.class;
        MSHookMessageEx(hooked, @selector(pointInside:withEvent:), (IMP)connectPointInside, (IMP *)&sg_origPointInside);
    }
    if (arranged.class != hooked) return;
    CGRect drawn = [glyph convertRect:glyph.bounds toView:arranged];
    CGRect square = CGRectMake(CGRectGetMidX(drawn) - 22, CGRectGetMidY(drawn) - 22, 44, 44);
    objc_setAssociatedObject(arranged, &kConnectHitKey, [NSValue valueWithCGRect:square], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - lower down

// Moved down, the row is drawn partly below the bottom stack it is arranged in, and UIKit does not look
// into a view for a touch outside its bounds. This band over the part that hangs out hands such a touch
// to the row itself, and lets every other one through.
@interface SGRFooterReach : UIView
@property (nonatomic, weak) UIView *row;
@end

@implementation SGRFooterReach
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = self.row;
    if (!row.window || row.alpha < 0.01 || row.hidden) return nil;
    UIView *hit = [row hitTest:[row convertPoint:point fromView:self] withEvent:event];
    return hit == row ? nil : hit;
}
@end

static UIViewController *unitOf(UIView *view) {
    UIResponder *next = view.nextResponder;
    return [next isKindOfClass:UIViewController.class] && ((UIViewController *)next).viewIfLoaded == view ? (UIViewController *)next : nil;
}

// The arranged view drawn right above `row` in its stack, by where the stack put them.
static UIView *rowAbove(UIView *row) {
    UIView *best = nil;
    CGFloat top = row.center.y - row.bounds.size.height / 2, bestBottom = -CGFLOAT_MAX;
    for (UIView *sibling in row.superview.subviews) {
        if (sibling == row || sibling.hidden || sibling.alpha < 0.01 || sibling.bounds.size.height < 1) continue;
        CGFloat bottom = sibling.center.y + sibling.bounds.size.height / 2;
        if (bottom <= top + 1 && bottom > bestBottom) {
            best = sibling;
            bestBottom = bottom;
        }
    }
    return best;
}

static void lowerRow(UIView *row) {
    UIView *stack = row.superview, *player = stack.superview;
    UIWindow *window = row.window;
    if (![stack isKindOfClass:UIStackView.class] || !player || !window) return;
    // Where the stack put the row, the row's own transform left out, and where it belongs.
    CGFloat middle = [stack convertPoint:row.center toView:player].y;
    CGFloat height = player.bounds.size.height;
    CGFloat target = height - MAX(window.safeAreaInsets.bottom + kRowAboveSafeArea, kRowMinBottom);
    CGFloat move = MAX(0, round(target - middle));
    CGAffineTransform down = CGAffineTransformMakeTranslation(0, move);
    if (!CGAffineTransformEqualToTransform(row.transform, down)) row.transform = down;

    // Only the controls, and only straight above: a volume row between them keeps its place and theirs.
    UIView *above = rowAbove(row);
    BOOL controls = [NSStringFromClass(unitOf(above).class) containsString:@"PlaybackControlsElementsUnit"];
    // With the volume row, the controls stay where Spotify put them and the row takes the room the footer leaves.
    // The volume row is placed against the controls where they would stand for it; one that does not show leaves them
    // following the footer as they do without it.
    BOOL volume = SGRPlayerVolumeOn() && controls;
    CGFloat share = volume ? 0 : kControlsShare, lift = volume ? kVolumeLift : 0;
    CGAffineTransform follow = CGAffineTransformMakeTranslation(0, controls ? round(move * share) - lift : 0);
    if (above && controls && !CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;
    SGRPlayerPaintCover(stack);
    if (volume && !SGRPlayerPlaceVolume(stack, above, row, kVolumeMargin)) {
        share = kControlsShare;
        follow = CGAffineTransformMakeTranslation(0, round(move * share));
        if (!CGAffineTransformEqualToTransform(above.transform, follow)) above.transform = follow;
    } else if (!volume) {
        SGRPlayerPlaceVolume(stack, nil, row, kVolumeMargin);
    }

    SGRFooterReach *reach = objc_getAssociatedObject(row, &kReachKey);
    if (!reach) {
        reach = [SGRFooterReach new];
        reach.row = row;
        objc_setAssociatedObject(row, &kReachKey, reach, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (reach.superview != player) [player addSubview:reach];
    CGRect stackFrame = [stack convertRect:stack.bounds toView:player];
    CGRect drawn = [row convertRect:row.bounds toView:player];
    CGFloat from = CGRectGetMaxY(stackFrame);
    CGRect band = CGRectMake(CGRectGetMinX(drawn), from, drawn.size.width, MAX(0, CGRectGetMaxY(drawn) - from));
    if (!CGRectEqualToRect(reach.frame, band)) reach.frame = band;

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: footer row from %.0f to %.0f of %.0f (safe area %.0f), controls %@ %.0f, volume %@", middle, middle + move, height,
              window.safeAreaInsets.bottom, controls ? @"follow" : @"stay", controls ? round(move * share) : 0, SGRPlayerVolumeOn() ? @"on" : @"off");
    });
}

%hook _TtC20NowPlaying_ModesImpl18FooterElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host) return;
    sg_footerHost = host;
    // The unit lays out before its row does, and the moves are measured from where the row put things.
    [SGRowIn(host) layoutIfNeeded];
    CGFloat width = host.bounds.size.width, middleY = CGRectGetMidY(host.bounds);
    BOOL rtl = host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;

    UIView *share = SGRFindByIdentifier(host, @"ShareButtonNowPlayingView", &kShareKey);
    // The arranged view goes too: a view that takes touches swallows them even with nothing on it.
    SGRPlayerVanish(share);
    SGRPlayerVanish(arrangedAround(share, host));
    // Spotify's clip button, hidden in every clean tree, would turn up where the queue moves to.
    UIView *trimmer = SGRFindByIdentifier(host, @"nowplaying-npv-media-trimmer-navigation-button", &kTrimmerKey);
    SGRPlayerVanish(trimmer);
    SGRPlayerVanish(arrangedAround(trimmer, host));
    // "From <friend>" on a track a friend shared sits in the middle of the row, over Connect, which the
    // row moves there; the Music app has no such chip.
    UIView *sharedBy = SGRFindByIdentifier(host, @"Components.UI.SharedByChip", &kSharedByKey);
    SGRPlayerVanish(sharedBy);
    SGRPlayerVanish(arrangedAround(sharedBy, host));

    SGRGlyphButton *lyrics = lyricsGlyphIn(host);
    lyrics.bounds = CGRectMake(0, 0, 44, 44);
    lyrics.center = CGPointMake(round(width * (rtl ? kTrailing : kLeading)), middleY);
    SGRPlayerLyricsChanged();

    UIView *connect = SGRFindByIdentifier(host, @"Components.ConnectButtonOutputSwitcher", &kConnectKey);
    // The unit lays out before Connect has sized its glyph, the first time the player opens: Connect is laid
    // out first so the glyph is there to move to the middle. Should it still be missing, Connect stays where
    // Spotify put it, since centering the whole control would leave the glyph well off the middle, and the unit
    // looks again on the next turn of the run loop.
    [connect layoutIfNeeded];
    UIView *glyph = connectGlyphIn(connect);
    static NSUInteger lookedAgain;   // a Connect with no glyph at all is left alone after this many
    if (glyph) lookedAgain = 0;
    if (connect && !glyph && lookedAgain++ < 20) {
        __weak UIView *weakHost = host;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakHost setNeedsLayout]; });
    }
    // The name is a MarqueeLabel on the phone's speaker and a plain Encore label on AirPods; Connect holds
    // nothing else that draws text.
    SGForEachView(connect, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] || [NSStringFromClass(view.class) containsString:@"MarqueeLabel"]) SGRPlayerVanish(view);
    });
    CGFloat connectFrom = glyph ? moveTo(arrangedAround(connect, host), glyph, CGPointMake(CGRectGetMidX(glyph.bounds), CGRectGetMidY(glyph.bounds)), host, round(width * kMiddle)) : -1;

    UIView *queue = SGRFindByIdentifier(host, @"QueueButtonNowPlaying", &kQueueKey);
    CGFloat queueFrom = moveTo(arrangedAround(queue, host), queue, CGPointMake(CGRectGetMidX(queue.bounds), CGRectGetMidY(queue.bounds)), host, round(width * (rtl ? kLeading : kTrailing)));

    lowerRow(host);
    coverConnect(arrangedAround(connect, host), glyph);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"redesign player: footer lyrics at %.0f, connect %.0f (%@) to %.0f, queue %.0f to %.0f, share %@", lyrics.center.x,
              connectFrom, glyph ? @"glyph" : @"button", round(width * kMiddle), queueFrom, round(width * (rtl ? kLeading : kTrailing)), share ? @"gone" : @"not found");
    });
}
%end

%hook _TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sg_playerIsVisible = YES;
    updatePlayerIdleTimer();
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sg_playerIsVisible = YES;
    updatePlayerIdleTimer();
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    sg_playerIsVisible = NO;
    updatePlayerIdleTimer();
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18FooterElementsUnit",
                       @"_TtC21NowPlaying_ScrollImpl27NPVBackgroundViewController"]);
    sg_footerStateWatcher = [SGRFooterStateWatcher new];
    SGAddPlayerStateObserver(sg_footerStateWatcher);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationDidBecomeActiveNotification, NSUserDefaultsDidChangeNotification]) {
        [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            updatePlayerIdleTimer();
            if (name == UIApplicationDidBecomeActiveNotification) {
                refreshFooter();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ refreshFooter(); });
            }
        }];
    }
}
