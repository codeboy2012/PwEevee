// The mDNS packet checks of Connect.h, in plain C over the bytes as they came: every read is checked
// against the packet's end, a name follows at most 32 compression pointers, and a name is matched by
// its labels, since an instance name may itself hold dots.
#import <strings.h>
#import "Connect.h"

enum { kHeader = 12, kMaxQuestions = 40, kMaxRecords = 400, kMaxLabels = 128, kMaxHops = 32 };

static uint16_t read16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }

typedef struct {
    const uint8_t *label[kMaxLabels];
    uint8_t length[kMaxLabels];
    size_t count;
} Name;

// Reads the name at *offset into `name` and moves *offset past it, which for a compressed name is past
// its first pointer. NO for a name that runs off the packet, loops, or is longer than DNS allows.
static BOOL readName(const uint8_t *packet, size_t length, size_t *offset, Name *name) {
    size_t at = *offset, end = 0, total = 0, hops = 0;
    BOOL jumped = NO;
    name->count = 0;
    while (YES) {
        if (at >= length) return NO;
        uint8_t byte = packet[at];
        if ((byte & 0xC0) == 0xC0) {
            if (at + 1 >= length || ++hops > kMaxHops) return NO;
            if (!jumped) end = at + 2;
            jumped = YES;
            at = (size_t)(byte & 0x3F) << 8 | packet[at + 1];
            continue;
        }
        if (byte & 0xC0) return NO; // the 0x40 and 0x80 label types are not in use
        if (byte == 0) {
            if (!jumped) end = at + 1;
            break;
        }
        total += byte + 1;
        if (at + 1 + byte > length || total > 255 || name->count == kMaxLabels) return NO;
        name->label[name->count] = packet + at + 1;
        name->length[name->count++] = byte;
        at += 1 + byte;
    }
    *offset = end;
    return YES;
}

static BOOL labelIs(const Name *name, size_t fromEnd, const char *text) {
    size_t index = name->count - 1 - fromEnd, length = strlen(text);
    return name->length[index] == length && strncasecmp((const char *)name->label[index], text, length) == 0;
}

// _spotify-connect._tcp.local, or a name under it (an instance, a subtype).
static BOOL isConnectName(const Name *name) {
    return name->count >= 3 && labelIs(name, 0, "local") && labelIs(name, 1, "_tcp") && labelIs(name, 2, "_spotify-connect");
}

BOOL SGMDNSIsConnectQuery(const uint8_t *packet, size_t length) {
    if (!packet || length < kHeader || length > SGMDNSMaxLength) return NO;
    uint16_t flags = read16(packet + 2), questions = read16(packet + 4);
    if (flags & 0x8000 || (flags >> 11 & 0xF) != 0 || questions == 0 || questions > kMaxQuestions) return NO;
    size_t offset = kHeader;
    BOOL connect = NO;
    for (uint16_t i = 0; i < questions; i++) {
        Name name;
        if (!readName(packet, length, &offset, &name) || offset + 4 > length) return NO;
        offset += 4;
        connect = connect || isConnectName(&name);
    }
    return connect;
}

BOOL SGMDNSIsConnectReply(const uint8_t *packet, size_t length, uint16_t queryID) {
    if (!packet || length < kHeader || length > SGMDNSMaxLength || read16(packet) != queryID) return NO;
    uint16_t flags = read16(packet + 2);
    // QR set, opcode 0, TC clear, RCODE 0.
    if (!(flags & 0x8000) || (flags >> 11 & 0xF) != 0 || flags & 0x0200 || (flags & 0xF) != 0) return NO;
    size_t questions = read16(packet + 4);
    size_t records = (size_t)read16(packet + 6) + read16(packet + 8) + read16(packet + 10);
    if (questions > kMaxQuestions || records == 0 || records > kMaxRecords) return NO;
    size_t offset = kHeader;
    Name name;
    for (size_t i = 0; i < questions; i++) {
        if (!readName(packet, length, &offset, &name) || offset + 4 > length) return NO;
        offset += 4;
    }
    BOOL connect = NO;
    for (size_t i = 0; i < records; i++) {
        if (!readName(packet, length, &offset, &name) || offset + 10 > length) return NO;
        // The top bit of the class is mDNS's cache flush.
        uint16_t type = read16(packet + offset);
        BOOL in = (read16(packet + offset + 2) & 0x7FFF) == 1;
        size_t data = offset + 10, dataLength = read16(packet + offset + 8);
        if (data + dataLength > length) return NO;
        if (in && isConnectName(&name)) connect = YES;
        if (type == 12) {
            size_t target = data;
            Name pointed;
            if (!readName(packet, length, &target, &pointed) || target > data + dataLength) return NO;
            if (in && isConnectName(&pointed)) connect = YES;
        }
        offset = data + dataLength;
    }
    return connect;
}
