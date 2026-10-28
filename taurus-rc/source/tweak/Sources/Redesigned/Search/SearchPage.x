#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

// Layout passes without the header before that is logged.
static const NSUInteger kMissesLogged = 60;

static char kTitleKey;

static __weak UICollectionView *sg_list;
static __weak UIStackView *sg_row;
static __weak UIView *sg_scrim;

static void vanish(UIView *view) {
    if (!view) return;
    if (view.alpha != 0) view.alpha = 0;
    if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

// A depth first search that leaves the list out: the header and the scrim sit beside it, and its cells are hundreds of views.
static UIView *findOutsideList(UIView *view, NSString *identifier) {
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class]) continue;
        if ([sub.accessibilityIdentifier isEqualToString:identifier]) return sub;
        UIView *found = findOutsideList(sub, identifier);
        if (found) return found;
    }
    return nil;
}

static BOOL findParts(UIView *view) {
    if (sg_row && sg_list && [sg_row isDescendantOfView:view] && [sg_list isDescendantOfView:view]) return YES;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:UICollectionView.class] && [sub.accessibilityIdentifier isEqualToString:SGRSearchListIdentifier]) {
            sg_list = (UICollectionView *)sub;
        }
        UIView *scrim = childNamed(sub, @"GradientView");
        if (scrim) sg_scrim = scrim;
    }
    UIView *row = findOutsideList(view, @"SearchToolBar.Header");
    sg_row = [row isKindOfClass:UIStackView.class] ? (UIStackView *)row : nil;
    if (sg_row && sg_list) return YES;
    static NSUInteger misses;
    if (++misses == kMissesLogged) {
        SGLog(@"redesign search: page parts not found in %lu passes (toolbar row %@, list %@), the header left as Spotify's",
              (unsigned long)misses, sg_row ? @"found" : @"missing", sg_list ? @"found" : @"missing");
    }
    return NO;
}

static NSString *titleText(UIStackView *row) {
    UIView *label = nil;
    for (UIView *part in row.arrangedSubviews) {
        if ([part.accessibilityIdentifier isEqualToString:@"SearchHeaderFind.HeaderLabel"]) label = part;
    }
    for (UIView *sub in label.subviews) {
        if ([sub isKindOfClass:UILabel.class] && ((UILabel *)sub).text.length) return ((UILabel *)sub).text;
    }
    return @"Search";
}

static UILabel *titleIn(UIStackView *row) {
    UILabel *title = objc_getAssociatedObject(row, &kTitleKey);
    if (!title) {
        title = [UILabel new];
        title.textColor = SGRPrimary();
        title.accessibilityTraits = UIAccessibilityTraitHeader;
        title.adjustsFontSizeToFitWidth = YES;
        title.minimumScaleFactor = 0.6;
        title.userInteractionEnabled = NO;
        objc_setAssociatedObject(row, &kTitleKey, title, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (title.superview != row) [row addSubview:title];
    return title;
}

static void layoutHeader(UIStackView *row) {
    vanish(sg_scrim);

    static Class faceClass;
    if (!faceClass) faceClass = NSClassFromString(@"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer");
    UIView *face = nil;
    NSString *text = titleText(row);
    for (UIView *part in row.arrangedSubviews) {
        if (faceClass && [part isKindOfClass:faceClass]) face = part;
        else vanish(part);
    }
    if (row.semanticContentAttribute != UISemanticContentAttributeForceRightToLeft) {
        row.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        [row setNeedsLayout];
    }
    [row layoutIfNeeded];

    UILabel *title = titleIn(row);
    if (![title.text isEqualToString:text]) {
        title.text = text;
        title.accessibilityLabel = text;
    }
    UIFont *font = SGRFont(UIFontTextStyleLargeTitle, UIFontWeightBold, UIContentSizeCategoryLarge);
    if (![title.font isEqual:font]) title.font = font;

    CGFloat trailing = face ? CGRectGetMinX(face.frame) - SGRGrid : row.bounds.size.width;
    CGFloat height = ceil(font.lineHeight);
    CGRect frame = CGRectMake(0, round(CGRectGetMidY(row.bounds) - height / 2), MAX(0, trailing), height);
    if (!CGRectEqualToRect(title.frame, frame)) title.frame = frame;

    static BOOL logged;
    if (!logged && row.window && CGRectGetMinX(row.frame) >= 0 && row.bounds.size.width > 0) {
        logged = YES;
        SGLog(@"redesign search: toolbar row %@, avatar %@, title %@ \"%@\", scrim %@", NSStringFromCGRect(row.frame),
              face ? NSStringFromCGRect(face.frame) : @"not found", NSStringFromCGRect(frame), text, sg_scrim ? @"found" : @"not found");
    }
}

%hook _TtC21Browse_BrowsePageImpl24BrowsePageViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *view = ((UIViewController *)self).viewIfLoaded;
    if (!view || !findParts(view)) return;
    layoutHeader(sg_row);
    SGRSearchCloseGap(sg_list);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    %orig;
    [((UIViewController *)self).viewIfLoaded setNeedsLayout];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC21Browse_BrowsePageImpl24BrowsePageViewController",
        @"_TtC29ListeningActivity_ElementsKit21AdaptiveFaceContainer",
    ]);
}
