#import "Core/SGCore.h"
#import "Headers/SPTLinkDispatcherImplementation.h"
#import "Links.h"
#import <objc/message.h>
#import <objc/runtime.h>

static __weak SPTLinkDispatcherImplementation *sg_linkDispatcher;

id SGLinkDispatcher(void) {
    return sg_linkDispatcher;
}

static id sg_send(id target, NSString *selector);

// A real link context stolen from Spotify's own flow. Filling context: with nil is a
// proven segfault (swift_getObjectType on 0x0), so the mod only goes in-process once
// Spotify has opened a link for itself and the hook below captured a live context.
static __strong id sg_realContext;

BOOL SGOpenSpotifyURI(NSURL *uri) {
    // Spotify's navigate entry moved out of ObjC reach in 9.1.90: its reason argument is
    // a Swift enum that nil/zero segfaults. But the already-hooked link dispatcher
    // exposes uriSchemeDispatcher, whose handleURI:context: is the same front door every
    // in-app spotify: link takes - ObjC-callable, BOOL-answering, nil context tolerated.
    SPTLinkDispatcherImplementation *dispatcher = sg_linkDispatcher;
    if (!uri || !dispatcher) return NO;
    id schemeDispatcher = sg_send(dispatcher, @"uriSchemeDispatcher");
    SEL handle = NSSelectorFromString(@"handleURI:context:");
    if (schemeDispatcher && [schemeDispatcher respondsToSelector:handle]) {
        NSURL *clean = sg_send(uri, @"spt_normalizedSpotifyURI");
        if (![clean isKindOfClass:NSURL.class]) clean = uri;
        // nil context aliases a segfault inside the dispatcher's own Swift guts, so
        // without a captured one the call is skipped and the fallback runs instead.
        if ([clean isKindOfClass:NSURL.class] && sg_realContext) {
            @try {
                BOOL opened = ((BOOL (*)(id, SEL, id, id))objc_msgSend)(schemeDispatcher, handle, clean, sg_realContext);
                SGLog(@"links: scheme dispatcher handleURI %@ ctx %@ -> %@", clean.absoluteString,
                    NSStringFromClass([sg_realContext class]), opened ? @"YES" : @"NO");
                if (opened) return YES;
            } @catch (NSException *e) {
                SGLog(@"links: scheme dispatcher threw %@", e.reason);
            }
        }
    }
    // Untouched fallback: iOS hands the spotify: link back to this app and Spotify runs
    // it through its own dispatcher with a reason it composed itself - which the scheme
    // dispatcher hook then captures for every later in-process open.
    [[UIApplication sharedApplication] openURL:uri options:@{} completionHandler:NULL];
    SGLog(@"links: opened via the system deep link");
    return YES;
}

// The navigate entry point has moved between Spotify majors; keep the actual list in the log
// so the next rename is a log read, not a crash hunt.
static void logDispatcherMethods(id dispatcher) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        unsigned count = 0;
        Method *methods = class_copyMethodList(object_getClass(dispatcher), &count);
        if (!methods) return;
        NSMutableString *list = [[NSString stringWithFormat:@"dispatcher methods (%u):", count] mutableCopy];
        for (unsigned i = 0; i < count; i++)
            [list appendFormat:@"\n  %s %s", sel_getName(method_getName(methods[i])),
                method_getTypeEncoding(methods[i])];
        free(methods);
        SGLogLong(@"links", list);
    });
}

#pragma mark - asking before opening

static void logDispatcherMethods(id dispatcher);

static id sg_send(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(target, sel);
}

static id sg_send1(id target, NSString *selector, id arg) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(target, sel, arg);
}

static NSString *takerFor(id<NSFastEnumeration> handlers, NSURL *uri, NSUInteger *asked) {
    SEL canHandle = NSSelectorFromString(@"URISubtypeHandlerCanHandleURI:");
    for (id handler in handlers) {
        NSString *name = NSStringFromClass([handler class]);
        if ([name containsString:@"EventSource"] || ![handler respondsToSelector:canHandle]) continue;
        (*asked)++;
        if (((BOOL (*)(id, SEL, id))objc_msgSend)(handler, canHandle, uri)) return name;
    }
    return nil;
}

SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via) {
    if (via) *via = nil;
    if (!uri) return SGLinkRouteNone;
    id linkHandler = sg_send(sg_linkDispatcher, @"spotifyLinkHandler");
    id handlers = sg_send(sg_send(linkHandler, @"URISubtypeRegistry"), @"handlers");
    if (![handlers conformsToProtocol:@protocol(NSFastEnumeration)]) return SGLinkRouteUnknown;
    @try {
        NSURL *clean = sg_send(uri, @"spt_normalizedSpotifyURI");
        if (![clean isKindOfClass:NSURL.class]) clean = uri;
        NSUInteger asked = 0;
        NSString *taker = takerFor(handlers, clean, &asked);
        if (!taker) {
            NSURL *remapped = sg_send1(linkHandler, @"remapURI:", clean);
            if ([remapped isKindOfClass:NSURL.class] && ![remapped isEqual:clean]) {
                taker = takerFor(handlers, remapped, &asked);
                if (taker) taker = [NSString stringWithFormat:@"remap %@ %@", remapped.absoluteString, taker];
            }
        }
        if (!asked) return SGLinkRouteUnknown;
        if (via) *via = taker;
        return taker ? SGLinkRouteOpens : SGLinkRouteNone;
    } @catch (NSException *e) {
        SGLog(@"links: asking about %@ threw %@", uri, e.reason);
        return SGLinkRouteUnknown;
    }
}

NSURL *SGSpotifyURIFromText(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return nil;
    NSURLComponents *parts = [NSURLComponents componentsWithString:trimmed];
    NSString *host = parts.host.lowercaseString;
    if ([parts.scheme.lowercaseString hasPrefix:@"http"] && [host isEqualToString:@"open.spotify.com"]) {
        NSMutableArray<NSString *> *path = [NSMutableArray array];
        for (NSString *piece in [parts.path componentsSeparatedByString:@"/"]) {
            if (piece.length) [path addObject:piece];
        }
        if (path.count && [path.firstObject hasPrefix:@"intl-"]) [path removeObjectAtIndex:0];
        if (path.count >= 2) return [NSURL URLWithString:[@"spotify:" stringByAppendingString:[path componentsJoinedByString:@":"]]];
    }
    return [NSURL URLWithString:trimmed];
}

%hook SPTLinkDispatcherImplementation
- (void)setMainUILoaded:(BOOL)loaded {
    %orig;
    sg_linkDispatcher = (SPTLinkDispatcherImplementation *)self;
    logDispatcherMethods(self);
}
%end

// Transparent capture of the context Spotify composes for its own link flows; the
// stored object is reused as the context: argument for the mod's own in-process opens.
%hook SPTURISchemeDispatcher
- (BOOL)handleURI:(NSURL *)uri context:(id)context {
    if (context) {
        sg_realContext = context;
        SGLog(@"links: captured link context %@ (%@)", context, NSStringFromClass([context class]));
    }
    return %orig;
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"SPTLinkDispatcherImplementation"]);
}
