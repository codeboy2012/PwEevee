// Turkish for the mod's own screens, without touching the tweak's sources.
//
// The tweak writes its English straight into the .m files, so there is no table to add a language to.
// This dylib swaps that English for Turkish (tr.json, embedded at link time as __TEXT,__pwee_tr) at
// the UIKit setters the tweak draws through: labels, buttons, list configurations, menus, alerts.
// It runs only while Spotify itself is in Turkish, and it only touches text whose call stack comes
// from spotifyglass.dylib or SpotifyAudioProbe.dylib, so Spotify's own labels -- a song called
// "Close", say -- are never translated. A string the table does not know is left as it was.
//
// scripts/pipeline.sh builds and injects it; --no-turkish leaves it out. After strings change in the
// tweak, extension/Turkish/untranslated.py lists the ones tr.json does not cover yet.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <pthread.h>
#import <dlfcn.h>
#import <mach-o/getsect.h>
#include <string.h>

#pragma mark - PwEevee image ranges

typedef struct { uintptr_t start, end; } Range;
static Range gRanges[4];
static volatile int gRangeCount;

static void onImage(const struct mach_header *mh, intptr_t slide) {
    Dl_info info;
    if (!dladdr(mh, &info) || !info.dli_fname) return;
    const char *base = strrchr(info.dli_fname, '/');
    base = base ? base + 1 : info.dli_fname;
    if (strcmp(base, "spotifyglass.dylib") && strcmp(base, "SpotifyAudioProbe.dylib")) return;
    const struct mach_header_64 *h = (const struct mach_header_64 *)mh;
    const uint8_t *p = (const uint8_t *)(h + 1);
    for (uint32_t i = 0; i < h->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (!strcmp(seg->segname, "__TEXT") && gRangeCount < 4) {
                gRanges[gRangeCount] = (Range){ seg->vmaddr + slide, seg->vmaddr + slide + seg->vmsize };
                gRangeCount++;
            }
        }
        p += lc->cmdsize;
    }
}

static inline BOOL inTweak(uintptr_t a) {
    a &= 0x0000000FFFFFFFFFULL;
    for (int i = 0; i < gRangeCount; i++)
        if (a >= gRanges[i].start && a < gRanges[i].end) return YES;
    return NO;
}

// 2 = the setter was called straight from PwEevee, 1 = PwEevee is a few frames up, 0 = not PwEevee.
static int __attribute__((noinline)) callerLevel(uintptr_t ret0, uintptr_t *fp) {
    if (!gRangeCount) return 0;
    if (inTweak(ret0)) return 2;
    pthread_t t = pthread_self();
    uintptr_t hi = (uintptr_t)pthread_get_stackaddr_np(t);
    uintptr_t lo = hi - pthread_get_stacksize_np(t);
    // fp is the hook's own frame; fp[1] is ret0, so start one frame further up.
    for (int depth = 0; depth < 6 && fp; depth++) {
        uintptr_t *next = (uintptr_t *)fp[0];
        if ((uintptr_t)next <= (uintptr_t)fp || (uintptr_t)next >= hi || (uintptr_t)next < lo || ((uintptr_t)next & 7)) break;
        fp = next;
        if (inTweak(fp[1])) return 1;
    }
    return 0;
}

#define LEVEL() callerLevel((uintptr_t)__builtin_return_address(0), (uintptr_t *)__builtin_frame_address(0))

#pragma mark - Dictionary

typedef struct {
    NSRegularExpression *re;
    NSString *prefix, *suffix, *tr;
} Pattern;

static NSDictionary<NSString *, NSString *> *gExact;
static Pattern *gPatterns;
static NSUInteger gPatternCount;
static NSArray<NSString *> *gFragments; // keys glued to a name at runtime ("Watch more from ")
static NSCache *gCache;

// Length of the printf conversion starting at s[i] == '%', 0 if malformed. *conv gets the conversion char.
static NSUInteger specLen(NSString *s, NSUInteger i, unichar *conv) {
    NSUInteger n = s.length, j = i + 1;
    while (j < n && [@"0123456789$-+ #'.*hlqLzjt" rangeOfString:[s substringWithRange:NSMakeRange(j, 1)]].location != NSNotFound) j++;
    if (j >= n) return 0;
    *conv = [s characterAtIndex:j];
    if (!strchr("@dDiuUxXoOfFeEgGcCsSp%", *conv)) return 0;
    return j - i + 1;
}

