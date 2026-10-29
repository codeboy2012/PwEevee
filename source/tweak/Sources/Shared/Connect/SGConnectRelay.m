// The relay of Connect.h. Spotify's multicast query, refused for want of the entitlement, is reported
// sent, and a round on a utility queue sends it by unicast to each receiver Bonjour found, at its mDNS
// port, from a socket of the mod's own per address family. A receiver answers a query from a port other
// than 5353 straight to that port (RFC 6762's legacy unicast), with the query's ID. Each answer that
// checks out is sent on over loopback to the local port of Spotify's socket, and recorded, so that when
// Spotify's recvfrom reads it there the source it is given is the receiver's rather than loopback's.
//
// A round knows Spotify's socket only by its number, its family and its port, read when it starts, so
// Spotify closing the socket halfway does it no harm: the loopback sends then just go nowhere.
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <os/lock.h>
#import <poll.h>
#import <stdatomic.h>
#import <string.h>
#import <time.h>
#import <unistd.h>
#import "Core/SGLog.h"
#import "Connect.h"

ssize_t (*SGConnectRealSendto)(int, const void *, size_t, int, const struct sockaddr *, socklen_t);
ssize_t (*SGConnectRealSendmsg)(int, const struct msghdr *, int);
ssize_t (*SGConnectRealRecvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *);

// A round ends after kRoundLength, after kQuietRoundLength having sent nothing, after kQuietRoundLength
// once nothing has been sent for kSendGap, or after kMaxReplies answers. Answers handed over are kept for
// recvfrom kRecordLife at most, kMaxRecords of them.
static const uint64_t kMillisecond = NSEC_PER_MSEC;
static const uint64_t kRoundLength = 1200 * kMillisecond, kQuietRoundLength = 700 * kMillisecond, kSendGap = 450 * kMillisecond;
static const uint64_t kRecordLife = 15 * NSEC_PER_SEC;
// The same question is relayed for an address family at most once in this long. Spotify asks it from four sockets
// every two seconds or so while it plays, and on a busy Wi-Fi each round brings dozens of answers: with no limit
// the relay passed about fifty a second, keeping the radio awake for a list that changes rarely. A different
// question (a device's own record) is never held back.
static const uint64_t kRepeatGap = 3 * NSEC_PER_SEC;
enum { kMaxRounds = 4, kMaxAddresses = 64, kMaxReplies = 32, kMaxRecords = 64 };

static uint64_t now(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW); }

static os_unfair_lock sg_lock = OS_UNFAIR_LOCK_INIT;

#pragma mark - receivers

static NSMutableDictionary<NSString *, NSArray<NSData *> *> *sg_receivers;

void SGConnectSetReceiver(NSString *name, NSArray<NSData *> *addresses) {
    if (!name) return;
    NSArray<NSData *> *kept = addresses.count ? [addresses copy] : nil;
    os_unfair_lock_lock(&sg_lock);
    if (!sg_receivers) sg_receivers = [NSMutableDictionary dictionary];
    sg_receivers[name] = kept;
    os_unfair_lock_unlock(&sg_lock);
}

NSArray<NSData *> *SGConnectReceiverAddresses(void) {
    NSMutableArray<NSData *> *all = [NSMutableArray array];
    os_unfair_lock_lock(&sg_lock);
    for (NSArray<NSData *> *addresses in sg_receivers.allValues) [all addObjectsFromArray:addresses];
    os_unfair_lock_unlock(&sg_lock);
    return all;
}

#pragma mark - addresses

static socklen_t lengthOf(int family) {
    return family == AF_INET6 ? sizeof(struct sockaddr_in6) : sizeof(struct sockaddr_in);
}

static BOOL sameAddress(const struct sockaddr *a, const struct sockaddr *b) {
    if (a->sa_family != b->sa_family) return NO;
    if (a->sa_family == AF_INET) {
        const struct sockaddr_in *x = (const void *)a, *y = (const void *)b;
        return x->sin_port == y->sin_port && x->sin_addr.s_addr == y->sin_addr.s_addr;
    }
    const struct sockaddr_in6 *x = (const void *)a, *y = (const void *)b;
    // A scope is left out by whoever does not know it; two that are known have to agree.
    BOOL scopes = !x->sin6_scope_id || !y->sin6_scope_id || x->sin6_scope_id == y->sin6_scope_id;
    return x->sin6_port == y->sin6_port && scopes && memcmp(&x->sin6_addr, &y->sin6_addr, sizeof x->sin6_addr) == 0;
}

