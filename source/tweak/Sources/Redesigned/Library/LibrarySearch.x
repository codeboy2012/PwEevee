#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Library.h"

static char kFieldKey, kCancelKey;

static UIView *childNamed(UIView *host, NSString *marker) {
    for (UIView *sub in host.subviews) {
        if ([NSStringFromClass(sub.class) containsString:marker]) return sub;
    }
    return nil;
}

static void capsule(UIView *shape) {
    CGFloat height = shape.bounds.size.height;
    if (height < 24) return;
    CALayer *layer = shape.layer;
    if (layer.cornerRadius != height / 2) layer.cornerRadius = height / 2;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;
}

%hook _TtC28YourLibrary_YourLibraryXImpl21YourLibrarySearchView
- (void)layoutSubviews {
    %orig;
    UIView *header = childNamed((UIView *)self, @"YourLibrarySearchHeaderView");
    if (!header) return;
    SGRLibraryClearScrim(header);
    UIView *field = SGRFindByIdentifier(header, @"Components.Header.UI.Toolbar.SearchField", &kFieldKey);
    UIView *cancel = SGRFindByIdentifier(header, @"Components.Header.UI.Toolbar.ButtonContainer", &kCancelKey);
    capsule(field);
    capsule(cancel);

    // The first pass the field had a size on: before that there is no shape to report.
    static BOOL logged;
    if (!logged && field.bounds.size.height > 1) {
        logged = YES;
        SGLog(@"redesign library: search field %@ at r=%.1f, cancel %@", NSStringFromCGRect(field.bounds),
              field.layer.cornerRadius, cancel ? @"a capsule too" : @"not found");
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC28YourLibrary_YourLibraryXImpl21YourLibrarySearchView"]);
}
