#import <UIKit/UIKit.h>
#import <os/log.h>
#import "Core/SGCore.h"
#import "Redesigned/Home/Home.h"
@interface _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer : UIView @end
@implementation _TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer @end
@interface _TtC16Home_CarouselKit29TouchCancellingCollectionView : UICollectionView @end
@implementation _TtC16Home_CarouselKit29TouchCancellingCollectionView @end
@interface MockHomeHeaderElement : UIView @end
@implementation MockHomeHeaderElement @end
@interface MockHomeHeaderView : UIView @end
@implementation MockHomeHeaderView @end
@interface _TtC19Home_FunkisPageImpl20FunkisViewController : UIViewController @end
@implementation _TtC19Home_FunkisPageImpl20FunkisViewController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; }
@end
BOOL SGRHomeGlassStyle(void) {
    return SGFlag(SGRKeyHomeGlass, YES);
}
double SGRHomeProbeBegin(void) { return 0; }
void SGRHomeProbeEnd(SGRHomeProbe probe, double began) {}
void SGRNavbarSetProfilePhotoVisible(UIView *face) {}
@interface HeaderTestDelegate : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HeaderTestDelegate
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:session.role];
    configuration.delegateClass = self.class; return configuration;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *page = [_TtC19Home_FunkisPageImpl20FunkisViewController new];
    page.view.backgroundColor = UIColor.blackColor;
    UICollectionView *list = [[_TtC16Home_CarouselKit29TouchCancellingCollectionView alloc]
        initWithFrame:page.view.bounds collectionViewLayout:[UICollectionViewFlowLayout new]];
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [page.view addSubview:list];
    UIView *element = [MockHomeHeaderElement new], *header = [MockHomeHeaderView new];
    UIStackView *stack = [UIStackView new];
    stack.distribution = UIStackViewDistributionFill;
    UIView *pills = [UIView new];
    [stack addArrangedSubview:pills];
    [header addSubview:stack]; [element addSubview:header]; [page.view addSubview:element];
    self.window.rootViewController = page; [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        header.frame = CGRectZero; stack.frame = CGRectZero;
        [page viewDidLayoutSubviews];
        UILabel *title = nil;
        for (UIView *v in header.subviews) if ([v isKindOfClass:UILabel.class]) title = (UILabel *)v;
        NSCAssert(title != nil && title.bounds.size.width == 0, @"Reproduce the zero-width first pass");
        element.frame = CGRectMake(0, 62, 402, 50); header.frame = element.bounds;
        stack.frame = CGRectMake(0, 8, 402, 34);
        [stack setNeedsLayout]; [stack layoutIfNeeded];
        NSCAssert(title.text.length && title.frame.size.width > 300 && title.frame.origin.y >= 0,
                  @"Home title must recover on the stack's pass alone");
        UIView *face = [_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer new];
        [face.widthAnchor constraintEqualToConstant:32].active = YES;
        [stack insertArrangedSubview:face atIndex:0];
        [stack setNeedsLayout]; [stack layoutIfNeeded];
        NSCAssert(title.frame.size.width > 0 && CGRectGetMaxX(title.frame) <= CGRectGetMinX(face.frame),
                  @"Home title must end before the late avatar");
        header.frame = CGRectMake(0, 0, 320, 50); stack.frame = CGRectMake(0, 8, 320, 34);
        [stack setNeedsLayout]; [stack layoutIfNeeded];
        NSCAssert(title.frame.size.width > 0 && CGRectGetMaxX(title.frame) <= CGRectGetMinX(face.frame),
                  @"Home title must follow a later width change");
        [list setContentOffset:CGPointMake(0, 120)]; [list layoutSubviews];
        BOOL glass = SGRHomeGlassStyle();
        NSCAssert(glass ? title.alpha < 0.01 : title.alpha > 0.99,
                  @"Home style off must keep the title visible; glass scroll must fade it");
        [list setContentOffset:CGPointZero]; [list layoutSubviews];
        NSCAssert(title.alpha > 0.99, @"Home title must be visible again at the top");
        os_log(OS_LOG_DEFAULT, "[header-test] PASS: Home page %{public}s; zero-width recovery, late avatar, width change, scroll",
               glass ? "on" : "off");
    });
}
@end
__attribute__((constructor(101))) static void defaults(void) {
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"spotifyglass.redesign"];
    [NSUserDefaults.standardUserDefaults setBool:![NSProcessInfo.processInfo.arguments containsObject:@"home-off"]
        forKey:SGRKeyHomeGlass];
}
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HeaderTestDelegate.class)); } }