static BOOL isLoopback(const struct sockaddr *address, socklen_t length) {
    if (address->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        return ((const struct sockaddr_in *)address)->sin_addr.s_addr == htonl(INADDR_LOOPBACK);
    }
    if (address->sa_family != AF_INET6 || length < sizeof(struct sockaddr_in6)) return NO;
    const struct in6_addr *ip = &((const struct sockaddr_in6 *)address)->sin6_addr;
    return IN6_IS_ADDR_LOOPBACK(ip) || (IN6_IS_ADDR_V4MAPPED(ip) && ip->s6_addr[12] == 127 && ip->s6_addr[15] == 1);
}

// 224.0.0.251:5353 or [ff02::fb]:5353.
static BOOL isMDNSGroup(const struct sockaddr *to, socklen_t length) {
    if (!to) return NO;
    if (to->sa_family == AF_INET && length >= sizeof(struct sockaddr_in)) {
        const struct sockaddr_in *v4 = (const void *)to;
        return v4->sin_port == htons(SGMDNSPort) && v4->sin_addr.s_addr == htonl(0xE00000FB);
    }
    if (to->sa_family != AF_INET6 || length < sizeof(struct sockaddr_in6)) return NO;
    const struct sockaddr_in6 *v6 = (const void *)to;
    static const uint8_t group[16] = {0xFF, 0x02, [15] = 0xFB};
    return v6->sin6_port == htons(SGMDNSPort) && memcmp(&v6->sin6_addr, group, sizeof group) == 0;
}

NSString *SGConnectAddressText(const struct sockaddr *address) {
    char text[INET6_ADDRSTRLEN] = "?";
    const void *ip = address->sa_family == AF_INET6 ? (const void *)&((const struct sockaddr_in6 *)address)->sin6_addr
                                                    : (const void *)&((const struct sockaddr_in *)address)->sin_addr;
    inet_ntop(address->sa_family, ip, text, sizeof text);
    return @(text);
}

#pragma mark - answers handed over

typedef struct {
    int socket;
    uint64_t made;
    uint8_t *bytes;
    size_t length;
    struct sockaddr_storage from;
} Record;

static Record sg_records[kMaxRecords];
static int sg_recordCount;
// recvfrom's fast path: nothing to look at unless an answer was handed over in the last kRecordLife.
static _Atomic uint64_t sg_lastRecord;

static void dropRecord(int index) {
    free(sg_records[index].bytes);
    sg_records[index] = sg_records[--sg_recordCount];
}

static void dropExpired(uint64_t time) {
    for (int i = sg_recordCount - 1; i >= 0; i--) {
        if (sg_records[i].made + kRecordLife < time) dropRecord(i); // made may be later than time, from another thread
    }
}

static void handOver(int spotify, const uint8_t *reply, size_t length, const struct sockaddr_storage *from, int sender, const struct sockaddr_storage *loopback) {
    uint8_t *bytes = malloc(length);
    if (!bytes) return;
    memcpy(bytes, reply, length);
    uint64_t time = now();
    os_unfair_lock_lock(&sg_lock);
    dropExpired(time);
    if (sg_recordCount == kMaxRecords) dropRecord(0);
    sg_records[sg_recordCount++] = (Record){spotify, time, bytes, length, *from};
    atomic_store(&sg_lastRecord, time);
    os_unfair_lock_unlock(&sg_lock);

    if (sendto(sender, reply, length, 0, (const struct sockaddr *)loopback, loopback->ss_len) >= 0) {
        // The first few of a launch only: answers come about fifty a second, and a line each filled the log.
        static _Atomic int logged;
        if (atomic_fetch_add(&logged, 1) < 5) SGLog(@"connect: relayed %zu bytes from %@", length, SGConnectAddressText((const struct sockaddr *)from));
        return;
    }
    os_unfair_lock_lock(&sg_lock);
    for (int i = 0; i < sg_recordCount; i++) {
        if (sg_records[i].bytes == bytes) {
            dropRecord(i);
            break;
        }
    }
    os_unfair_lock_unlock(&sg_lock);
}

