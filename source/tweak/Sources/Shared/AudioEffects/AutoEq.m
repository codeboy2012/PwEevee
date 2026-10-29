// AutoEq's headphone corrections, read straight from its public repository: github.com/jaakkopasanen/AutoEq,
// MIT License, Copyright (c) 2018-2022 Jaakko Pasanen. Nothing of it ships in the mod; results/INDEX.md and
// the chosen headphone's GraphicEQ file are downloaded when asked for.
//
// INDEX.md, as of October 2026, is a heading and a note, then one line per result:
//     - [1MORE Quad Driver](./crinacle/711%20in-ear/1MORE%20Quad%20Driver) by crinacle on 711
// and the folder holds "<folder's last part> GraphicEQ.txt", one "GraphicEQ: 20 -0.2; 21 -0.2; ..." line.
// The file is named after the folder, not the name in brackets: the name can carry a target the folder
// does not.
#import "Core/SGLog.h"
#import "AudioEffects.h"
#import "AudioEffectsPresets.h"

static NSString *const kResults = @"https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/";
static const NSTimeInterval kIndexLife = 30 * 24 * 3600;

@implementation SGAutoEqHeadphone
@end

NSArray<SGAutoEqHeadphone *> *SGAutoEqParseIndex(NSString *markdown) {
    NSMutableArray<SGAutoEqHeadphone *> *headphones = [NSMutableArray array];
    [markdown enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if (![line hasPrefix:@"- ["]) return;
        // The last "](./" and the last ") by ": names hold brackets and folders parentheses.
        NSRange link = [line rangeOfString:@"](./" options:NSBackwardsSearch];
        NSRange by = [line rangeOfString:@") by " options:NSBackwardsSearch];
        if (link.location == NSNotFound || by.location == NSNotFound || by.location <= NSMaxRange(link)) return;
        SGAutoEqHeadphone *headphone = [SGAutoEqHeadphone new];
        headphone.name = [line substringWithRange:NSMakeRange(3, link.location - 3)];
        headphone.path = [line substringWithRange:NSMakeRange(NSMaxRange(link), by.location - NSMaxRange(link))];
        headphone.source = [line substringFromIndex:NSMaxRange(by)];
        if (headphone.name.length && headphone.path.length) [headphones addObject:headphone];
    }];
    return headphones;
}

// Decoded and encoded again: INDEX.md leaves some characters raw ("$", "&", parentheses) that a URL may not.
NSURL *SGAutoEqGraphicEqURL(NSString *path) {
    NSString *folder = path.stringByRemovingPercentEncoding ?: path;
    NSString *file = [NSString stringWithFormat:@"%@/%@ GraphicEQ.txt", folder, folder.lastPathComponent];
    NSString *encoded = [file stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    return encoded ? [NSURL URLWithString:[kResults stringByAppendingString:encoded]] : nil;
}

NSString *SGAutoEqNameOf(NSString *path) {
    NSString *folder = path.stringByRemovingPercentEncoding ?: path;
    return folder.lastPathComponent;
}

NSArray<SGAutoEqHeadphone *> *SGAutoEqSearch(NSArray<SGAutoEqHeadphone *> *all, NSString *query) {
    NSStringCompareOptions loose = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
    NSArray<NSString *> *words = [query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (!words.count) return all;
    NSMutableArray<SGAutoEqHeadphone *> *found = [NSMutableArray array];
    for (SGAutoEqHeadphone *headphone in all) {
        NSString *text = [NSString stringWithFormat:@"%@ %@", headphone.name, headphone.source];
        BOOL match = YES;
        for (NSString *word in words) match = match && [text rangeOfString:word options:loose].location != NSNotFound;
        if (match) [found addObject:headphone];
    }
    return found;
}

#pragma mark - downloads

static NSURL *cachedIndex(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [[caches URLByAppendingPathComponent:@"spoti.pw" isDirectory:YES] URLByAppendingPathComponent:@"AutoEq" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder URLByAppendingPathComponent:@"INDEX.md"];
}

// The body of a 200 answer as text, or nil and why not. `done` on URLSession's queue, not the main one.
static void fetchText(NSURL *url, void (^done)(NSString *text, NSString *error)) {
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        NSString *text = status == 200 && data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSString *why = text ? nil : error ? error.localizedDescription : [NSString stringWithFormat:@"GitHub answered %ld", (long)status];
        if (why) SGLog(@"autoeq: %@ failed (%@)", url.path, why);
        done(text, why);
    }] resume];
}

