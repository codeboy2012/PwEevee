// Clean shared links (CleanLinks.m): every open.spotify.com link the app puts on the pasteboard or hands to the
// share sheet goes out without its tracking.
//
// Spotify's binary sends -setString:, -setURL:, -setItems:, -setItems:options: and -setData:forPasteboardType:
// to the pasteboard, and builds its share sheet with -initWithActivityItems:applicationActivities: and a
// UIActivityItemProvider of Branch's among others. Which of them "Copy link" takes has not been seen on a
// device, so each way onto the pasteboard is cleaned, the object ones too. Cleaning twice changes nothing, so
// one of them calling another is harmless.
//
// The pasteboard is hooked on _UIConcretePasteboard, not UIPasteboard: every pasteboard UIKit hands out is one,
// and it overrides each setter, so a hook on UIPasteboard's own never ran (simulator, iOS 27).
//
// The switch is read on each copy and share, so it needs no restart. Anything that is not an open.spotify.com
// link -- the mod's own backups and signing pages, images, spotify: URIs -- goes through as it came.
#import "Core/SGCore.h"
#import "Privacy.h"

static BOOL cleaning(void) {
    return SGEnabled(SGKeyCleanLinks);
}

static NSArray *cleanAll(NSArray *objects) {
    if (![objects isKindOfClass:NSArray.class]) return objects;
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:objects.count];
    for (id object in objects) [cleaned addObject:SGCleanLinkObject(object)];
    return cleaned;
}

// Bytes are only read as text under a type that is text or a link; an image is left alone.
static BOOL isTextType(NSString *type) {
    static NSSet<NSString *> *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        types = [NSSet setWithArray:@[@"public.url", @"public.text", @"public.plain-text", @"public.utf8-plain-text"]];
    });
    return [types containsObject:type];
}

static id cleanValue(id value, NSString *type) {
    if (![value isKindOfClass:NSData.class]) return SGCleanLinkObject(value);
    if (!isTextType(type)) return value;
    NSString *text = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    NSString *cleaned = SGCleanLinksInText(text);
    return cleaned == text ? value : [cleaned dataUsingEncoding:NSUTF8StringEncoding];
}

static NSArray<NSDictionary *> *cleanItems(NSArray<NSDictionary *> *items) {
    if (![items isKindOfClass:NSArray.class]) return items;
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class]) {
            [cleaned addObject:item];
            continue;
        }
        NSMutableDictionary *copy = [NSMutableDictionary dictionaryWithCapacity:item.count];
        [item enumerateKeysAndObjectsUsingBlock:^(id type, id value, BOOL *stop) {
            copy[type] = cleanValue(value, type);
        }];
        [cleaned addObject:copy];
    }
    return cleaned;
}

%hook _UIConcretePasteboard
- (void)setString:(NSString *)string {
    %orig(cleaning() ? SGCleanLinksInText(string) : string);
}
- (void)setStrings:(NSArray<NSString *> *)strings {
    %orig(cleaning() ? cleanAll(strings) : strings);
}
- (void)setURL:(NSURL *)url {
    %orig(cleaning() ? SGCleanLinkURL(url) : url);
}
- (void)setURLs:(NSArray<NSURL *> *)urls {
    %orig(cleaning() ? cleanAll(urls) : urls);
}
- (void)setObjects:(NSArray *)objects {
    %orig(cleaning() ? cleanAll(objects) : objects);
}
- (void)setObjects:(NSArray *)objects localOnly:(BOOL)localOnly expirationDate:(NSDate *)date {
    %orig(cleaning() ? cleanAll(objects) : objects, localOnly, date);
}
- (void)setObjects:(NSArray *)objects options:(NSDictionary *)options {
    %orig(cleaning() ? cleanAll(objects) : objects, options);
}
- (void)setItems:(NSArray<NSDictionary *> *)items {
    %orig(cleaning() ? cleanItems(items) : items);
}
- (void)setItems:(NSArray<NSDictionary *> *)items options:(NSDictionary *)options {
    %orig(cleaning() ? cleanItems(items) : items, options);
}
- (void)addItems:(NSArray<NSDictionary *> *)items {
    %orig(cleaning() ? cleanItems(items) : items);
}
- (void)setValue:(id)value forPasteboardType:(NSString *)type {
    %orig(cleaning() ? cleanValue(value, type) : value, type);
}
- (void)setData:(NSData *)data forPasteboardType:(NSString *)type {
    %orig(cleaning() ? cleanValue(data, type) : data, type);
}
%end

#pragma mark - the share sheet

// The method `cls` answers `selector` with, its own or inherited, made to clean what it returns. A provider
// overrides -item rather than the base class answering, so a hook on UIActivityItemProvider would never run:
// each class that reaches the sheet is taken as it comes, once.
static void cleanReturn(Class cls, SEL selector, id (^make)(IMP original)) {
    Method inherited = class_getInstanceMethod(cls, selector);
    if (!inherited) return;
    Method own = nil;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count && !own; i++) {
        if (method_getName(methods[i]) == selector) own = methods[i];
    }
    free(methods);
    IMP original = own ? method_getImplementation(own) : class_getMethodImplementation(class_getSuperclass(cls), selector);
    if (!original) return;
    IMP cleaned = imp_implementationWithBlock(make(original));
    if (own) method_setImplementation(own, cleaned);
    else class_addMethod(cls, selector, cleaned, method_getTypeEncoding(inherited));
}

static void cleanSource(id item) {
    static NSMutableSet<Class> *taken;
    if (!taken) taken = [NSMutableSet set];
    Class cls = object_getClass(item);
    if (!cls || [taken containsObject:cls]) return;
    [taken addObject:cls];

    SEL itemFor = @selector(activityViewController:itemForActivityType:);
    cleanReturn(cls, itemFor, ^id(IMP original) {
        return ^id(id me, UIActivityViewController *sheet, UIActivityType type) {
            id value = ((id (*)(id, SEL, UIActivityViewController *, UIActivityType))original)(me, itemFor, sheet, type);
            return cleaning() ? SGCleanLinkObject(value) : value;
        };
    });
    // A provider's -item runs on a queue of the sheet's, not the main thread: the cleaning is Foundation only.
    if ([item isKindOfClass:UIActivityItemProvider.class]) {
        SEL itemSel = @selector(item);
        cleanReturn(cls, itemSel, ^id(IMP original) {
            return ^id(id me) {
                id value = ((id (*)(id, SEL))original)(me, itemSel);
                return cleaning() ? SGCleanLinkObject(value) : value;
            };
        });
    }
    SGLog(@"privacy: share sheet items of %@ cleaned", NSStringFromClass(cls));
}

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray<UIActivity *> *)activities {
    if (!cleaning() || ![items isKindOfClass:NSArray.class]) return %orig;
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if ([item isKindOfClass:NSString.class] || [item isKindOfClass:NSURL.class]) {
            [cleaned addObject:SGCleanLinkObject(item)];
            continue;
        }
        if ([item conformsToProtocol:@protocol(UIActivityItemSource)]) cleanSource(item);
        [cleaned addObject:item];
    }
    return %orig(cleaned, activities);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_UIConcretePasteboard"]);
}