// The receiver's address in place of loopback's for an answer read on `socket`, in the family the socket
// reported (an IPv4 receiver as ::ffff:a.b.c.d to an IPv6 socket).
static void fixSource(int socket, const void *buffer, size_t length, int flags, struct sockaddr *from, socklen_t *fromLength) {
    struct sockaddr_storage real = {0};
    BOOL found = NO;
    os_unfair_lock_lock(&sg_lock);
    dropExpired(now());
    for (int i = 0; i < sg_recordCount; i++) {
        Record *record = &sg_records[i];
        if (record->socket != socket || record->length != length || memcmp(record->bytes, buffer, length) != 0) continue;
        real = record->from;
        found = YES;
        if (!(flags & MSG_PEEK)) dropRecord(i);
        break;
    }
    os_unfair_lock_unlock(&sg_lock);
    if (!found) return;

    struct sockaddr_storage reported = {0};
    if (from->sa_family == real.ss_family) {
        reported = real;
    } else if (from->sa_family == AF_INET6 && real.ss_family == AF_INET) {
        struct sockaddr_in6 *mapped = (struct sockaddr_in6 *)&reported;
        const struct sockaddr_in *v4 = (const struct sockaddr_in *)&real;
        mapped->sin6_len = sizeof *mapped;
        mapped->sin6_family = AF_INET6;
        mapped->sin6_port = v4->sin_port;
        mapped->sin6_addr.s6_addr[10] = mapped->sin6_addr.s6_addr[11] = 0xFF;
        memcpy(&mapped->sin6_addr.s6_addr[12], &v4->sin_addr, 4);
    } else {
        return;
    }
    socklen_t size = lengthOf(reported.ss_family);
    memcpy(from, &reported, MIN(*fromLength, size));
    *fromLength = size;
}

#pragma mark - rounds

static NSMutableSet<NSData *> *sg_rounds;

static int openSocket(int family) {
    int s = socket(family, SOCK_DGRAM, IPPROTO_UDP);
    if (s < 0) return -1;
    int on = 1;
    setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    if (family == AF_INET6) setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &on, sizeof on);
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    return s;
}

