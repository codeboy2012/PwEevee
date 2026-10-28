#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"

static char kGlassKey, kCloseKey, kMoreKey, kPillKey, kPillViewKey;

static void glassInside(UIViewController *unit, NSArray<NSString *> *identifiers, const void **findKeys) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    NSUInteger found = 0;
    for (NSUInteger i = 0; i < identifiers.count; i++) {
        UIView *button = SGRFindByIdentifier(host, identifiers[i], findKeys[i]);
        if (!button) {
            static NSMutableSet<NSString *> *missing;
            if (!missing) missing = [NSMutableSet set];
            if (![missing containsObject:identifiers[i]]) {
                [missing addObject:identifiers[i]];
                SGLog(@"redesign player: %@ not found in %@, left as Spotify's", identifiers[i], NSStringFromClass(host.class));
            }
            continue;
        }
        SGRGlassInside(button, &kGlassKey, SGRGlassCircleSize);
        if ([identifiers[i] isEqualToString:@"Context menu"]) {
            SGPlayerMenuWatchMoreButton(button);
            SGRPlayerMenuWatchMoreButton(button);
        }
        found++;
    }

    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *unitName = NSStringFromClass(unit.class);
    if (![logged containsObject:unitName]) {
        [logged addObject:unitName];
        SGLog(@"redesign player: glass inside %lu of %lu buttons in %@", (unsigned long)found, (unsigned long)identifiers.count, unitName);
    }
}


// The header's context line ("Playing from ...") on a glass pill of its own, so it reads over any cover, the
// sharp artwork of the fill background included. The pill is a passthrough view under the label, sized to
// the text, so Spotify's label keeps its layout and its taps.
static const CGFloat kPillPadX = 16, kPillMinHeight = 34;

static UILabel *contextLabelIn(UIView *host) {
    __block UILabel *found = nil;
    SGForEachView(host, ^(UIView *view) {
        if (found || ![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (label.hidden || label.alpha < 0.01 || !label.text.length || label.bounds.size.width < 60) return;
        found = label;
    });
    return found;
}

static void pillBehindContext(UIViewController *unit) {
    UIView *host = unit.viewIfLoaded;
    if (!host) return;
    UILabel *label = contextLabelIn(host);
    UIView *box = label ? objc_getAssociatedObject(label, &kPillViewKey) : nil;
    if (!label || !label.superview) {
        box.hidden = YES;
        return;
    }
    if (!box) {
        box = [UIView new];
        box.userInteractionEnabled = NO;
        box.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(label, &kPillViewKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *parent = label.superview;
    if (box.superview != parent) [parent insertSubview:box belowSubview:label];
    else if ([parent.subviews indexOfObject:box] > [parent.subviews indexOfObject:label]) [parent insertSubview:box belowSubview:label];

    CGSize text = [label.text sizeWithAttributes:@{NSFontAttributeName: label.font ?: [UIFont systemFontOfSize:14]}];
    CGFloat width = MIN(ceil(text.width) + 2 * kPillPadX, MAX(parent.bounds.size.width - 8, 0));
    CGFloat height = MAX(kPillMinHeight, ceil(text.height) + 14);
    box.bounds = CGRectMake(0, 0, width, height);
    box.center = label.center;
    box.hidden = label.hidden;
    box.alpha = label.alpha;
    SGRGlassCapsuleInside(box, &kPillKey, box.bounds.size, NO);
}

%hook _TtC20NowPlaying_ModesImpl18HeaderElementsUnit
- (void)viewDidLayoutSubviews {
    %orig;
    static const void *keys[] = {&kCloseKey, &kMoreKey};
    glassInside((UIViewController *)self, @[@"now-playing-minimize-button", @"Context menu"], keys);
    pillBehindContext((UIViewController *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC20NowPlaying_ModesImpl18HeaderElementsUnit"]);
}
