// A round button of Spotify's mocked the way the player's header holds one -- a 48x48 control whose glyph is
// its own subview -- with the real SGRGlassInside behind it, so what the glass does to the glyph can be looked
// at on the Mac. Issue #39: the glyph comes out blurred and unreadable on the phone.
//
// Three columns, all the same button and the same shape, differing only in how the shape is put behind it:
//
//   as shipped   the shape first in the button's subviews (Redesigned/Kit/SGRGlass.m)
//   by depth     the shape added last and pushed back with zPosition -1, the way it used to be
//   outside      the shape a sibling of the button, behind it in its superview
//
// A UIVisualEffectView takes its backdrop from what is drawn beneath it *in its own backdrop group*, which is
// the nearest ancestor that gathers one. A shape inside the button is in the button's group, so the glyph can
// be in its backdrop however the shape is ordered; a shape outside cannot be. The three columns are here to
// show which of those actually happens.
#import <UIKit/UIKit.h>
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"

// The accent is the only thing the Kit's tokens reach out for and it is not what is being looked at here.
UIColor *SGRAccentColor(void) { return nil; }

static const CGFloat kButton = 48;

// Spotify's header button: a control with the glyph as a subview of its own, which is what a shape inside has
// to sit behind (trees/clean/player/01.txt:103, id=now-playing-minimize-button 48x48).
static UIView *mockButton(NSString *symbol) {
    UIView *button = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kButton, kButton)];
    UIImageConfiguration *weight = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:weight]];
    glyph.tintColor = UIColor.whiteColor;
    glyph.contentMode = UIViewContentModeCenter;
    glyph.frame = button.bounds;
    [button addSubview:glyph];
    return button;
}

@interface SGRGlassHarnessDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGRGlassHarnessDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *root = [UIViewController new];
    self.window.rootViewController = root;
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIView *page = root.view;
    page.backgroundColor = UIColor.blackColor;

    // Something with colour and detail under the glass, so a shape that is refracting the page reads as glass
    // rather than as a flat disc. The player's field is artwork blurred behind the header the same way.
    CAGradientLayer *field = [CAGradientLayer layer];
    field.frame = CGRectMake(0, 0, page.bounds.size.width, 420);
    field.colors = @[(id)[UIColor colorWithRed:0.42 green:0.05 blue:0.09 alpha:1].CGColor,
                     (id)[UIColor colorWithRed:0.10 green:0.02 blue:0.03 alpha:1].CGColor];
    [page.layer addSublayer:field];

    NSArray<NSString *> *symbols = @[@"chevron.down", @"ellipsis", @"shuffle", @"arrow.down"];
    NSArray<NSString *> *ways = @[@"as shipped", @"by depth", @"outside"];

    for (NSUInteger way = 0; way < ways.count; way++) {
        UILabel *caption = [UILabel new];
        caption.text = ways[way];
        caption.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        caption.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        caption.frame = CGRectMake(24, 60 + way * 120, 200, 18);
        [page addSubview:caption];

        for (NSUInteger i = 0; i < symbols.count; i++) {
            UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(24 + i * 70, 88 + way * 120, kButton, kButton)];
            [page addSubview:holder];
            UIView *button = mockButton(symbols[i]);
            [holder addSubview:button];

            static char keys[3][4];
            UIView *shape = SGRGlassInside(button, &keys[way][i], SGRGlassCircleSize);
            if (way == 1) {
                // Pushed back by depth while sitting last in the subviews, the way it used to be.
                shape.layer.zPosition = -1;
                [button addSubview:shape];
            } else if (way == 2) {
                // A sibling of the button, so the button's content is not in the shape's backdrop group at all.
                shape.layer.zPosition = 0;
                shape.center = CGPointMake(CGRectGetMidX(holder.bounds), CGRectGetMidY(holder.bounds));
                [holder insertSubview:shape belowSubview:button];
            }
        }
    }

    [self.window makeKeyAndVisible];
    [page layoutIfNeeded];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGRGlassHarnessDelegate.class));
    }
}
