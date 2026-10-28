// Translations kept on disk, whichever way they were made: one small JSON file a song and language in
// Caches/spoti.pw/Translations, each line's text to its translation, so a song comes back translated after
// a relaunch and lyrics from another source still find their lines. The newest kKept files stay; iOS may
// clear Caches when it runs low, which costs a translation again.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "LyricsTranslation.h"

static const NSUInteger kKept = 200;

static NSURL *folder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    return [[caches URLByAppendingPathComponent:@"spoti.pw" isDirectory:YES] URLByAppendingPathComponent:@"Translations" isDirectory:YES];
}

static NSURL *fileFor(NSString *track, NSString *language) {
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].invertedSet;
    NSString *tag = [[language componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
    return [folder() URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", track, tag]];
}

static NSArray<NSURL *> *files(void) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder() includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                          options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
}

void SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length || !language.length || !lines.count) return;
    NSData *data = [NSData dataWithContentsOfURL:fileFor(track, language)];
    id saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![saved isKindOfClass:NSDictionary.class]) saved = nil;
    for (SGKaraokeLine *line in lines) {
        id translation = saved[SGKaraokeLineText(line) ?: @""];
        BOOL has = [translation isKindOfClass:NSString.class] && [translation length];
        if (line.translationMade && !has) {
            line.translation = nil;
            line.translationMade = NO;
        } else if (!line.translation.length && has) {
            line.translation = translation;
            line.translationMade = YES;
        }
    }
}

void SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length || !language.length) return;
    NSMutableDictionary<NSString *, NSString *> *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translation.length) saved[text] = line.translation;
    }
    if (!saved.count) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:saved options:0 error:nil];
    // One at a time, in the order asked: a song is saved after every batch, and an older write must not land last.
    static dispatch_queue_t writes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ writes = dispatch_queue_create("pweevee.translations", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(writes, ^{
        [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:fileFor(track, language) atomically:YES];
        NSArray<NSURL *> *all = files();
        if (all.count <= kKept) return;
        NSArray<NSURL *> *oldestFirst = [all sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
            NSDate *da, *db;
            [a getResourceValue:&da forKey:NSURLContentModificationDateKey error:nil];
            [b getResourceValue:&db forKey:NSURLContentModificationDateKey error:nil];
            return [da ?: NSDate.distantPast compare:db ?: NSDate.distantPast];
        }];
        for (NSUInteger i = 0; i < all.count - kKept; i++) [NSFileManager.defaultManager removeItemAtURL:oldestFirst[i] error:nil];
    });
}

static NSString *summary(void) {
    NSArray<NSURL *> *all = files();
    if (!all.count) return @"None";
    long long bytes = 0;
    for (NSURL *file in all) {
        NSNumber *size;
        [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        bytes += size.longLongValue;
    }
    return [NSString stringWithFormat:@"%lu · %@", (unsigned long)all.count,
            [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile]];
}

SGModRow *SGSavedTranslationsRow(void) {
    return SGStatActionRow(@"Saved translations", @"Songs translated on this iPhone or by Gemini come back translated",
                           ^NSString *{ return summary(); }, ^{
        if (!files().count) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete saved translations?"
            message:@"Songs translated before are translated again the next time you ask." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [NSFileManager.defaultManager removeItemAtURL:folder() error:nil];
            SGLog(@"translation: saved translations deleted");
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
