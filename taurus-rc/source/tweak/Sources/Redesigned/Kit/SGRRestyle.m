#import <objc/message.h>
#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "SGRRestyle.h"
#import "SGRTokens.h"

static char kPlateKey, kImageObserverKey, kLayoutObserverKey;

@interface SGRWeakBox : NSObject
@property (nonatomic, weak) id value;
@end

@implementation SGRWeakBox
@end

#pragma mark - instance subclasses

static BOOL subclassable(Class cls) {
    const char *name = class_getName(cls);
    return strncmp(name, "_Tt", 3) != 0 && !strchr(name, '.') && strncmp(name, "NSKVONotifying_", 15) != 0;
}

static Class instanceSubclass(Class original, const char *prefix, void (^install)(Class subclass, Class original)) {
    NSString *name = [NSString stringWithFormat:@"%s%s", prefix, class_getName(original)];
    Class subclass = objc_getClass(name.UTF8String);
    if (subclass) return subclass;
    subclass = objc_allocateClassPair(original, name.UTF8String, 0);
    if (!subclass) return Nil;
    install(subclass, original);
    class_addMethod(subclass, @selector(class), imp_implementationWithBlock(^Class(id self) { return original; }), "#@:");
    objc_registerClassPair(subclass);
    return subclass;
}

// Moves the view into the subclass unless it is already in it; NO when the view cannot be subclassed.
static BOOL adopt(UIView *view, const char *prefix, void (^install)(Class subclass, Class original)) {
    Class current = object_getClass(view);
    if (strncmp(class_getName(current), prefix, strlen(prefix)) == 0) return YES;
    if (!subclassable(current)) return NO;
    Class subclass = instanceSubclass(current, prefix, install);
    if (!subclass) return NO;
    object_setClass(view, subclass);
    return YES;
}

static void addOverride(Class subclass, Class original, SEL selector, id block) {
    Method method = class_getInstanceMethod(original, selector);
    if (method) class_addMethod(subclass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method));
}

#pragma mark - the class itself

static BOOL overrideOnClass(Class cls, SEL selector, id (^make)(IMP replaced)) {
    if (!cls || !selector) return NO;
    if (strncmp(class_getName(cls), "NSKVONotifying_", 15) == 0) return NO;
    if (objc_getAssociatedObject(cls, (void *)selector)) return YES;

    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return NO;
    Method own = nil;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) own = methods[i];
    }
    free(methods);
    IMP replaced = own ? method_getImplementation(own)
                       : class_getMethodImplementation(class_getSuperclass(cls), selector);
    if (!replaced) return NO;

    IMP override = imp_implementationWithBlock(make(replaced));
    if (own) method_setImplementation(own, override);
    else if (!class_addMethod(cls, selector, override, method_getTypeEncoding(inherited))) return NO;
    objc_setAssociatedObject(cls, (void *)selector, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

// Said once per class: what could not be watched at all, and what had to be watched through its class.
static void logWatch(UIView *view, SEL selector, BOOL kept, BOOL onClass) {
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass(object_getClass(view));
    NSString *mark = [NSString stringWithFormat:@"%@ %s", name, sel_getName(selector)];
    if ([logged containsObject:mark]) return;
    [logged addObject:mark];
    if (!kept) SGLog(@"redesign kit: %@ cannot be watched for %s", name, sel_getName(selector));
    else if (onClass) SGLog(@"redesign kit: %@ watched for %s through its class", name, sel_getName(selector));
}

#pragma mark - views

void SGRSuppress(UIView *view) {
    if (!view) return;
    BOOL kept = adopt(view, "SGRSuppressed_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(setAlpha:), ^(UIView *self, CGFloat alpha) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, CGFloat))objc_msgSendSuper)(&parent, @selector(setAlpha:), 0);
        });
        addOverride(subclass, original, @selector(setUserInteractionEnabled:), ^(UIView *self, BOOL enabled) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&parent, @selector(setUserInteractionEnabled:), NO);
        });
    });
    if (!kept) {
        static NSMutableSet<NSString *> *logged;
        if (!logged) logged = [NSMutableSet set];
        NSString *name = NSStringFromClass(object_getClass(view));
        if (![logged containsObject:name]) {
            [logged addObject:name];
            SGLog(@"redesign kit: %@ cannot keep being suppressed, set once per call", name);
        }
    }
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
}

static BOOL hasMonospacedDigits(UIFont *font) {
    for (NSDictionary *setting in font.fontDescriptor.fontAttributes[UIFontDescriptorFeatureSettingsAttribute]) {
        if ([setting[UIFontFeatureTypeIdentifierKey] integerValue] == kNumberSpacingType
            && [setting[UIFontFeatureSelectorIdentifierKey] integerValue] == kMonospacedNumbersSelector) return YES;
    }
    return NO;
}