void SGAutoEqLoadIndex(BOOL refresh, void (^done)(NSArray<SGAutoEqHeadphone *> *, NSString *)) {
    NSURL *cache = cachedIndex();
    NSDate *saved = [NSFileManager.defaultManager attributesOfItemAtPath:cache.path error:nil].fileModificationDate;
    void (^fromCache)(NSString *) = ^(NSString *why) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *text = [NSString stringWithContentsOfURL:cache encoding:NSUTF8StringEncoding error:nil];
            NSArray<SGAutoEqHeadphone *> *headphones = text ? SGAutoEqParseIndex(text) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                // A failed refresh still says so over the saved list.
                done(headphones.count ? headphones : nil, why ?: (headphones.count ? nil : @"The saved list could not be read"));
            });
        });
    };
    if (saved && !refresh && -saved.timeIntervalSinceNow < kIndexLife) {
        fromCache(nil);
        return;
    }
    // Its 8850 lines are read and saved off the main thread, which has only the answer.
    fetchText([NSURL URLWithString:[kResults stringByAppendingString:@"INDEX.md"]], ^(NSString *text, NSString *error) {
        // A page that answers but holds no headphones is not kept over a good copy.
        NSArray<SGAutoEqHeadphone *> *headphones = text ? SGAutoEqParseIndex(text) : nil;
        if (!headphones.count) {
            fromCache(error ?: @"AutoEq's list has no headphones in it");
            return;
        }
        [text writeToURL:cache atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ done(headphones, nil); });
    });
}

#pragma mark - a correction per output

static NSString *sg_outputUID, *sg_outputName;

static NSDictionary<NSString *, NSDictionary *> *outputs(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyDSPOutputs];
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static void setOutput(NSString *uid, NSDictionary *entry) {
    NSMutableDictionary *all = [outputs() mutableCopy];
    all[uid] = entry;
    [NSUserDefaults.standardUserDefaults setObject:all forKey:SGKeyDSPOutputs];
}

static NSString *followed(void) {
    return [NSUserDefaults.standardUserDefaults stringForKey:SGKeyDSPOutputFollowed] ?: @"";
}

static void setFollowed(NSString *uid) {
    [NSUserDefaults.standardUserDefaults setObject:uid ?: @"" forKey:SGKeyDSPOutputFollowed];
}

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGAutoEqOutputsChangedNotification object:nil];
}

// A headphone's correction is what the Graphic EQ plays, rather than nothing or the user's own curve.
static BOOL correctionInUse(void) {
    return SGDSPSwitch(SGKeyDSPGraphicEq) && SGDSPString(SGKeyDSPGraphicEq).length;
}

static void takeOff(void) {
    if (!correctionInUse()) return;
    SGDSPSetString(SGKeyDSPGraphicEq, @"");
    SGDSPSetSwitch(SGKeyDSPGraphicEq, NO);
}

// The output playing now remembers what the Graphic EQ plays, when it is remembered.
static void rememberPick(void) {
    if (!sg_outputUID.length || !outputs()[sg_outputUID]) return;
    BOOL on = correctionInUse();
    setOutput(sg_outputUID, @{@"name": sg_outputName ?: sg_outputUID, @"path": on ? SGDSPString(SGKeyDSPGraphicEq) : @"",
                              @"nodes": on ? SGDSPString(SGKeyDSPGraphicEqNodes) : @""});
    setFollowed(sg_outputUID);
    changed();
}

BOOL SGAutoEqApplyText(NSString *path, NSString *text) {
    NSString *line = SGDSPGraphicEqLine(text);
    if (!line || !path.length) return NO;
    SGDSPSetString(SGKeyDSPGraphicEqNodes, line);
    SGDSPSetString(SGKeyDSPGraphicEq, path);
    SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);
    // The correction is meant to be heard: the master switch, off until asked for, comes on with it.
    if (!SGDSPSwitch(SGKeyDSP)) SGDSPSetSwitch(SGKeyDSP, YES);
    rememberPick();
    return YES;
}