static BOOL buildPattern(NSString *key, NSString *tr, Pattern *out) {
    NSMutableString *re = [NSMutableString stringWithString:@"^"];
    NSMutableString *lit = [NSMutableString string];
    NSString *prefix = nil;
    NSUInteger n = key.length, i = 0, last = 0, specs = 0, literalChars = 0;
    while (i < n) {
        unichar c = [key characterAtIndex:i];
        if (c != '%') { i++; continue; }
        unichar conv = 0;
        NSUInteger len = specLen(key, i, &conv);
        if (!len) return NO;
        [lit appendString:[key substringWithRange:NSMakeRange(last, i - last)]];
        if (conv == '%') { [lit appendString:@"%"]; i += len; last = i; continue; }
        if (!prefix) prefix = [lit copy];
        literalChars += [lit stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length;
        [re appendString:[NSRegularExpression escapedPatternForString:lit]];
        [lit setString:@""];
        switch (conv) {
            case 'd': case 'D': case 'i': case 'u': case 'U': [re appendString:@"(-?[0-9]+)"]; break;
            case 'f': case 'F': case 'e': case 'E': case 'g': case 'G': [re appendString:@"(-?[0-9.,e+-]+)"]; break;
            case 'x': case 'X': case 'p': [re appendString:@"((?:0x)?[0-9a-fA-F]+)"]; break;
            case 'c': case 'C': [re appendString:@"(.)"]; break;
            default: [re appendString:@"([\\s\\S]*?)"]; break; // may be empty: plural "s" suffixes
        }
        specs++;
        i += len; last = i;
    }
    [lit appendString:[key substringFromIndex:last]];
    literalChars += [lit stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length;
    if (!specs || literalChars < 4) return NO;
    [re appendString:[NSRegularExpression escapedPatternForString:lit]];
    [re appendString:@"$"];
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:re options:0 error:nil];
    if (!rx) return NO;
    *out = (Pattern){ rx, prefix ?: @"", [lit copy], tr };
    return YES;
}

static BOOL loadDictionary(void) {
    Dl_info image;
    if (!dladdr((const void *)&loadDictionary, &image)) return NO;
    unsigned long size = 0;
    uint8_t *bytes = getsectiondata((const struct mach_header_64 *)image.dli_fbase, "__TEXT", "__pwee_tr", &size);
    if (!bytes || !size) return NO;
    NSData *data = [NSData dataWithBytesNoCopy:bytes length:size freeWhenDone:NO];
    NSDictionary *all = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![all isKindOfClass:NSDictionary.class]) return NO;
    NSMutableDictionary *exact = [NSMutableDictionary dictionary];
    NSMutableArray *frags = [NSMutableArray array];
    gPatterns = calloc(all.count, sizeof(Pattern));
    NSCharacterSet *edge = [NSCharacterSet characterSetWithCharactersInString:@" :·—-("];
    [all enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        if (![k isKindOfClass:NSString.class] || ![v isKindOfClass:NSString.class]) return;
        unichar dummy;
        NSRange pct = [k rangeOfString:@"%"];
        BOOL isFormat = NO;
        for (NSUInteger i = pct.location; pct.location != NSNotFound && i < k.length; i++) {
            if ([k characterAtIndex:i] == '%' && specLen(k, i, &dummy) && dummy != '%') { isFormat = YES; break; }
        }
        // Also kept as an exact key: "100% is" reads like a "% i" conversion but is shown literally.
        exact[k] = v;
        if (isFormat) {
            Pattern p;
            if (buildPattern(k, v, &p)) gPatterns[gPatternCount++] = p;
            return;
        }
        if (k.length >= 6 && ([edge characterIsMember:[k characterAtIndex:k.length - 1]] || [edge characterIsMember:[k characterAtIndex:0]]))
            [frags addObject:k];
    }];
    [frags sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return b.length < a.length ? NSOrderedAscending : b.length > a.length ? NSOrderedDescending : NSOrderedSame; }];
    gExact = exact;
    gFragments = frags;
    gCache = [NSCache new];
    gCache.countLimit = 4000;
    return YES;
}

#pragma mark - Translation

static NSString *fillFormat(NSString *fmt, NSArray<NSString *> *args) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = fmt.length, i = 0, seq = 0, last = 0;
    while (i < n) {
        if ([fmt characterAtIndex:i] != '%') { i++; continue; }
        unichar conv = 0;
        NSUInteger len = specLen(fmt, i, &conv);
        if (!len) { i++; continue; }
        [out appendString:[fmt substringWithRange:NSMakeRange(last, i - last)]];
        if (conv == '%') {
            [out appendString:@"%"];
        } else {
            NSString *spec = [fmt substringWithRange:NSMakeRange(i + 1, len - 1)];
            NSRange dollar = [spec rangeOfString:@"$"];
            NSUInteger idx = dollar.location != NSNotFound ? (NSUInteger)[spec substringToIndex:dollar.location].integerValue - 1 : seq++;
            if (idx < args.count) [out appendString:args[idx]];
        }
        i += len; last = i;
    }
    [out appendString:[fmt substringFromIndex:last]];
    return out;
}