static void runRound(int spotify, int family, in_port_t port, NSData *query) {
    // An IPv4 socket cannot be told an IPv6 source, so it hears from IPv4 receivers only.
    int sockets[2] = {openSocket(AF_INET), family == AF_INET6 ? openSocket(AF_INET6) : -1};
    int sender = sockets[family == AF_INET6];
    struct sockaddr_storage loopback = {0};
    if (family == AF_INET6) {
        struct sockaddr_in6 *to = (struct sockaddr_in6 *)&loopback;
        *to = (struct sockaddr_in6){.sin6_len = sizeof *to, .sin6_family = AF_INET6, .sin6_port = port, .sin6_addr = in6addr_loopback};
    } else {
        struct sockaddr_in *to = (struct sockaddr_in *)&loopback;
        *to = (struct sockaddr_in){.sin_len = sizeof *to, .sin_family = AF_INET, .sin_port = port, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    }

    const uint8_t *bytes = query.bytes;
    uint16_t queryID = (uint16_t)(bytes[0] << 8 | bytes[1]);
    struct sockaddr_storage sent[kMaxAddresses];
    int sentCount = 0, replies = 0;
    uint64_t start = now(), lastSend = 0;
    uint8_t buffer[SGMDNSMaxLength + 1];

    while (sender >= 0) {
        // Receivers resolved while the round runs are sent to as well.
        for (NSData *address in SGConnectReceiverAddresses()) {
            if (sentCount == kMaxAddresses) break;
            const struct sockaddr *to = address.bytes;
            if (address.length < lengthOf(to->sa_family)) continue;
            int s = sockets[to->sa_family == AF_INET6];
            BOOL known = NO;
            for (int i = 0; i < sentCount && !known; i++) known = sameAddress((const struct sockaddr *)&sent[i], to);
            if (s < 0 || known) continue;
            memcpy(&sent[sentCount++], to, lengthOf(to->sa_family));
            if (sendto(s, bytes, query.length, 0, to, lengthOf(to->sa_family)) >= 0) lastSend = now();
        }

        uint64_t time = now(), elapsed = time - start;
        if (elapsed >= kRoundLength || replies >= kMaxReplies) break;
        if (elapsed >= kQuietRoundLength && (!lastSend || time - lastSend >= kSendGap)) break;

        struct pollfd ready[2] = {{sockets[0], POLLIN, 0}, {sockets[1], POLLIN, 0}};
        if (poll(ready, 2, 50) <= 0) continue;
        for (int k = 0; k < 2; k++) {
            if (!(ready[k].revents & POLLIN)) continue;
            while (replies < kMaxReplies) {
                struct sockaddr_storage from = {0};
                struct iovec part = {buffer, sizeof buffer};
                struct msghdr message = {.msg_name = &from, .msg_namelen = sizeof from, .msg_iov = &part, .msg_iovlen = 1};
                ssize_t length = recvmsg(sockets[k], &message, 0);
                if (length < 0) break;
                if (message.msg_flags & MSG_TRUNC || length > SGMDNSMaxLength) continue;
                BOOL known = NO;
                for (int i = 0; i < sentCount && !known; i++) known = sameAddress((const struct sockaddr *)&sent[i], (const struct sockaddr *)&from);
                if (!known || !SGMDNSIsConnectReply(buffer, (size_t)length, queryID)) continue;
                replies++;
                handOver(spotify, buffer, (size_t)length, &from, sender, &loopback);
            }
        }
    }
    for (int k = 0; k < 2; k++) {
        if (sockets[k] >= 0) close(sockets[k]);
    }
}

BOOL SGConnectRelayQuery(int socket, const void *query, size_t length) {
    int type = 0;
    socklen_t typeLength = sizeof type;
    if (getsockopt(socket, SOL_SOCKET, SO_TYPE, &type, &typeLength) != 0 || type != SOCK_DGRAM) return NO;
    struct sockaddr_storage address;
    socklen_t addressLength = sizeof address;
    if (getpeername(socket, (struct sockaddr *)&address, &addressLength) == 0 || errno != ENOTCONN) return NO;
    addressLength = sizeof address;
    if (getsockname(socket, (struct sockaddr *)&address, &addressLength) != 0) return NO;
    in_port_t port;
    if (address.ss_family == AF_INET) port = ((struct sockaddr_in *)&address)->sin_port;
    else if (address.ss_family == AF_INET6) port = ((struct sockaddr_in6 *)&address)->sin6_port;
    else return NO;
    if (!port) return NO;

    NSData *bytes = [NSData dataWithBytes:query length:length];
    NSMutableData *key = [NSMutableData dataWithBytes:&socket length:sizeof socket];
    [key appendData:bytes];
    os_unfair_lock_lock(&sg_lock);
    if (!sg_rounds) sg_rounds = [NSMutableSet set];
    BOOL start = sg_rounds.count < kMaxRounds && ![sg_rounds containsObject:key];
    if (start) [sg_rounds addObject:key];
    os_unfair_lock_unlock(&sg_lock);
    if (!start) return YES;

    int family = address.ss_family;
    // Counted, and said once a minute, so the limit's effect shows in the log.
    static uint64_t ran, skipped, countedFrom;
    static NSMutableDictionary<NSData *, NSNumber *> *lastRun;
    uint64_t time = now();
    os_unfair_lock_lock(&sg_lock);
    if (!lastRun) lastRun = [NSMutableDictionary dictionary];
    // The question for its address family, whatever socket asked it: Spotify sends the same query from two sockets
    // of each family every two seconds or so, and each started a round of its own to every receiver.
    NSMutableData *question = [NSMutableData dataWithBytes:&family length:sizeof family];
    if (length > 2) [question appendBytes:(const uint8_t *)query + 2 length:length - 2];
    uint64_t was = [lastRun[question] unsignedLongLongValue];
    BOOL allowed = !was || time - was >= kRepeatGap;
    if (allowed) {
        lastRun[question] = @(time);
        ran++;
    } else {
        skipped++;
        [sg_rounds removeObject:key];
    }
    uint64_t saidRan = 0, saidSkipped = 0;
    BOOL say = NO;
    if (!countedFrom) countedFrom = time;
    else if (time - countedFrom >= 60 * NSEC_PER_SEC) {
        say = YES;
        saidRan = ran, saidSkipped = skipped;
        ran = skipped = 0;
        countedFrom = time;
        // Questions not asked in the last minute are forgotten.
        for (NSData *old in lastRun.allKeys) if (time - lastRun[old].unsignedLongLongValue >= 60 * NSEC_PER_SEC) [lastRun removeObjectForKey:old];
    }
    os_unfair_lock_unlock(&sg_lock);
    if (say) SGLog(@"connect: %llu rounds and %llu repeats held back in the last minute", saidRan, saidSkipped);
    if (!allowed) return YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        runRound(socket, family, port, bytes);
        os_unfair_lock_lock(&sg_lock);
        [sg_rounds removeObject:key];
        os_unfair_lock_unlock(&sg_lock);
    });
    return YES;
}

