#import "SGAudioSourceQueue.h"
#import "Core/SGLog.h"
#import <mach/mach.h>
#import <mach-o/dyld.h>
#include <string.h>
#include <stdbool.h>
#include <stdatomic.h>

static uintptr_t sg_sourceImage;
static bool sg_sourceLayout;
static bool sg_sourceSpotify90;
static atomic_bool sg_sourceProbeLogged;
static NSString *probeWords(const uint64_t *words, NSUInteger count) {
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < count; i++)
        [result appendFormat:@"%@%02lu=%016llx", i ? @" " : @"",
                              (unsigned long)(i * sizeof(uint64_t)),
                              (unsigned long long)words[i]];
    return result;
}
static bool readMetadata(uintptr_t address, void *value, size_t size) {
    vm_size_t count = 0;
    return address && address <= UINTPTR_MAX - size &&
        vm_read_overwrite(mach_task_self(), address, size, (vm_address_t)value, &count) == KERN_SUCCESS && count == size;
}
static bool readWord(uintptr_t address, uint64_t *value) {
    *value = 0;
    return readMetadata(address, value, sizeof *value);
}
void SGAudioSourceQueueInitialize(void) {
    // 9.1.90 is identified only for diagnostics; its private queue ABI is not verified.
    static const unsigned char uuid9178[16] = {0xc7,0x12,0x37,0x0b,0x44,0xcd,0x35,0xc8,0xa0,0x58,0x4f,0xbe,0xd1,0xad,0x07,0x58};
    static const unsigned char uuid9190[16] = {0xfb,0xce,0x22,0xc1,0x7e,0x1b,0x3e,0x0d,0x9b,0xe8,0x66,0xff,0x92,0x91,0x94,0x3e};
    sg_sourceImage = 0;
    sg_sourceLayout = false;
    sg_sourceSpotify90 = false;
    atomic_store(&sg_sourceProbeLogged, false);
    const struct mach_header_64 *header = (const void *)_dyld_get_image_header(0);
    if (!header || header->magic != MH_MAGIC_64) return;
    const struct load_command *command = (const void *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const void *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_UUID && command->cmdsize == sizeof(struct uuid_command)) {
            const unsigned char *uuid = ((const struct uuid_command *)command)->uuid;
            if (memcmp(uuid, uuid9178, sizeof uuid9178) && memcmp(uuid, uuid9190, sizeof uuid9190)) continue;
            sg_sourceImage = (uintptr_t)header;
            sg_sourceLayout = !memcmp(uuid, uuid9178, sizeof uuid9178);
            sg_sourceSpotify90 = !memcmp(uuid, uuid9190, sizeof uuid9190);
            return;
        }
    }
}
void SGAudioSourceQueueProbe(AURenderCallbackStruct callback) {
    if (!SGAudioSourceQueueProbeRequired(callback) ||
        atomic_exchange(&sg_sourceProbeLogged, true)) return;

    uintptr_t context = (uintptr_t)callback.inputProcRefCon;
    uint32_t channels = 0, active = 0;
    uint64_t sink = 0, scratch = 0, limit = 0;
    bool contextReadable = context && context <= UINTPTR_MAX - 0xa0 &&
        readMetadata(context + 0x6c, &channels, sizeof channels) &&
        readWord(context + 0x78, &sink) && readWord(context + 0x80, &scratch) &&
        readWord(context + 0x88, &limit) && readMetadata(context + 0x9c, &active, sizeof active);
    SGLog(@"Sing ABI probe 9.1.90 callback=%p context=%p readable=%d channels=%u sink=%p scratch=%p limit=%p active=%u",
          (void *)(uintptr_t)callback.inputProc, callback.inputProcRefCon, contextReadable, channels,
          (void *)(uintptr_t)sink, (void *)(uintptr_t)scratch, (void *)(uintptr_t)limit, active);
    if (!contextReadable) return;

    uint64_t sinkWords[16] = {0}, vtableWords[16] = {0};
    bool sinkReadable = sink && sink <= UINTPTR_MAX - sizeof sinkWords &&
        readMetadata((uintptr_t)sink, sinkWords, sizeof sinkWords);
    bool vtableReadable = sinkReadable && sinkWords[0] && sinkWords[0] <= UINTPTR_MAX - sizeof vtableWords &&
        readMetadata((uintptr_t)sinkWords[0], vtableWords, sizeof vtableWords);
    SGLog(@"Sing ABI probe sink readable=%d fields={%@}", sinkReadable, probeWords(sinkWords, 16));
    SGLog(@"Sing ABI probe vtable=%p readable=%d entries={%@}",
          (void *)(uintptr_t)sinkWords[0], vtableReadable, probeWords(vtableWords, 16));
    if (!sinkReadable || sinkWords[4] < 8) return;

    uintptr_t owner = (uintptr_t)sinkWords[4] - 8;
    uint64_t head = 0, tail = 0, pending = 0, flags = 0;
    bool ownerReadable = owner <= UINTPTR_MAX - 0xc0 &&
        readWord(owner + 0x18, &head) && readWord(owner + 0x20, &tail) &&
        readWord(owner + 0xb8, &pending) && readWord(owner + 0xa0, &flags);
    SGLog(@"Sing ABI probe legacy-offset candidate owner=%p readable=%d head=%p tail=%p pending=%p flags=0x%llx",
          (void *)owner, ownerReadable, (void *)(uintptr_t)head, (void *)(uintptr_t)tail,
          (void *)(uintptr_t)pending, (unsigned long long)flags);
    if (!ownerReadable || !head || head > UINTPTR_MAX - 0x28) return;

    uint64_t node[5] = {0}, remaining = 0;
    bool nodeReadable = readMetadata((uintptr_t)head, node, sizeof node);
    if (nodeReadable && node[0] && node[0] <= UINTPTR_MAX - 0x28)
        readWord((uintptr_t)node[0] + 0x20, &remaining);
    SGLog(@"Sing ABI probe legacy-offset candidate node readable=%d block=%p next=%p remaining=%llu",
          nodeReadable, (void *)(uintptr_t)node[0], (void *)(uintptr_t)node[4],
          (unsigned long long)remaining);
}
bool SGAudioSourceQueueProbeRequired(AURenderCallbackStruct callback) {
    return sg_sourceSpotify90 && (uintptr_t)callback.inputProc == sg_sourceImage + 0x6d0b080;
}
bool SGAudioSourceQueueSupported(AURenderCallbackStruct callback) {
    uint64_t instruction;
    return sg_sourceLayout && (uintptr_t)callback.inputProc == sg_sourceImage + 0x24dd98 &&
        readWord((uintptr_t)callback.inputProc, &instruction) && instruction == UINT64_C(0xa9bc5ff8350005a3);
}
SGAudioSourcePrefix SGAudioSourceQueuePrefix(AURenderCallbackStruct callback, UInt32 maximumFrames, bool continuous) {
    const SGAudioSourcePrefix empty = {0, UINT32_MAX};
    if (!maximumFrames || !SGAudioSourceQueueSupported(callback)) return empty;
    uintptr_t context = (uintptr_t)callback.inputProcRefCon;
    uint64_t instruction, sink, table, function, delegate;
    uint64_t contextWords[5], sinkWords[5];
    if (!context || context > UINTPTR_MAX - 0x90 ||
        !readWord((uintptr_t)callback.inputProc, &instruction) || instruction != UINT64_C(0xa9bc5ff8350005a3) ||
        !readMetadata(context + 0x68, contextWords, sizeof contextWords)) return empty;
    sink = contextWords[2];
    if ((uint32_t)(contextWords[0] >> 32) != 2 || contextWords[4] <= contextWords[3] ||
        !readMetadata(sink, sinkWords, sizeof sinkWords)) return empty;
    table = sinkWords[0]; delegate = sinkWords[4];
    if (table > UINTPTR_MAX - 0x18 ||
        !readWord(table + 0x10, &function) || function != sg_sourceImage + 0x180f3c ||
        !readWord(function, &instruction) || instruction != UINT64_C(0xa9025ff8d10183ff) ||
        delegate < 8 || delegate > UINTPTR_MAX - 0xb8 ||
        !readWord(delegate, &table) || table > UINTPTR_MAX - 0x18 ||
        !readWord(table + 0x10, &function) || function != sg_sourceImage + 0x10908b4 ||
        !readWord(function, &instruction) || instruction != UINT64_C(0x17c2d2c2d1002000) ||
        !readWord(sg_sourceImage + 0x1453c0, &instruction) || instruction != UINT64_C(0xa9016ffcd101c3ff)) return empty;
    uintptr_t owner = delegate - 8;
    uint64_t head, tail, pending;
    // The reader at 0x1453c0 processes pending commands before consuming its queue.
    if (!readWord(owner + 0xb8, &pending) || pending ||
        !readWord(owner + 0x18, &head) || !readWord(owner + 0x20, &tail)) return empty;
    uint64_t cursor = head, samples = 0;
    uint64_t boundary = UINT64_MAX, flags = 0;
    uintptr_t visited[128];
    unsigned count = 0;
    while (cursor != tail) {
        if (count == 128 || !cursor || cursor > UINTPTR_MAX - 0x28) return empty;
        for (unsigned i = 0; i < count; i++) if (visited[i] == cursor) return empty;
        visited[count++] = cursor;
        uint64_t node[5], remaining;
        if (!readMetadata(cursor, node, sizeof node)) return empty;
        uint64_t block = node[0], next = node[4];
        if (next != tail) for (unsigned i = 0; i < count; i++) if (visited[i] == next) return empty;
        if (!block) {
            if (!continuous || boundary != UINT64_MAX) break;
            if (!readWord(sg_sourceImage + 0x1454b4, &instruction) || instruction != UINT64_C(0x95ece96591006296) ||
                !readWord(owner + 0xa0, &flags)) return empty;
            if (((flags >> 8) & 255) == 1 && !(flags & (UINT64_C(1) << 16))) break;
            boundary = samples / 2;
            cursor = next;
            continue;
        }
        if (block > UINTPTR_MAX - 0x28 || !readWord(block + 0x20, &remaining) ||
            remaining > 882000 || (remaining & 1)) return empty;
        samples += remaining;
        if (samples / 2 >= maximumFrames) break;
        cursor = next;
    }
    uint64_t headAfter, tailAfter;
    if (!readWord(owner + 0xb8, &pending) || pending ||
        !readWord(owner + 0x18, &headAfter) || !readWord(owner + 0x20, &tailAfter) ||
        head != headAfter || tail != tailAfter) return empty;
    if (boundary != UINT64_MAX) {
        uint64_t after;
        if (!readWord(owner + 0xa0, &after) || after != flags) return empty;
    }
    UInt32 frames = (UInt32)MIN(samples / 2, maximumFrames);
    return (SGAudioSourcePrefix){frames, boundary < frames ? (UInt32)boundary : UINT32_MAX};
}
UInt32 SGAudioSourceQueueFrames(AURenderCallbackStruct callback, UInt32 maximumFrames) {
    return SGAudioSourceQueuePrefix(callback, maximumFrames, false).frames;
}
