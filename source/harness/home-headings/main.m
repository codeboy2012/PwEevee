#import <UIKit/UIKit.h>
#import <os/log.h>
#import "Core/SGCore.h"
#import "Redesigned/Home/Home.h"

@interface _TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton : UIControl @end
@implementation _TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton
- (void)layoutSubviews { [super layoutSubviews]; }
@end
@interface _TtC12Element_List18CollectionViewCell : UICollectionViewCell @end
@implementation _TtC12Element_List18CollectionViewCell @end
@interface _TtC16Home_CarouselKit29TouchCancellingCollectionView : UICollectionView @end
@implementation _TtC16Home_CarouselKit29TouchCancellingCollectionView @end

BOOL SGRHomeGlassStyle(void) { return SGFlag(SGRKeyHomeGlass, YES); }
CFTimeInterval SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, CFTimeInterval began) {}
SGModRow *SGSwitchRow(NSString *title, NSString *subtitle, NSString *key) { return nil; }
SGModRow *SGWithSymbol(SGModRow *row, NSString *symbol) { return row; }

#include "HomeTopPicks.m"

@interface FixtureLayout : UICollectionViewLayout @end
@implementation FixtureLayout
- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)path {
    CGFloat tops[] = {0, 124, 188}, heights[] = {100, 40, 240};
    UICollectionViewLayoutAttributes *item = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:path];
    item.frame = CGRectMake(0, tops[path.item], 370, heights[path.item]);
    return item;
}
- (CGSize)collectionViewContentSize { return CGSizeMake(370, 428); }
@end
@interface FixtureList : UICollectionView @end
@implementation FixtureList
- (NSInteger)numberOfItemsInSection:(NSInteger)section { return 3; }
@end

static BOOL visible(UIView *view) {
    if (!view.window) return NO;
    for (UIView *part = view; part; part = part.superview) {
        if (part.hidden || part.alpha < 0.01) return NO;
    }
    return YES;
}

@interface HeadingTestDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic) NSUInteger taps;
@end
@implementation HeadingTestDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:session.role];
    configuration.delegateClass = self.class;
    return configuration;
}
- (void)tapped:(UIControl *)sender { self.taps++; }
- (void)checkHeadings:(UIView *)root {
    UIView *heading = [[UIView alloc] initWithFrame:CGRectMake(16, 130, 370, 48)];
    heading.accessibilityIdentifier = @"Components.UI.SectionHeadingHome";
    [root addSubview:heading];
    UIView *wrapper = [[UIView alloc] initWithFrame:heading.bounds];
    [heading addSubview:wrapper];
    UIControl *button = [[_TtCOOOE11Home_ECMKitO19LegacyUI_ECMCoreKit10Components18SectionHeadingHome2UI7Private28NoIntrinsicContentSizeButton alloc] initWithFrame:wrapper.bounds];
    [wrapper addSubview:button];
    [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
    UILabel *source = [UILabel new];
    source.textColor = UIColor.whiteColor;
    source.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    source.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:source];
    [NSLayoutConstraint activateConstraints:@[
        [source.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
        [source.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    ]];
    for (NSString *text in @[@"Jump back in", @"Recently played", @"Recents", @"Albums by artists you follow", @"Escuchado recientemente", @"Reprendre", @"Quick listens: Audiobooks", @"Jump back in"]) {
        source.text = text;
        button.accessibilityLabel = text;
        [button setNeedsLayout]; [button layoutIfNeeded]; [heading layoutIfNeeded];
        __block BOOL found = NO;
        SGForEachView(heading, ^(UIView *view) {
            if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:text] && visible(view)) found = YES;
        });
        NSCAssert(found, @"Missing shelf heading: %@ (Home page %@)", text, SGRHomeGlassStyle() ? @"on" : @"off");
        NSCAssert(!heading.accessibilityElementsHidden, @"Shelf heading must remain accessible");
    }
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
    NSCAssert(self.taps == 1, @"Heading must keep Spotify's action");
    source.text = nil;
    [button setNeedsLayout]; [button layoutIfNeeded];
    source.text = @"Recently played";
    [button setNeedsLayout]; [button layoutIfNeeded]; [heading layoutIfNeeded];
    __block BOOL found = NO;
    SGForEachView(heading, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:source.text] && visible(view)) found = YES;
    });
    NSCAssert(found, @"Reused shelf heading must recover after an empty label");
    os_log(OS_LOG_DEFAULT, "[headings-test] PASS: shelf headings, localization, reuse, accessibility and taps; Home page %{public}s", SGRHomeGlassStyle() ? "on" : "off");
}
- (void)checkReordering {
    BOOL large = SGFlag(SGRKeyHomeTopPicks, NO);
    sg_enlarging = large;
    sg_cardWidth = 0;
    NSCollectionLayoutSize *card = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:149]
        heightDimension:[NSCollectionLayoutDimension absoluteDimension:195]];
    sg_enlarging = NO;
    BOOL enlarged = card.widthDimension.dimension > 149 && card.heightDimension.dimension > 195;
    NSCAssert(enlarged == large, @"Top picks size must follow its own setting with either Home page setting");
    FixtureLayout *layout = [FixtureLayout new];
    UICollectionView *list = [[FixtureList alloc] initWithFrame:CGRectMake(0, 0, 370, 600) collectionViewLayout:layout];
    sg_pageLayout = layout;
    sg_shortcutsPath = [NSIndexPath indexPathForItem:0 inSection:0];
    sg_topPath = [NSIndexPath indexPathForItem:2 inSection:0];
    NSDictionary *frames = swappedFrames(layout);
    if (!SGRHomeGlassStyle() || !large) {
        NSCAssert(frames == nil, @"Home page off must retain the first shelf heading with Top picks on");
    } else {
        NSCAssert(frames.count == 3, @"Glass Home must keep its promoted shelf layout");
    }
    NSCAssert(list != nil, @"Keep the fixture list alive during the layout query");
    os_log(OS_LOG_DEFAULT, "[headings-test] PASS: Top picks preserves Home page choice; Home page %{public}s", SGRHomeGlassStyle() ? "on" : "off");
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (![NSProcessInfo.processInfo.arguments containsObject:@"top-only"]) [self checkHeadings:root.view];
        [self checkReordering];
    });
}
@end
__attribute__((constructor(101))) static void fixtureDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:@"spotifyglass.redesign"];
    [defaults setBool:![NSProcessInfo.processInfo.arguments containsObject:@"home-off"] forKey:SGRKeyHomeGlass];
    [defaults setBool:![NSProcessInfo.processInfo.arguments containsObject:@"top-off"] forKey:SGRKeyHomeTopPicks];
}
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HeadingTestDelegate.class)); }
}