#pragma mark - the replacements

// The errors a send to the multicast group meets without the entitlement.
static BOOL refusedMulticast(int error) {
    return error == EACCES || error == EPERM || error == ENETUNREACH || error == EHOSTUNREACH || error == EADDRNOTAVAIL;
}

ssize_t SGConnectSendto(int socket, const void *buffer, size_t length, int flags, const struct sockaddr *to, socklen_t toLength) {
    ssize_t sent = (SGConnectRealSendto ?: sendto)(socket, buffer, length, flags, to, toLength);
    if (sent >= 0) return sent;
    int error = errno;
    BOOL relayed = refusedMulticast(error) && isMDNSGroup(to, toLength) && SGMDNSIsConnectQuery(buffer, length)
        && SGConnectRelayQuery(socket, buffer, length);
    errno = error;
    return relayed ? (ssize_t)length : sent;
}

// The message's parts gathered and relayed: their length, or -1. Out of line, so the buffer is no part
// of the frame of every sendmsg Spotify makes.
__attribute__((noinline)) static ssize_t relayMessage(int socket, const struct msghdr *message) {
    uint8_t packet[SGMDNSMaxLength];
    size_t length = 0;
    for (int i = 0; i < message->msg_iovlen; i++) {
        const struct iovec *part = &message->msg_iov[i];
        if (part->iov_len > sizeof packet - length) return -1;
        if (part->iov_len) memcpy(packet + length, part->iov_base, part->iov_len);
        length += part->iov_len;
    }
    return SGMDNSIsConnectQuery(packet, length) && SGConnectRelayQuery(socket, packet, length) ? (ssize_t)length : -1;
}

ssize_t SGConnectSendmsg(int socket, const struct msghdr *message, int flags) {
    ssize_t sent = (SGConnectRealSendmsg ?: sendmsg)(socket, message, flags);
    if (sent >= 0 || !message || !message->msg_iov) return sent;
    int error = errno;
    ssize_t relayed = refusedMulticast(error) && isMDNSGroup(message->msg_name, message->msg_namelen) ? relayMessage(socket, message) : -1;
    errno = error;
    return relayed >= 0 ? relayed : sent;
}

ssize_t SGConnectRecvfrom(int socket, void *buffer, size_t length, int flags, struct sockaddr *from, socklen_t *fromLength) {
    ssize_t received = (SGConnectRealRecvfrom ?: recvfrom)(socket, buffer, length, flags, from, fromLength);
    if (received < 0 || !from || !fromLength || !buffer) return received;
    uint64_t last = atomic_load(&sg_lastRecord);
    if (!last || now() - last > kRecordLife) return received;
    int error = errno;
    if (isLoopback(from, *fromLength)) fixSource(socket, buffer, (size_t)received, flags, from, fromLength);
    errno = error;
    return received;
}
