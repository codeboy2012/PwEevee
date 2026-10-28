#import "Core/SGCore.h"
#import "TabIcons.h"
#import "Headers/SPTEncoreIconView.h"
#import <objc/message.h>
#import <objc/runtime.h>

NSString *const SGTabIconSetSymbols = @"symbols";

static UIImage *symbolImage(NSString *name) {
    if (!name.length) return nil;
    return [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]];
}

// SPTEncoreIcon exposes one class method per glyph ("podcasts", "heart"), 538 of them in 9.1.78.
static UIView *encoreView(NSString *name, UIColor *color) {
    Class icon = NSClassFromString(@"SPTEncoreIcon");
    Class view = NSClassFromString(@"SPTEncoreIconView");
    SEL glyphSel = NSSelectorFromString(name.length ? name : @"star");
    if (!icon || !view || ![icon respondsToSelector:glyphSel]) return nil;
    id glyph = ((id (*)(id, SEL))objc_msgSend)(icon, glyphSel);
    SPTEncoreIconView *encore = glyph ? [[view alloc] initWithIcon:glyph] : nil;
    [encore setForegroundColor:color];
    return encore;
}

static UIView *symbolView(UIImage *image, UIColor *color) {
    UIImageView *view = [[UIImageView alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    view.tintColor = color;
    view.contentMode = UIViewContentModeCenter;
    return view;
}

UIView *SGTabIconView(NSString *name, BOOL symbol, UIColor *color) {
    UIImage *image = symbol ? symbolImage(name) : nil;
    if (image) return symbolView(image, color);
    return encoreView(name, color) ?: symbolView(symbolImage(@"star.fill"), color);
}

#pragma mark - the catalogs

// Methods every class answers, which are not glyphs and some of which must not be called bare.
static BOOL notAGlyph(NSString *name) {
    static NSSet *names;
    if (!names) names = [NSSet setWithArray:@[@"alloc", @"new", @"class", @"superclass", @"copy", @"mutableCopy", @"description",
                                              @"debugDescription", @"initialize", @"load", @"hash", @"self", @"dealloc", @"init"]];
    return [name hasPrefix:@"_"] || [name hasPrefix:@"."] || [names containsObject:name];
}

// The class methods on SPTEncoreIcon's metaclass that take nothing and return an object, each called
// once and kept when what it returns has a name.
NSArray<NSString *> *SGEncoreGlyphNames(void) {
    static NSArray<NSString *> *glyphs;
    if (glyphs) return glyphs;
    Class icon = NSClassFromString(@"SPTEncoreIcon");
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    unsigned int count = 0;
    Method *methods = icon ? class_copyMethodList(object_getClass(icon), &count) : NULL;
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        // Two arguments are self and _cmd: a selector with no colon of its own.
        if (method_getNumberOfArguments(methods[i]) != 2 || [name containsString:@":"] || notAGlyph(name)) continue;
        const char *types = method_getTypeEncoding(methods[i]);
        if (!types || types[0] != '@') continue;
        @try {
            id glyph = ((id (*)(id, SEL))objc_msgSend)(icon, method_getName(methods[i]));
            if ([glyph respondsToSelector:@selector(name)] && [[glyph name] isKindOfClass:NSString.class] && [glyph name].length) [found addObject:name];
        } @catch (NSException *e) {
            SGLog(@"tab icons: +[SPTEncoreIcon %@] threw %@", name, e.reason);
        }
    }
    free(methods);
    glyphs = [found sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    SGLog(@"tab icons: %lu Encore glyphs", (unsigned long)glyphs.count);
    return glyphs;
}

NSArray<NSString *> *SGCommonTabGlyphs(void) {
    NSArray<NSString *> *all = SGEncoreGlyphNames();
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *name in @[@"home", @"search", @"collection", @"heart", @"playlist", @"album", @"artist", @"podcasts",
                             @"audiobook", @"downloaded", @"bookmark", @"browse", @"star", @"user", @"events", @"queue",
                             @"radio", @"plus"]) {
        if ([all containsObject:name]) [kept addObject:name];
    }
    return kept;
}

NSArray<NSString *> *SGCommonTabSymbols(void) {
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *name in @[@"house.fill", @"magnifyingglass", @"books.vertical.fill", @"heart.fill", @"music.note.list",
                             @"square.stack.fill", @"music.mic", @"mic.fill", @"globe", @"radio.fill", @"headphones",
                             @"star.fill", @"clock.fill", @"arrow.down.circle.fill", @"bookmark.fill", @"person.crop.circle.fill",
                             @"sparkles", @"flame.fill", @"chart.bar.fill", @"waveform", @"calendar", @"ticket.fill",
                             @"list.bullet", @"plus"]) {
        if (symbolImage(name)) [kept addObject:name];
    }
    return kept;
}

