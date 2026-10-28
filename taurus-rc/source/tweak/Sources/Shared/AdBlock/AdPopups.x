#import "Core/SGCore.h"
#import "AdBlock.h"

static NSString *const words[] = {
    @"premium", @"upgrade", @"subscribe", @"subscription", @"listening without limits", @"unlimited skips",
    @"play the songs you love", @"go premium", @"like listening", @"free account", @"ad-free", @"ad free", @"try free",
    @"get premium", @"start premium", @"upsell", @"paywall", @"free tier", @"limited listening",
    @"předplatn", @"bez reklam",
};

static char kUpsellKey;

static BOOL sells(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    text = text.lowercaseString;
    for (size_t i = 0; i < sizeof(words) / sizeof(words[0]); i++) {
        if ([text containsString:words[i]]) return YES;
    }
    return NO;
}

static void mark(id object) {
    objc_setAssociatedObject(object, &kUpsellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL marked(id object) {
    return objc_getAssociatedObject(object, &kUpsellKey) != nil;
}

// valueForKey: on a key the object lacks raises, so it is only asked what it answers to.
static id readKey(id object, NSString *key) {
    return [object respondsToSelector:NSSelectorFromString(key)] ? [object valueForKey:key] : nil;
}

%hook SPTEncorePopUpDialogModel
- (id)initWithTitle:(NSString *)title description:(NSString *)description image:(id)image primaryButtonTitle:(NSString *)primary secondaryButtonTitle:(NSString *)secondary {
    id model = %orig;
    if (model && (sells(title) || sells(description) || sells(primary) || sells(secondary))) mark(model);
    return model;
}
%end

%hook SPTEncorePopUpDialog
- (void)update:(id)model {
    if (marked(model)) mark(self);
    %orig;
}
%end

%hook SPTEncorePopUpPresenter
- (void)presentPopUp:(id)popUp {
    SGAdBlockSawOne(@"Popups");
    id model = readKey(popUp, @"model") ?: popUp;
    NSString *title = readKey(model, @"title") ?: readKey(model, @"dialogTitle");
    NSString *body = readKey(model, @"descriptionText") ?: readKey(model, @"body") ?: readKey(model, @"subtitle");
    if (marked(popUp) || sells(title) || sells(body)) {
        SGAdBlockCountOne(@"Popups");
        SGLog(@"dropped pop-up %@", title ?: @"(marked at its model)");
        return;
    }
    %orig;
}
%end

%ctor {
    if (!SGFlag(SGKeyHideUpsells, YES)) return;
    %init;
    SGRequireClasses(@[@"SPTEncorePopUpDialogModel", @"SPTEncorePopUpDialog", @"SPTEncorePopUpPresenter"]);
}