static NSString *translateLine(NSString *s, int level) {
    NSString *hit = gExact[s];
    if (hit) {
        if (level == 2) return hit;
        NSUInteger words = [s componentsSeparatedByString:@" "].count;
        if (level == 1 && words >= 2) return hit;
        if (level == 0 && words >= 4 && s.length >= 20) return hit;
        return nil;
    }
    if (level == 0) return nil;
    NSString *trimmed = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length != s.length && trimmed.length && gExact[trimmed]) {
        NSRange r = [s rangeOfString:trimmed];
        return [s stringByReplacingCharactersInRange:r withString:gExact[trimmed]];
    }
    for (NSUInteger p = 0; p < gPatternCount; p++) {
        Pattern *pt = &gPatterns[p];
        // hasPrefix:@"" is NO, so empty ends are checked by length.
        if ((pt->prefix.length && ![s hasPrefix:pt->prefix]) || (pt->suffix.length && ![s hasSuffix:pt->suffix])) continue;
        NSTextCheckingResult *m = [pt->re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        if (!m) continue;
        NSMutableArray *args = [NSMutableArray array];
        for (NSUInteger g = 1; g < m.numberOfRanges; g++) {
            NSRange r = [m rangeAtIndex:g];
            NSString *arg = r.location == NSNotFound ? @"" : [s substringWithRange:r];
            [args addObject:gExact[arg] ?: arg]; // "On"/"Off" style values inside a format
        }
        return fillFormat(pt->tr, args);
    }
    NSString *out = s;
    for (NSString *frag in gFragments) {
        if ([out rangeOfString:frag].location != NSNotFound) out = [out stringByReplacingOccurrencesOfString:frag withString:gExact[frag]];
    }
    return out == s ? nil : out;
}

static NSString *TR(NSString *s, int level) {
    if (![s isKindOfClass:NSString.class] || s.length < 2 || !gExact) return s;
    if (level == 0) {
        // Spotify's own text: only long exact sentences, no cache churn for every song title.
        if (s.length < 20) return s;
        return translateLine(s, 0) ?: s;
    }
    NSString *ck = [NSString stringWithFormat:@"%d\x1f%@", level, s];
    id cached = [gCache objectForKey:ck];
    if (cached) return cached == NSNull.null ? s : cached;
    NSString *out = translateLine(s, level);
    if (!out && level && [s rangeOfString:@"\n"].location != NSNotFound) {
        NSArray *lines = [s componentsSeparatedByString:@"\n"];
        NSMutableArray *done = [NSMutableArray arrayWithCapacity:lines.count];
        BOOL changed = NO;
        for (NSString *l in lines) {
            NSString *t = l.length ? translateLine(l, level) : nil;
            [done addObject:t ?: l];
            changed |= t != nil;
        }
        if (changed) out = [done componentsJoinedByString:@"\n"];
    }
    [gCache setObject:out ?: NSNull.null forKey:ck];
    return out ?: s;
}

static NSAttributedString *TRA(NSAttributedString *a, int level) {
    if (![a isKindOfClass:NSAttributedString.class] || a.length < 2 || !gExact) return a;
    NSString *s = a.string;
    NSString *whole = TR(s, level);
    if (whole != s && [s rangeOfString:@"\n"].location == NSNotFound) {
        NSMutableAttributedString *m = a.mutableCopy;
        [m replaceCharactersInRange:NSMakeRange(0, m.length) withString:whole];
        return m;
    }
    // Multi-line: swap line by line so a bold title and its description keep their own styles.
    NSMutableAttributedString *m = nil;
    NSArray *lines = [s componentsSeparatedByString:@"\n"];
    NSUInteger loc = s.length;
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0; i--) {
        NSString *l = lines[i];
        loc -= l.length;
        NSString *t = l.length >= 2 ? TR(l, level) : l;
        if (t != l && ![t isEqualToString:l]) {
            if (!m) m = a.mutableCopy;
            [m replaceCharactersInRange:NSMakeRange(loc, l.length) withString:t];
        }
        if (i > 0) loc -= 1;
    }
    return m ?: a;
}