// The same symbol drawn for a script (heart.text.square.ar, .hi, .ja…), which a search would list
// once per language.
static BOOL scriptVariant(NSString *name) {
    static NSSet *scripts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        scripts = [NSSet setWithArray:@[@"ar", @"hi", @"he", @"ja", @"th", @"zh", @"bn", @"gu", @"kn", @"ko", @"ml",
                                        @"mr", @"or", @"pa", @"te", @"si", @"ta", @"el", @"ru", @"km", @"my"]];
    });
    NSRange dot = [name rangeOfString:@"." options:NSBackwardsSearch];
    return dot.location != NSNotFound && [scripts containsObject:[name substringFromIndex:dot.location + 1]];
}

// UIKit lists no symbol names. The system's own catalog does, in CoreGlyphs (a link in CoreServices to
// SFSymbols.framework's bundle on iOS 26 and 27, checked against the iOS 27 simulator runtime): its
// symbol_order.plist names each symbol once, in the SF Symbols app's order.
static NSArray<NSString *> *systemSymbolNames(void) {
    NSBundle *glyphs = [NSBundle bundleWithPath:@"/System/Library/CoreServices/CoreGlyphs.bundle"];
    NSString *path = [glyphs pathForResource:@"symbol_order" ofType:@"plist"];
    NSArray *names = path ? [NSArray arrayWithContentsOfFile:path] : nil;
    if (names.count) return names;
    path = [glyphs pathForResource:@"name_availability" ofType:@"plist"];
    NSDictionary *symbols = path ? [NSDictionary dictionaryWithContentsOfFile:path][@"symbols"] : nil;
    return [symbols isKindOfClass:NSDictionary.class] ? symbols.allKeys : nil;
}

void SGLoadSymbolNames(void (^done)(NSArray<NSString *> *names)) {
    static NSArray<NSString *> *loaded;
    static NSMutableArray *waiting;
    if (loaded) {
        done(loaded);
        return;
    }
    BOOL first = !waiting;
    if (first) waiting = [NSMutableArray array];
    [waiting addObject:[done copy]];
    if (!first) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *names = systemSymbolNames();
        // Each name is asked of UIKit, 8,500 of them on iOS 27, so the asking is spread over the cores.
        NSUInteger count = names.count;
        BOOL *draws = calloc(count ?: 1, sizeof(BOOL));
        dispatch_apply(count, DISPATCH_APPLY_AUTO, ^(size_t i) {
            id name = names[i];
            draws[i] = [name isKindOfClass:NSString.class] && !scriptVariant(name) && symbolImage(name);
        });
        NSMutableArray<NSString *> *kept = [NSMutableArray array];
        for (NSUInteger i = 0; i < count; i++) if (draws[i]) [kept addObject:names[i]];
        free(draws);
        dispatch_async(dispatch_get_main_queue(), ^{
            loaded = kept.count ? [kept copy] : SGCommonTabSymbols();
            SGLog(@"tab icons: %lu SF Symbols of %lu listed", (unsigned long)kept.count, (unsigned long)names.count);
            for (void (^callback)(NSArray *) in waiting) callback(loaded);
            waiting = nil;
        });
    });
}
