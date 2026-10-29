#import "SGLosslessStore.h"
#import <AudioToolbox/AudioToolbox.h>

static NSString *const kIndex = @".index.plist";   // track URI -> file name

NSString *SGLosslessStoreDirectory(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *directory = [documents stringByAppendingPathComponent:@"Lossless"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    return directory;
}

static NSString *indexPath(void) {
    return [SGLosslessStoreDirectory() stringByAppendingPathComponent:kIndex];
}

static NSString *folded(NSString *text) {
    return [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
        stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSWidthInsensitiveSearch locale:nil];
}

// A file's title tag and length, read once per file and kept by name and modification date.
static NSDictionary *tags(NSString *path) {
    static NSMutableDictionary<NSString *, NSDictionary *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL].fileModificationDate;
    NSString *key = [NSString stringWithFormat:@"%@|%f", path, modified.timeIntervalSince1970];
    if (cache[key]) return cache[key];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    AudioFileID file;
    if (AudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], kAudioFileReadPermission, 0, &file) == noErr) {
        CFDictionaryRef info = NULL;
        UInt32 size = sizeof info;
        if (AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, &info) == noErr && info) {
            NSDictionary *read = CFBridgingRelease(info);
            if (read[@kAFInfoDictionary_Title]) found[@"title"] = read[@kAFInfoDictionary_Title];
            if (read[@kAFInfoDictionary_ApproximateDurationInSeconds]) found[@"duration"] = @([read[@kAFInfoDictionary_ApproximateDurationInSeconds] doubleValue]);
        }
        AudioFileClose(file);
    }
    cache[key] = found;
    return found;
}

static NSString *find(NSString *uri, NSString *title, double duration) {
    NSString *directory = SGLosslessStoreDirectory();
    NSDictionary *index = [NSDictionary dictionaryWithContentsOfFile:indexPath()];
    NSString *known = index[uri];
    if (known) {
        NSString *path = [directory stringByAppendingPathComponent:known];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) return path;
    }
    if (!title.length) return nil;
    NSString *wanted = folded(title);
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL]) {
        NSString *extension = name.pathExtension.lowercaseString;
        if (![@[@"flac", @"m4a", @"caf"] containsObject:extension]) continue;
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDictionary *tag = tags(path);
        NSString *fileTitle = tag[@"title"];
        BOOL titled = fileTitle ? [folded(fileTitle) isEqualToString:wanted]
                                : [folded(name.stringByDeletingPathExtension) containsString:wanted];
        if (titled && (duration < 0 || fabs([tag[@"duration"] doubleValue] - duration) <= 2)) return path;
    }
    return nil;
}

NSString *SGLosslessStoreFile(NSString *uri, NSString *title, double duration) {
    return duration > 0 ? find(uri, title, duration) : find(uri, @"", 0);
}

BOOL SGLosslessStoreHas(NSString *uri, NSString *title) {
    return find(uri, title, -1) != nil;
}

void SGLosslessStoreRemember(NSString *uri, NSString *path) {
    NSMutableDictionary *index = [NSMutableDictionary dictionaryWithContentsOfFile:indexPath()] ?: [NSMutableDictionary dictionary];
    if ([index[uri] isEqualToString:path.lastPathComponent]) return;
    index[uri] = path.lastPathComponent;
    [index writeToFile:indexPath() atomically:YES];
}
