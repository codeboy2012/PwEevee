#import "Core/SGCore.h"
#import "Diagnostics.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

static const uint16_t kTreePort = 8085;

static NSString *hexColor(CGColorRef color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [[UIColor colorWithCGColor:color] getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X@%.2f", (int)(r * 255), (int)(g * 255), (int)(b * 255), a];
}

static void appendTree(UIView *view, NSUInteger depth, NSMutableString *out) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%*s%@ %@", (int)depth * 2, "", NSStringFromClass(view.class), NSStringFromCGRect(view.frame)];
    CGColorRef bg = view.layer.backgroundColor;
    if (bg && CGColorGetAlpha(bg) > 0) [line appendFormat:@" bg=%@", hexColor(bg)];
    if (view.layer.cornerRadius > 0) [line appendFormat:@" r=%.1f", view.layer.cornerRadius];
    if (view.alpha < 1) [line appendFormat:@" a=%.2f", view.alpha];
    if (view.hidden) [line appendString:@" hidden"];
    if (view.layer.mask) [line appendString:@" masked"];
    if (view.clipsToBounds) [line appendString:@" clips"];
    if (view.accessibilityIdentifier.length) [line appendFormat:@" id=%@", view.accessibilityIdentifier];
    if ([view isKindOfClass:UIControl.class] && view.accessibilityLabel.length) [line appendFormat:@" a11y=\"%@\"", view.accessibilityLabel];
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        [line appendFormat:@" \"%@\" %.0fpt %@", label.text, label.font.pointSize, hexColor(label.textColor.CGColor)];
    }
    if ([view isKindOfClass:UIImageView.class] && ((UIImageView *)view).image) {
        CGSize size = ((UIImageView *)view).image.size;
        [line appendFormat:@" img=%.0fx%.0f", size.width, size.height];
    }
    [out appendString:line];
    [out appendString:@"\n"];
    for (UIView *sub in view.subviews) appendTree(sub, depth + 1, out);
}

BOOL SGIsDebugBuild(void) {
    return NSClassFromString(@"FLEXManager") != nil;
}

static NSString *describeValue(id value) {
    if ([value isKindOfClass:NSArray.class] || [value isKindOfClass:NSDictionary.class]) {
        return [NSString stringWithFormat:@"%@%lu", [value isKindOfClass:NSArray.class] ? @"list:" : @"map:", (unsigned long)[value count]];
    }
    if ([value isKindOfClass:NSString.class]) {
        NSString *text = value;
        return [NSString stringWithFormat:@"\"%@\"", text.length > 40 ? [[text substringToIndex:40] stringByAppendingString:@"…"] : text];
    }
    return [value description];
}

static void appendModState(NSMutableString *out) {
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{};
    [out appendFormat:@"== mod\nstock %@\n", [stored[SGKeyStock] boolValue] ? @"yes" : @"no"];
    NSArray<NSString *> *local = @[@"spotifyglass.adblock.counts", @"spotifyglass.privacy.counts", @"spotifyglass.update.",
                                   @"spotifyglass.signing.", @"spotifyglass.onboarding.", @"spotifyglass.navbar.stock", @"spotifyglass.redesign.navbar.stock",
                                   @"spotifyglass.musixmatch.token"];
    for (NSString *key in [stored.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        if (![key hasPrefix:@"spotifyglass."] || [key isEqualToString:SGKeyStock]) continue;
        BOOL skip = NO;
        for (NSString *prefix in local) skip |= [key hasPrefix:prefix];
        if (!skip) [out appendFormat:@"%@ = %@\n", key, describeValue(stored[key])];
    }
}

NSString *SGScreenTree(void) {
    NSMutableString *out = [NSMutableString string];
    UIViewController *root = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || [NSStringFromClass(window.class) containsString:@"FLEX"]) continue;
            if (!root || window.isKeyWindow) root = window.rootViewController;
            [out appendFormat:@"== window %@ level %.0f\n", window.class, window.windowLevel];
            appendTree(window, 0, out);
        }
    }
    if ([root respondsToSelector:@selector(_printHierarchy)]) {
        [out appendFormat:@"== view controllers\n%@\n", [root _printHierarchy]];
    }
    appendModState(out);
    return out;
}

void SGDumpScreen(NSString *reason) {
    SGLogLong([@"screen dump " stringByAppendingString:reason], SGScreenTree());
}

// GET anything on 127.0.0.1:kTreePort answers with the current screen's tree as text/plain.
static void sendAll(int client, NSData *data) {
    const uint8_t *p = data.bytes;
    size_t left = data.length;
    while (left > 0) {
        ssize_t n = send(client, p, left, 0);
        if (n <= 0) return;
        p += n;
        left -= (size_t)n;
    }
}

static void startTreeServer(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(kTreePort);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(fd, 4) != 0) {
        SGLog(@"tree server: could not listen on %u", kTreePort);
        close(fd);
        return;
    }
    static dispatch_source_t source;
    source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        struct timeval timeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        char request[1024];
        recv(client, request, sizeof(request), 0);
        __block NSString *body = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{ body = SGScreenTree(); });
        NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
        NSString *head = [NSString stringWithFormat:@"HTTP/1.0 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)data.length];
        sendAll(client, [head dataUsingEncoding:NSUTF8StringEncoding]);
        sendAll(client, data);
        close(client);
    });
    dispatch_resume(source);
    SGLog(@"tree server on 127.0.0.1:%u; on the Mac: iproxy %u:%u, then GET http://127.0.0.1:%u/tree", kTreePort, kTreePort, kTreePort, kTreePort);
}

%hook _TtC21NowPlaying_ScrollImpl23NPVScrollViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!SGIsDebugBuild()) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGDumpScreen(@"now playing view");
        });
    });
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC21NowPlaying_ScrollImpl23NPVScrollViewController"]);
    SGLog(@"loaded, UIGlassEffect %@", NSClassFromString(@"UIGlassEffect") ? @"available" : @"missing");
    if (SGIsDebugBuild()) {
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            SGDumpScreen(@"on background");
        }];
        startTreeServer();
        SGLog(@"debug build: backgrounding the app dumps the visible screen's view tree");
    }
}