#pragma mark - Hooks

static void swap(Class c, SEL sel, IMP imp, IMP *orig) {
    Method m = class_getInstanceMethod(c, sel);
    if (!m) return;
    // Only replace a method the class itself defines; add an override otherwise so the
    // superclass keeps its original implementation for other subclasses.
    if (class_addMethod(c, sel, imp, method_getTypeEncoding(m))) *orig = method_getImplementation(m);
    else *orig = method_setImplementation(m, imp);
}
#define HOOK_I(cls, sel, name) swap(cls, @selector(sel), (IMP)name##_h, (IMP *)&name##_o)
#define HOOK_C(cls, sel, name) swap(object_getClass(cls), @selector(sel), (IMP)name##_h, (IMP *)&name##_o)

// id-taking single-argument setters
#define STR_SETTER(name) \
    static void (*name##_o)(id, SEL, id); \
    static void name##_h(id self, SEL _cmd, id v) { name##_o(self, _cmd, TR(v, LEVEL())); }
#define ATTR_SETTER(name) \
    static void (*name##_o)(id, SEL, id); \
    static void name##_h(id self, SEL _cmd, id v) { name##_o(self, _cmd, TRA(v, LEVEL())); }

STR_SETTER(labelText)
ATTR_SETTER(labelAttr)
STR_SETTER(textViewText)
STR_SETTER(vcTitle)
STR_SETTER(navTitle)
STR_SETTER(navPrompt)
STR_SETTER(fieldPlaceholder)
STR_SETTER(searchPlaceholder)
STR_SETTER(barItemTitle)
STR_SETTER(cfgTitle)
STR_SETTER(cfgSubtitle)
STR_SETTER(listText)
STR_SETTER(listSecondary)
STR_SETTER(unavailText)
STR_SETTER(unavailSecondary)
STR_SETTER(actionTitle)
STR_SETTER(actionSubtitle)
STR_SETTER(alertMessage)
STR_SETTER(ctxTitle)

static void (*layerString_o)(id, SEL, id);
static void layerString_h(id self, SEL _cmd, id v) {
    int lv = LEVEL();
    if ([v isKindOfClass:NSString.class]) v = TR(v, lv);
    else if ([v isKindOfClass:NSAttributedString.class]) v = TRA(v, lv);
    layerString_o(self, _cmd, v);
}

static void (*btnTitle_o)(id, SEL, id, UIControlState);
static void btnTitle_h(id self, SEL _cmd, id t, UIControlState st) { btnTitle_o(self, _cmd, TR(t, LEVEL()), st); }
static void (*btnAttr_o)(id, SEL, id, UIControlState);
static void btnAttr_h(id self, SEL _cmd, id t, UIControlState st) { btnAttr_o(self, _cmd, TRA(t, LEVEL()), st); }

static void (*segInsert_o)(id, SEL, id, NSUInteger, BOOL);
static void segInsert_h(id self, SEL _cmd, id t, NSUInteger i, BOOL a) { segInsert_o(self, _cmd, TR(t, LEVEL()), i, a); }
static void (*segSet_o)(id, SEL, id, NSUInteger);
static void segSet_h(id self, SEL _cmd, id t, NSUInteger i) { segSet_o(self, _cmd, TR(t, LEVEL()), i); }

static id (*alertMake_o)(id, SEL, id, id, NSInteger);
static id alertMake_h(id self, SEL _cmd, id t, id m, NSInteger s) { int lv = LEVEL(); return alertMake_o(self, _cmd, TR(t, lv), TR(m, lv), s); }
static id (*alertAction_o)(id, SEL, id, NSInteger, id);
static id alertAction_h(id self, SEL _cmd, id t, NSInteger s, id h) { return alertAction_o(self, _cmd, TR(t, LEVEL()), s, h); }
static id (*uiAction_o)(id, SEL, id, id, id, id);
static id uiAction_h(id self, SEL _cmd, id t, id img, id ident, id h) { return uiAction_o(self, _cmd, TR(t, LEVEL()), img, ident, h); }
static id (*menu2_o)(id, SEL, id, id);
static id menu2_h(id self, SEL _cmd, id t, id ch) { return menu2_o(self, _cmd, TR(t, LEVEL()), ch); }
static id (*menu5_o)(id, SEL, id, id, id, NSUInteger, id);
static id menu5_h(id self, SEL _cmd, id t, id img, id ident, NSUInteger o, id ch) { return menu5_o(self, _cmd, TR(t, LEVEL()), img, ident, o, ch); }
static id (*ctxMake_o)(id, SEL, NSInteger, id, id);
static id ctxMake_h(id self, SEL _cmd, NSInteger s, id t, id h) { return ctxMake_o(self, _cmd, s, TR(t, LEVEL()), h); }
static id (*barInit_o)(id, SEL, id, NSInteger, id, SEL);
static id barInit_h(id self, SEL _cmd, id t, NSInteger s, id tg, SEL a) { return barInit_o(self, _cmd, TR(t, LEVEL()), s, tg, a); }

// Strings PwEevee styles itself before handing them to a Spotify view; only a direct call counts.
static id (*asInit_o)(id, SEL, id, id);
static id asInit_h(id self, SEL _cmd, id s, id at) {
    if (inTweak((uintptr_t)__builtin_return_address(0))) s = TR(s, 2);
    return asInit_o(self, _cmd, s, at);
}
static id (*masInit_o)(id, SEL, id, id);
static id masInit_h(id self, SEL _cmd, id s, id at) {
    if (inTweak((uintptr_t)__builtin_return_address(0))) s = TR(s, 2);
    return masInit_o(self, _cmd, s, at);
}

__attribute__((constructor)) static void TurkishInit(void) {
    @autoreleasepool {
        // The language Spotify draws its own screens in, per-app language setting included.
        if (![NSBundle.mainBundle.preferredLocalizations.firstObject hasPrefix:@"tr"]) return;
        if (!loadDictionary()) return;
        _dyld_register_func_for_add_image(onImage);

        HOOK_I(UILabel.class, setText:, labelText);
        HOOK_I(UILabel.class, setAttributedText:, labelAttr);
        HOOK_I(UITextView.class, setText:, textViewText);
        HOOK_I(UIViewController.class, setTitle:, vcTitle);
        HOOK_I(UINavigationItem.class, setTitle:, navTitle);
        HOOK_I(UINavigationItem.class, setPrompt:, navPrompt);
        HOOK_I(UITextField.class, setPlaceholder:, fieldPlaceholder);
        HOOK_I(UISearchBar.class, setPlaceholder:, searchPlaceholder);
        HOOK_I(UIBarItem.class, setTitle:, barItemTitle);
        HOOK_I(UIButton.class, setTitle:forState:, btnTitle);
        HOOK_I(UIButton.class, setAttributedTitle:forState:, btnAttr);
        HOOK_I(UIButtonConfiguration.class, setTitle:, cfgTitle);
        HOOK_I(UIButtonConfiguration.class, setSubtitle:, cfgSubtitle);
        HOOK_I(UIListContentConfiguration.class, setText:, listText);
        HOOK_I(UIListContentConfiguration.class, setSecondaryText:, listSecondary);
        if (@available(iOS 17.0, *)) {
            HOOK_I(UIContentUnavailableConfiguration.class, setText:, unavailText);
            HOOK_I(UIContentUnavailableConfiguration.class, setSecondaryText:, unavailSecondary);
        }
        HOOK_I(UIAction.class, setTitle:, actionTitle);
        HOOK_I(UIAction.class, setSubtitle:, actionSubtitle);
        HOOK_I(UIAlertController.class, setMessage:, alertMessage);
        HOOK_I(UIContextualAction.class, setTitle:, ctxTitle);
        HOOK_I(UISegmentedControl.class, insertSegmentWithTitle:atIndex:animated:, segInsert);
        HOOK_I(UISegmentedControl.class, setTitle:forSegmentAtIndex:, segSet);
        HOOK_I(UIBarButtonItem.class, initWithTitle:style:target:action:, barInit);
        HOOK_I(CATextLayer.class, setString:, layerString);
        HOOK_C(UIAlertController.class, alertControllerWithTitle:message:preferredStyle:, alertMake);
        HOOK_C(UIAlertAction.class, actionWithTitle:style:handler:, alertAction);
        HOOK_C(UIAction.class, actionWithTitle:image:identifier:handler:, uiAction);
        HOOK_C(UIMenu.class, menuWithTitle:children:, menu2);
        HOOK_C(UIMenu.class, menuWithTitle:image:identifier:options:children:, menu5);
        HOOK_C(UIContextualAction.class, contextualActionWithStyle:title:handler:, ctxMake);
        Class cas = NSClassFromString(@"NSConcreteAttributedString");
        Class cmas = NSClassFromString(@"NSConcreteMutableAttributedString");
        if (cas) HOOK_I(cas, initWithString:attributes:, asInit);
        if (cmas) HOOK_I(cmas, initWithString:attributes:, masInit);
    }
}