static void applyMonospaced(UILabel *label, Class original) {
    NSAttributedString *text = label.attributedText;
    struct objc_super parent = {label, original};
    if (!text.length) {
        UIFont *font = label.font;
        if (font && !hasMonospacedDigits(font)) {
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setFont:), SGRMonospacedDigitsFont(font));
        }
        return;
    }
    __block NSMutableAttributedString *mapped = nil;
    [text enumerateAttribute:NSFontAttributeName inRange:NSMakeRange(0, text.length) options:0 usingBlock:^(UIFont *font, NSRange range, BOOL *stop) {
        if (!font || hasMonospacedDigits(font)) return;
        if (!mapped) mapped = [text mutableCopy];
        [mapped addAttribute:NSFontAttributeName value:SGRMonospacedDigitsFont(font) range:range];
    }];
    if (mapped) ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setAttributedText:), mapped);
}

static BOOL sg_keepingMonospaced = NO;

static void keepMonospaced(UILabel *label, Class original) {
    if (sg_keepingMonospaced) return;
    sg_keepingMonospaced = YES;
    applyMonospaced(label, original);
    sg_keepingMonospaced = NO;
}

void SGRMonospacedDigits(UILabel *label) {
    if (![label isKindOfClass:UILabel.class]) return;
    BOOL kept = adopt(label, "SGRMonospaced_", ^(Class subclass, Class original) {
        for (NSString *name in @[@"setText:", @"setAttributedText:", @"setFont:"]) {
            SEL selector = NSSelectorFromString(name);
            addOverride(subclass, original, selector, ^(UILabel *self, id value) {
                struct objc_super parent = {self, original};
                ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, selector, value);
                keepMonospaced(self, original);
            });
        }
    });
    Class original = kept ? class_getSuperclass(object_getClass(label)) : object_getClass(label);
    keepMonospaced(label, original);
}

// Only the views that asked: everything else of the class carrying the override goes straight back out.
static void reportImage(UIImageView *view) {
    void (^block)(UIImageView *) = objc_getAssociatedObject(view, &kImageObserverKey);
    if (block) block(view);
}

BOOL SGRObserveImage(UIImageView *view, void (^changed)(UIImageView *view)) {
    if (![view isKindOfClass:UIImageView.class]) return NO;
    BOOL first = objc_getAssociatedObject(view, &kImageObserverKey) == nil;
    objc_setAssociatedObject(view, &kImageObserverKey, changed, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(view, "SGRImageObserved_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(setImage:), ^(UIImageView *self, UIImage *image) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&parent, @selector(setImage:), image);
            reportImage(self);
        });
    });
    BOOL onClass = !kept && overrideOnClass(object_getClass(view), @selector(setImage:), ^id(IMP replaced) {
        return ^(UIImageView *self, UIImage *image) {
            ((void (*)(id, SEL, id))replaced)(self, @selector(setImage:), image);
            reportImage(self);
        };
    });
    if (first) logWatch(view, @selector(setImage:), kept || onClass, onClass);
    return kept || onClass;
}

static BOOL sg_reportingLayout = NO;

BOOL SGRObserveLayout(UIView *view, void (^laidOut)(UIView *view)) {
    if (![view isKindOfClass:UIView.class]) return NO;
    objc_setAssociatedObject(view, &kLayoutObserverKey, laidOut, OBJC_ASSOCIATION_COPY_NONATOMIC);
    BOOL kept = adopt(view, "SGRLayoutObserved_", ^(Class subclass, Class original) {
        addOverride(subclass, original, @selector(layoutSubviews), ^(UIView *self) {
            struct objc_super parent = {self, original};
            ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&parent, @selector(layoutSubviews));
            if (sg_reportingLayout) return;
            void (^block)(UIView *) = objc_getAssociatedObject(self, &kLayoutObserverKey);
            if (!block) return;
            sg_reportingLayout = YES;
            block(self);
            sg_reportingLayout = NO;
        });
    });
    if (!kept) {
        static NSMutableSet<NSString *> *logged;
        if (!logged) logged = [NSMutableSet set];
        NSString *name = NSStringFromClass(object_getClass(view));
        if (![logged containsObject:name]) {
            [logged addObject:name];
            SGLog(@"redesign kit: %@ cannot be watched for its layout", name);
        }
    }
    return kept;
}

// An identifier ending in * matches by prefix, for Spotify's ids that carry an entity after a dash.
static BOOL identifierMatches(NSString *identifier, NSString *wanted) {
    if (!identifier) return NO;
    if ([wanted hasSuffix:@"*"]) return [identifier hasPrefix:[wanted substringToIndex:wanted.length - 1]];
    return [identifier isEqualToString:wanted];
}

