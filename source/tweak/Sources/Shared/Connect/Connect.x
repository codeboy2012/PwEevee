// Connect receivers found with Bonjour for the relay (Connect.h), and Spotify's imports of sendto,
// sendmsg and recvfrom rebound to it. The browse runs from launch on the main thread, so the receivers
// are known by the time Spotify asks; each one found is resolved to its addresses, kept with the mDNS
// port in place of the service's own, and forgotten when Bonjour says it went.
#import <arpa/inet.h>
#import <netinet/in.h>
#import "Core/SGLog.h"
#import "Core/SGRebind.h"
#import "Connect.h"

// A resolve that fails or finds nothing to send to is tried again kFirstRetry later, doubling up to
// kLastRetry; a browse that fails starts again after kBrowseRetry.
static const NSTimeInterval kResolveTimeout = 5, kFirstRetry = 2, kLastRetry = 30, kBrowseRetry = 3;

// The address with the mDNS port, or nil for one no query can go to: unspecified, loopback, multicast.
static NSData *queryAddress(NSData *data) {
    if (data.length >= sizeof(struct sockaddr_in) && ((const struct sockaddr *)data.bytes)->sa_family == AF_INET) {
        struct sockaddr_in v4;
        memcpy(&v4, data.bytes, sizeof v4);
        uint32_t ip = ntohl(v4.sin_addr.s_addr);
        if (ip == INADDR_ANY || ip >> 24 == IN_LOOPBACKNET || IN_MULTICAST(ip)) return nil;
        v4.sin_len = sizeof v4;
        v4.sin_port = htons(SGMDNSPort);
        return [NSData dataWithBytes:&v4 length:sizeof v4];
    }
    if (data.length >= sizeof(struct sockaddr_in6) && ((const struct sockaddr *)data.bytes)->sa_family == AF_INET6) {
        struct sockaddr_in6 v6;
        memcpy(&v6, data.bytes, sizeof v6);
        if (IN6_IS_ADDR_UNSPECIFIED(&v6.sin6_addr) || IN6_IS_ADDR_LOOPBACK(&v6.sin6_addr) || IN6_IS_ADDR_MULTICAST(&v6.sin6_addr)) return nil;
        v6.sin6_len = sizeof v6;
        v6.sin6_port = htons(SGMDNSPort);
        return [NSData dataWithBytes:&v6 length:sizeof v6];
    }
    return nil;
}

@interface SGConnectBrowser : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
- (void)start;
@end

@implementation SGConnectBrowser {
    NSNetServiceBrowser *_browser;
    NSMutableDictionary<NSString *, NSNetService *> *_services;
    NSMutableDictionary<NSString *, NSNumber *> *_retries;
}

- (void)start {
    _services = [NSMutableDictionary dictionary];
    _retries = [NSMutableDictionary dictionary];
    _browser = [NSNetServiceBrowser new];
    _browser.delegate = self;
    [_browser searchForServicesOfType:@"_spotify-connect._tcp." inDomain:@"local."];
}

- (void)forget:(NSString *)name {
    NSNetService *service = _services[name];
    service.delegate = nil;
    [service stop];
    [_services removeObjectForKey:name];
    [_retries removeObjectForKey:name];
    SGConnectSetReceiver(name, nil);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    if (_services[service.name] == service) return;
    [self forget:service.name];
    _services[service.name] = service;
    service.delegate = self;
    [service resolveWithTimeout:kResolveTimeout];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    [self forget:service.name];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary<NSString *, NSNumber *> *)error {
    SGLog(@"connect: Bonjour browse failed (%@), again in %.0f s", error[NSNetServicesErrorCode], kBrowseRetry);
    _browser.delegate = nil;
    [_browser stop];
    for (NSString *name in _services.allKeys) [self forget:name];
    __weak SGConnectBrowser *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBrowseRetry * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf start];
    });
}

// Called again as more of a receiver's addresses come in, each time with all of them.
- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (_services[service.name] != service) return;
    NSMutableArray<NSData *> *addresses = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSData *data in service.addresses) {
        NSData *address = queryAddress(data);
        if (!address || [addresses containsObject:address]) continue;
        [addresses addObject:address];
        [texts addObject:SGConnectAddressText(address.bytes)];
    }
    if (!addresses.count) {
        [self retry:service];
        return;
    }
    [_retries removeObjectForKey:service.name];
    SGConnectSetReceiver(service.name, addresses);
    SGLog(@"connect: %@ at %@", service.name, [texts componentsJoinedByString:@", "]);
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary<NSString *, NSNumber *> *)error {
    if (_services[service.name] == service) [self retry:service];
}

- (void)retry:(NSNetService *)service {
    NSString *name = service.name;
    NSNumber *last = _retries[name];
    NSTimeInterval delay = last ? MIN(last.doubleValue * 2, kLastRetry) : kFirstRetry;
    _retries[name] = @(delay);
    __weak SGConnectBrowser *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGConnectBrowser *browser = weakSelf;
        if (!browser || browser->_services[name] != service) return;
        [service stop];
        [service resolveWithTimeout:kResolveTimeout];
    });
}

@end

static SGConnectBrowser *sg_browser;

%ctor {
    // recvfrom first: without it the receivers' answers would reach Spotify from loopback, so nothing
    // is relayed at all.
    if (!SGRebindImport("recvfrom", SGConnectRecvfrom, (void **)&SGConnectRealRecvfrom) || !SGConnectRealRecvfrom) {
        SGLog(@"connect: Spotify does not import recvfrom, Connect discovery is Spotify's own");
        return;
    }
    BOOL sends = SGRebindImport("sendto", SGConnectSendto, (void **)&SGConnectRealSendto);
    BOOL messages = SGRebindImport("sendmsg", SGConnectSendmsg, (void **)&SGConnectRealSendmsg);
    if (!sends && !messages) {
        SGLog(@"connect: Spotify imports neither sendto nor sendmsg, Connect discovery is Spotify's own");
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_browser = [SGConnectBrowser new];
        [sg_browser start];
    });
}