void SGAutoEqTakeOff(void) {
    takeOff();
    rememberPick();
}

void SGAutoEqOutputChanged(NSString *uid, NSString *name) {
    if (!uid.length || [uid isEqualToString:sg_outputUID]) return;
    sg_outputUID = [uid copy];
    sg_outputName = name.length ? [name copy] : sg_outputUID;
    NSDictionary *entry = outputs()[uid];
    if (entry) {
        if (![entry[@"name"] isEqual:sg_outputName]) {
            NSMutableDictionary *renamed = [entry mutableCopy];
            renamed[@"name"] = sg_outputName;
            setOutput(uid, renamed);
        }
        NSString *path = entry[@"path"], *nodes = entry[@"nodes"];
        if (path.length && nodes.length) {
            SGDSPSetString(SGKeyDSPGraphicEqNodes, nodes);
            SGDSPSetString(SGKeyDSPGraphicEq, path);
            SGDSPSetSwitch(SGKeyDSPGraphicEq, YES);
            SGLog(@"autoeq: %@ connected, its correction %@ on%@", sg_outputName, SGAutoEqNameOf(path), SGDSPSwitch(SGKeyDSP) ? @"" : @" (Audio effects are off)");
        } else {
            takeOff();
            SGLog(@"autoeq: %@ connected, None remembered for it", sg_outputName);
        }
        setFollowed(uid);
    } else if (followed().length) {
        // The correction came on for another output; this one has none.
        if (correctionInUse()) SGLog(@"autoeq: %@ connected, with no correction remembered: %@ off", sg_outputName, SGAutoEqNameOf(SGDSPString(SGKeyDSPGraphicEq)));
        takeOff();
        setFollowed(@"");
    }
    changed();
}

NSString *SGAutoEqOutputUID(void) {
    return sg_outputUID;
}

NSString *SGAutoEqOutputName(void) {
    return sg_outputName;
}

void SGAutoEqRememberOutput(BOOL remember) {
    if (!sg_outputUID.length) return;
    if (!remember) {
        SGAutoEqForgetOutput(sg_outputUID);
        return;
    }
    setOutput(sg_outputUID, @{@"name": sg_outputName, @"path": @"", @"nodes": @""});
    rememberPick();
}

BOOL SGAutoEqOutputRemembered(NSString *uid) {
    return uid.length && outputs()[uid] != nil;
}

// What plays stays: forgetting an output does not take its correction off now.
void SGAutoEqForgetOutput(NSString *uid) {
    if (!uid.length) return;
    NSMutableDictionary *all = [outputs() mutableCopy];
    [all removeObjectForKey:uid];
    [NSUserDefaults.standardUserDefaults setObject:all forKey:SGKeyDSPOutputs];
    if ([followed() isEqualToString:uid]) setFollowed(@"");
    changed();
}

NSArray<NSDictionary<NSString *, NSString *> *> *SGAutoEqRememberedOutputs(void) {
    NSMutableArray *list = [NSMutableArray array];
    [outputs() enumerateKeysAndObjectsUsingBlock:^(NSString *uid, NSDictionary *entry, BOOL *stop) {
        if (![entry isKindOfClass:NSDictionary.class]) return;
        [list addObject:@{@"uid": uid, @"name": entry[@"name"] ?: uid, @"path": entry[@"path"] ?: @""}];
    }];
    [list sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]]];
    return list;
}

void SGAutoEqApply(SGAutoEqHeadphone *headphone, void (^done)(NSString *)) {
    NSURL *url = SGAutoEqGraphicEqURL(headphone.path);
    if (!url) {
        done(@"Its address could not be made");
        return;
    }
    fetchText(url, ^(NSString *text, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) done(error);
            else done(SGAutoEqApplyText(headphone.path, text) ? nil : @"The file is not a GraphicEQ line");
        });
    });
}