static UIView *findIdentifier(UIView *view, NSString *identifier) {
    if (identifierMatches(view.accessibilityIdentifier, identifier)) return view;
    for (UIView *sub in view.subviews) {
        UIView *found = findIdentifier(sub, identifier);
        if (found) return found;
    }
    return nil;
}

UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if (!root || !identifier.length) return nil;
    SGRWeakBox *box = cacheKey ? objc_getAssociatedObject(root, cacheKey) : nil;
    UIView *cached = box.value;
    if (cached && identifierMatches(cached.accessibilityIdentifier, identifier) && [cached isDescendantOfView:root]) return cached;
    UIView *found = findIdentifier(root, identifier);
    if (found && cacheKey) {
        if (!box) {
            box = [SGRWeakBox new];
            objc_setAssociatedObject(root, cacheKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        box.value = found;
    }
    return found;
}

@implementation SGRShadowPlate {
    CGRect _pathBounds;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _cornerRadius = SGRRadiusArtwork;
    _pathBounds = CGRectNull;
    CALayer *layer = self.layer;
    layer.shadowColor = UIColor.blackColor.CGColor;
    layer.shadowOpacity = 0.45;
    layer.shadowRadius = 32;
    layer.shadowOffset = CGSizeMake(0, 12);
    return self;
}

- (void)setCornerRadius:(CGFloat)radius {
    _cornerRadius = radius;
    _pathBounds = CGRectNull;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (CGRectEqualToRect(bounds, _pathBounds)) return;
    _pathBounds = bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:_cornerRadius].CGPath;
    [CATransaction commit];
}

@end

SGRShadowPlate *SGRShadowPlateIn(UIView *host, const void *key) {
    if (!host) return nil;
    const void *slot = key ?: &kPlateKey;
    SGRShadowPlate *plate = objc_getAssociatedObject(host, slot);
    if (!plate) {
        plate = [[SGRShadowPlate alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, slot, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (plate.superview != host) [host insertSubview:plate atIndex:0];
    return plate;
}

#pragma mark - Spotify's controls and pages

static const CGFloat kPaintedShare = 0.75;

static void clearPaint(UIView *view, UIView *cell, CGFloat wide) {
    BOOL full = view.bounds.size.width >= wide;
    if (view != cell && !full && [view isKindOfClass:UICollectionViewCell.class]) return;
    if (full) {
        CGColorRef color = view.layer.backgroundColor;
        if (color && SGIsBaseSurface(color)) view.backgroundColor = UIColor.clearColor;
        if (!view.layer.mask && [NSStringFromClass(view.class) containsString:@"GradientView"]) view.layer.mask = [CALayer layer];
    }
    for (UIView *sub in view.subviews) clearPaint(sub, cell, wide);
}

void SGRClearCellPaint(UIView *cell) {
    if (!cell) return;
    clearPaint(cell, cell, cell.bounds.size.width * kPaintedShare);
}

void SGRActivate(UIView *source) {
    if (!source) return;
    __block UIControl *control = nil;
    SGForEachView(source, ^(UIView *v) {
        if (!control && [v isKindOfClass:UIControl.class]) control = (UIControl *)v;
    });
    if (control && SGRFire(control)) return;
    id target = control ?: source;
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass([target class]);
    if (![logged containsObject:name]) {
        [logged addObject:name];
        SGLog(@"redesign kit: %@ fired through accessibility", name);
    }
    [target accessibilityActivate];
}

BOOL SGRFire(UIControl *control) {
    if (![control isKindOfClass:UIControl.class]) return NO;
    __block UIControlEvents registered = control.allControlEvents;
    [control enumerateEventHandlers:^(UIAction *action, id target, SEL selector, UIControlEvents events, BOOL *stop) {
        registered |= events;
    }];
    UIControlEvents fire = (registered & UIControlEventPrimaryActionTriggered) ? UIControlEventPrimaryActionTriggered
                         : (registered & UIControlEventTouchUpInside) ? UIControlEventTouchUpInside : 0;
    static NSMutableSet<NSString *> *logged;
    if (!logged) logged = [NSMutableSet set];
    NSString *name = NSStringFromClass(control.class);
    if (![logged containsObject:name]) {
        [logged addObject:name];
        SGLog(@"redesign kit: %@ fires %@ (events 0x%lx)", name, fire == UIControlEventPrimaryActionTriggered ? @"its primary action" : fire ? @"touch up inside" : @"nothing", (unsigned long)registered);
    }
    if (!fire) return NO;
    [control sendActionsForControlEvents:fire];
    return YES;
}
