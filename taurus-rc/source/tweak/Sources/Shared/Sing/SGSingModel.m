#import "SGSingModel.h"
#import "SGStemWorker.h"
#import "Core/SGLog.h"
#import "Core/SGPrefs.h"
#import <CommonCrypto/CommonDigest.h>
#import <Network/Network.h>

NSNotificationName const SGSingModelDidChangeNotification = @"spotifyglass.singModelChanged";
NSString *const SGSingModelDidChangeChoiceKey = @"choiceChanged";

#ifndef SGSingModelBase
#define SGSingModelBase @"https://huggingface.co/My-Name-Is-Jeff/vitrine-sing/resolve/main/"
#endif
#ifndef SGSingModelRoot
#define SGSingModelRoot nil
#endif

typedef struct {
    const char *path;
    int64_t size;
    const char *sha256;
} SGSingModelFile;

typedef struct {
    const char *repoFolder;
    const char *installedFolder;
    const char *stagingFolder;
    const char *stagedModelFolder;
    const SGSingModelFile *files;
} SGSingModelDescriptor;

static const SGSingModelFile kFullFiles[] = {
    {"metadata.json", 2333, "101714d1a37ad29c70bf1705ec25ec99584c3cbce27f2245858ace06dacbfb44"},
    {"coremldata.bin", 388, "bcfd38a8b121681dfb9fdfe6f9d88ffb29068e0dd6d24d4012f4c3a7bdcbc81b"},
    {"analytics/coremldata.bin", 243, "55f78aab64f5b1250ce4d6016dff23aee43fb97feb77bbceab4e36b3d9ccffb3"},
    {"model.mil", 1346642, "957024c1075fe331f7ca3410b8bf5e2f83a58c61763caf154729829ce0a92d08"},
    {"weights/weight.bin", 209077208, "bb4a0effafb5121b9aaa5ea96371fa14d0d8dc30a5ae44a93e0c15a2f4077635"},
};
static const SGSingModelFile kLightFiles[] = {
    {"metadata.json", 2383, "757200c870bd4c5e5b70130c9edbd60029bd81c779b504c57ddcd624597f30e9"},
    {"coremldata.bin", 484, "e533e0c22c3f185e5b8871d2b897111e64420736daa7dc7c239206ca2519d428"},
    {"analytics/coremldata.bin", 243, "205b1d1d16603c69b4abdfa54b29df71164a16ca4f16a1cf436e7e33ce0b1407"},
    {"model.mil", 715945, "d3b62a7972344d1a8eec5de8a21130a19272738bce1135871d8bab098585a841"},
    {"weights/weight.bin", 30040968, "ad460549f68898eab7fe946e9675efaa2551d37b93f73796958c73d4881897fc"},
};
enum { kFileCount = 5 };

static const SGSingModelDescriptor kModels[] = {
    {"separator-ane.mlmodelc", "separator.mlmodelc", "Download-vitrine-ane", "separator.mlmodelc", kFullFiles},
    {"separator-light.mlmodelc", "separator-light.mlmodelc", "Download-vitrine-light", "separator-light.mlmodelc", kLightFiles},
};

static NSString *const kSessionIdentifier = @"spotifyglass.sing.model";
static NSString *const kDownloadKindKey = @"spotifyglass.sing.modelDownloadKind";
static const int64_t kHeadroom = 64ll << 20;               // free space left over once the model is in
static const NSTimeInterval kProgressInterval = 0.25;      // between two progress notifications

static BOOL sg_loaded, sg_installed, sg_want, sg_metered;
static SGSingModelKind sg_loadedKind;
static NSString *sg_failure;
static BOOL sg_done[kFileCount], sg_checking[kFileCount], sg_restarted[kFileCount], sg_fromResume[kFileCount];
static int64_t sg_bytes[kFileCount];
static NSString *sg_rejected[kFileCount];
static NSMutableDictionary<NSNumber *, NSURLSessionDownloadTask *> *sg_tasks;
static NSUInteger sg_epoch;
static NSURLSession *sg_session;
static void (^sg_sessionCompletion)(void);
static NSTimeInterval sg_lastPost;

#pragma mark - the files

static SGSingModelKind chosenKind(void) {
    return SGInt(SGKeySingModel, SGSingModelFull) == SGSingModelLight ? SGSingModelLight : SGSingModelFull;
}
static const SGSingModelDescriptor *model(void) { return &kModels[chosenKind()]; }
static const SGSingModelFile *files(void) { return model()->files; }
static const SGSingModelFile *filesOfKind(SGSingModelKind kind) { return kModels[kind == SGSingModelLight ? SGSingModelLight : SGSingModelFull].files; }
static NSString *pathOf(int i) { return @(files()[i].path); }
static NSString *repoPathOf(int i) { return [[NSString stringWithUTF8String:model()->repoFolder] stringByAppendingFormat:@"/%@", pathOf(i)]; }
static NSString *downloadFolderName(void) { return @(model()->stagingFolder); }

static NSURL *singFolder(void) {
    static NSURL *folder;
    if (!folder) {
        NSString *root = SGSingModelRoot;
        NSURL *base = root ? [NSURL fileURLWithPath:root isDirectory:YES]
            : [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        folder = [base URLByAppendingPathComponent:@"spoti.pw/Sing" isDirectory:YES];
    }
    return folder;
}
static NSURL *installedModel(void) { return [singFolder() URLByAppendingPathComponent:@(model()->installedFolder) isDirectory:YES]; }
static NSURL *staging(void) { return [singFolder() URLByAppendingPathComponent:downloadFolderName() isDirectory:YES]; }
static NSURL *stagedModel(void) { return [staging() URLByAppendingPathComponent:@(model()->stagedModelFolder) isDirectory:YES]; }
static NSURL *stagedFile(int i) { return [stagedModel() URLByAppendingPathComponent:pathOf(i)]; }
// Where a file waits for its hash, and where a stopped download of it keeps what it needs to resume.
static NSURL *arrivedFile(int i) { return [staging() URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.part", i]]; }
static NSURL *resumeFile(int i) { return [staging() URLByAppendingPathComponent:[NSString stringWithFormat:@"%d.resume", i]]; }

static int64_t sizeAt(NSURL *url) {
    NSNumber *size = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:nil][NSFileSize];
    return size ? size.longLongValue : -1;
}

static NSString *sha256(NSURL *url) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
    if (!file) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    for (;;) {
        @autoreleasepool {
            NSData *chunk = [file readDataUpToLength:1 << 20 error:nil];
            if (!chunk.length) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [file closeAndReturnError:nil];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int n = 0; n < CC_SHA256_DIGEST_LENGTH; n++) [hex appendFormat:@"%02x", digest[n]];
    return hex;
}

// Hashing, moving and removing go one after another, off the main thread.
static dispatch_queue_t disk(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("spotifyglass.sing.model", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

// The folder stays out of the iCloud backup, with what is in it: the model is large and can be had again.
static BOOL makeFolders(NSError **error) {
    if (![NSFileManager.defaultManager createDirectoryAtURL:stagedModel() withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSURL *folder = singFolder();
    [folder setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    return YES;
}

static void load(void) {
    SGSingModelKind kind = chosenKind();
    if (sg_loaded && sg_loadedKind == kind) return;
    sg_loaded = YES;
    sg_loadedKind = kind;
    sg_want = NO;
    sg_installed = NO;
    sg_failure = nil;
    memset(sg_done, 0, sizeof sg_done);
    memset(sg_checking, 0, sizeof sg_checking);
    memset(sg_restarted, 0, sizeof sg_restarted);
    memset(sg_fromResume, 0, sizeof sg_fromResume);
    memset(sg_bytes, 0, sizeof sg_bytes);
    if (!sg_tasks) sg_tasks = [NSMutableDictionary dictionary];
    sg_installed = YES;
    for (int i = 0; i < kFileCount; i++)
        sg_installed &= sizeAt([installedModel() URLByAppendingPathComponent:pathOf(i)]) == files()[i].size;
    if (sg_installed) return;
    for (int i = 0; i < kFileCount; i++) {
        sg_done[i] = sizeAt(stagedFile(i)) == files()[i].size;
        sg_bytes[i] = sg_done[i] ? 0 : [[NSDictionary dictionaryWithContentsOfURL:resumeFile(i)][@"bytes"] longLongValue];
    }
}

static void post(BOOL progress) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (progress && now - sg_lastPost < kProgressInterval) return;
    sg_lastPost = now;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingModelDidChangeNotification object:nil];
}

static void postChoice(void) {
    sg_lastPost = NSProcessInfo.processInfo.systemUptime;
    [NSNotificationCenter.defaultCenter postNotificationName:SGSingModelDidChangeNotification
                                                      object:nil
                                                    userInfo:@{SGSingModelDidChangeChoiceKey: @YES}];
}

#pragma mark - the download

@interface SGSingModelDelegate : NSObject <NSURLSessionDownloadDelegate>
@end

static NSURLSession *session(void) {
    if (!sg_session) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kSessionIdentifier];
        configuration.sessionSendsLaunchEvents = YES;
        configuration.discretionary = NO;
        sg_session = [NSURLSession sessionWithConfiguration:configuration delegate:[SGSingModelDelegate new]
                                             delegateQueue:NSOperationQueue.mainQueue];
    }
    return sg_session;
}

static void keepResume(int i, NSData *data, const SGSingModelDescriptor *downloadModel) {
    if (!data) {
        if (downloadModel == model()) sg_bytes[i] = 0;
        return;
    }
    NSURL *resume = [singFolder() URLByAppendingPathComponent:
        [NSString stringWithFormat:@"%s-%d.resume", downloadModel->stagingFolder, i]];
    [@{@"data": data, @"bytes": @(sg_bytes[i]), @"metered": @(sg_metered)} writeToURL:resume error:nil];
}

// Stops every task: kept for a resume when `keep`, dropped otherwise.
static void stopTasks(BOOL keep) {
    sg_want = NO;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kDownloadKindKey];
    const SGSingModelDescriptor *downloadModel = model();
    NSUInteger epoch = sg_epoch;
    [sg_tasks enumerateKeysAndObjectsUsingBlock:^(NSNumber *key, NSURLSessionDownloadTask *task, BOOL *stop) {
        int i = key.intValue;
        if (!keep) { [task cancel]; return; }
        int64_t received = sg_bytes[i];
        BOOL metered = sg_metered;
        [task cancelByProducingResumeData:^(NSData *data) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (epoch != sg_epoch || sg_want) return;
                if (!data) {
                    if (downloadModel == model()) sg_bytes[i] = 0;
                    return;
                }
                NSURL *resume = [singFolder() URLByAppendingPathComponent:
                    [NSString stringWithFormat:@"%s-%d.resume", downloadModel->stagingFolder, i]];
                [@{@"data": data, @"bytes": @(received), @"metered": @(metered)} writeToURL:resume error:nil];
                post(NO);
            });
        }];
    }];
    [sg_tasks removeAllObjects];
}

static void fail(NSString *failure) {
    SGLog(@"Sing voice model download stopped: %@", failure);
    sg_failure = failure;
    stopTasks(YES);
    post(NO);
}

static void startFile(int i) {
    NSDictionary *resume = [NSDictionary dictionaryWithContentsOfURL:resumeFile(i)];
    [NSFileManager.defaultManager removeItemAtURL:resumeFile(i) error:nil];
    NSURLSessionDownloadTask *task = nil;
    if ([resume[@"data"] isKindOfClass:NSData.class] && [resume[@"metered"] boolValue] == sg_metered && !sg_restarted[i]) {
        task = [session() downloadTaskWithResumeData:resume[@"data"]];
        sg_bytes[i] = [resume[@"bytes"] longLongValue];
    }
    sg_fromResume[i] = task != nil;
    if (!task) {
        NSURL *url = [NSURL URLWithString:repoPathOf(i) relativeToURL:[NSURL URLWithString:SGSingModelBase]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.absoluteURL];
        request.allowsExpensiveNetworkAccess = sg_metered;
        request.allowsConstrainedNetworkAccess = sg_metered;
        task = [session() downloadTaskWithRequest:request];
        sg_bytes[i] = 0;
    }
    task.taskDescription = repoPathOf(i);
    task.countOfBytesClientExpectsToReceive = files()[i].size;
    sg_tasks[@(i)] = task;
    [task resume];
}

static void startMissing(void) {
    for (int i = 0; i < kFileCount; i++)
        if (!sg_done[i] && !sg_checking[i] && !sg_tasks[@(i)]) startFile(i);
}

// Every file checked: the staged model takes the installed one's place in one rename.
static void installIfComplete(void) {
    if (!sg_want) return;
    for (int i = 0; i < kFileCount; i++) if (!sg_done[i]) return;
    SGSingModelKind kind = chosenKind();
    NSUInteger epoch = sg_epoch;
    NSURL *staged = stagedModel(), *installed = installedModel(), *folder = staging();
    dispatch_async(disk(), ^{
        NSFileManager *files = NSFileManager.defaultManager;
        NSError *error = nil;
        [files removeItemAtURL:installed error:nil];
        BOOL moved = [files moveItemAtURL:staged toURL:installed error:&error];
        if (moved) {
            [files removeItemAtURL:folder error:nil];
            [installed setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (epoch != sg_epoch || kind != chosenKind() || !sg_want) return;
            if (!moved) { fail([NSString stringWithFormat:@"The voice model could not be put in place: %@", error.localizedDescription]); return; }
            SGLog(@"Sing voice model installed");
            sg_want = NO;
            [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:kDownloadKindKey];
            sg_installed = YES;
            memset(sg_done, 0, sizeof sg_done);
            memset(sg_bytes, 0, sizeof sg_bytes);
            post(NO);
        });
    });
}

static void check(int i) {
    sg_checking[i] = YES;
    SGSingModelKind kind = chosenKind();
    NSUInteger epoch = sg_epoch;
    NSURL *arrived = arrivedFile(i), *staged = stagedFile(i);
    int64_t size = files()[i].size;
    NSString *expected = @(files()[i].sha256);
    dispatch_async(disk(), ^{
        NSFileManager *manager = NSFileManager.defaultManager;
        BOOL right = sizeAt(arrived) == size && [sha256(arrived) isEqualToString:expected];
        if (right) {
            [manager createDirectoryAtURL:staged.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [manager removeItemAtURL:staged error:nil];
            right = [manager moveItemAtURL:arrived toURL:staged error:nil];
        }
        if (!right) [manager removeItemAtURL:arrived error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (epoch != sg_epoch || kind != chosenKind()) return;
            sg_checking[i] = NO;
            sg_done[i] = right;
            sg_bytes[i] = 0;
            if (!right) {
                SGLog(@"Sing voice model: %s did not match its pinned size and hash", files()[i].path);
                if (sg_want) fail(@"A downloaded file didn't match Sing's voice model, so it wasn't kept.");
                return;
            }
            installIfComplete();
            post(NO);
        });
    });
}

static int indexOf(NSURLSessionTask *task) {
    for (int i = 0; i < kFileCount; i++) if ([task.taskDescription isEqualToString:repoPathOf(i)]) return i;
    return -1;
}

@implementation SGSingModelDelegate

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)written
 totalBytesWritten:(int64_t)total totalBytesExpectedToWrite:(int64_t)expected {
    int i = indexOf(task);
    if (i < 0 || sg_tasks[@(i)] != task) return;
    sg_bytes[i] = total;
    post(YES);
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didResumeAtOffset:(int64_t)offset
 expectedTotalBytes:(int64_t)expected {
    int i = indexOf(task);
    if (i < 0 || sg_tasks[@(i)] != task) return;
    SGLog(@"Sing voice model: %s resumed at %lld bytes", files()[i].path, offset);
    sg_bytes[i] = offset;
    post(YES);
}

// The file has to be moved before this returns: the system deletes it afterwards.
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
    int i = indexOf(task);
    if (i < 0 || !sg_want || sg_done[i] || sg_checking[i]) return;
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    if (status != 200 && status != 206) {
        sg_rejected[i] = [NSString stringWithFormat:@"The voice model's host answered %ld.", (long)status];
        return;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSError *error = nil;
    [files removeItemAtURL:arrivedFile(i) error:nil];
    if (![files moveItemAtURL:location toURL:arrivedFile(i) error:&error]) {
        sg_rejected[i] = [NSString stringWithFormat:@"The downloaded file could not be kept: %@", error.localizedDescription];
        return;
    }
    check(i);
    // A launch may have started this file again while the task that finished was still reporting in.
    NSURLSessionDownloadTask *other = sg_tasks[@(i)];
    if (other && other != task) {
        [sg_tasks removeObjectForKey:@(i)];
        [other cancel];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    int i = indexOf(task);
    if (i < 0 || (sg_tasks[@(i)] && sg_tasks[@(i)] != task)) return;
    BOOL ours = sg_tasks[@(i)] == task;
    [sg_tasks removeObjectForKey:@(i)];
    NSString *rejected = sg_rejected[i];
    sg_rejected[i] = nil;
    if (!ours || !sg_want) { post(NO); return; }   // stopped here, which kept or dropped its resume itself
    if (error) {
        keepResume(i, error.userInfo[NSURLSessionDownloadTaskResumeData], model());
        BOOL cancelled = [error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled;
        if (cancelled || (sg_fromResume[i] && !sg_restarted[i])) {
            if (!cancelled) sg_restarted[i] = YES;
            SGLog(@"Sing voice model: %s starting again after %@", files()[i].path, error.localizedDescription);
            startFile(i);
            post(NO);
            return;
        }
        fail([NSString stringWithFormat:@"The download stopped: %@", error.localizedDescription]);
        return;
    }
    if (rejected) fail(rejected);
    else post(NO);
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    void (^completion)(void) = sg_sessionCompletion;
    sg_sessionCompletion = nil;
    if (completion) completion();
}

@end

#pragma mark - the API

SGSingModelKind SGSingModelChosen(void) { return chosenKind(); }

void SGSingModelChoose(SGSingModelKind kind) {
    if (kind != SGSingModelLight) kind = SGSingModelFull;
    if (kind == chosenKind()) return;
    load();
    if (sg_want) SGSingModelCancel();
    SGSetInt(SGKeySingModel, kind);
    sg_loaded = NO;
    load();
    postChoice();
}

SGSingModelState SGSingModelCurrentState(void) {
    load();
    if (sg_installed) return SGSingModelInstalled;
    if (!sg_want) return SGSingModelMissing;
    return sg_tasks.count ? SGSingModelDownloading : SGSingModelChecking;
}

int64_t SGSingModelSize(void) {
    int64_t total = 0;
    const SGSingModelFile *selectedFiles = files();
    for (int i = 0; i < kFileCount; i++) total += selectedFiles[i].size;
    return total;
}

NSString *SGSingModelSizeTextOf(SGSingModelKind kind) {
    int64_t total = 0;
    const SGSingModelFile *selectedFiles = filesOfKind(kind);
    for (int i = 0; i < kFileCount; i++) total += selectedFiles[i].size;
    return [NSString stringWithFormat:@"%lld MB", (total + 500000) / 1000000];
}

int64_t SGSingModelReceived(void) {
    load();
    if (sg_installed) return SGSingModelSize();
    int64_t total = 0;
    const SGSingModelFile *selectedFiles = files();
    for (int i = 0; i < kFileCount; i++)
        total += sg_done[i] || sg_checking[i] ? selectedFiles[i].size : MAX(0, MIN(sg_bytes[i], selectedFiles[i].size));
    return total;
}

NSString *SGSingModelFailure(void) { return sg_failure; }

NSString *SGSingModelPath(void) {
    load();
    return sg_installed ? installedModel().path : nil;
}

NSString *SGSingModelBytesText(int64_t bytes) {
    if (bytes >= 1ll << 30) return [NSString stringWithFormat:@"%.1f GB", bytes / (double)(1ll << 30)];
    return [NSString stringWithFormat:@"%lld MB", (bytes + (1ll << 19)) >> 20];
}

NSString *SGSingModelSpaceProblem(void) {
    int64_t needed = SGSingModelSize() - SGSingModelReceived() + kHeadroom;
    // The volume is asked through the nearest folder that already exists.
    NSURL *folder = singFolder();
    while (folder.path.length > 1 && ![NSFileManager.defaultManager fileExistsAtPath:folder.path])
        folder = folder.URLByDeletingLastPathComponent;
    NSNumber *free = nil;
    [folder getResourceValue:&free forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:nil];
    if (!free || free.longLongValue >= needed) return nil;
    return [NSString stringWithFormat:@"Sing's voice model needs %@ of free space, and this iPhone has %@.",
            SGSingModelBytesText(needed), SGSingModelBytesText(free.longLongValue)];
}

void SGSingModelCheckNetwork(void (^done)(SGSingModelNetwork network)) {
    nw_path_monitor_t monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(monitor, dispatch_get_main_queue());
    __block BOOL answered = NO;
    nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
        if (answered) return;
        answered = YES;
        SGSingModelNetwork network = nw_path_get_status(path) != nw_path_status_satisfied ? SGSingModelOffline
            : nw_path_is_expensive(path) || nw_path_is_constrained(path) ? SGSingModelMetered : SGSingModelUnmetered;
        nw_path_monitor_cancel(monitor);
        done(network);
    });
    nw_path_monitor_start(monitor);
}

void SGSingModelDownload(BOOL metered) {
    load();
    if (sg_installed || sg_want) return;
    NSError *error = nil;
    if (!makeFolders(&error)) {
        sg_failure = [NSString stringWithFormat:@"The voice model's folder could not be made: %@", error.localizedDescription];
        post(NO);
        return;
    }
    SGLog(@"Sing voice model download starting, %lld of %lld bytes here, %@", SGSingModelReceived(), SGSingModelSize(),
          metered ? @"on any network" : @"off metered networks");
    sg_want = YES;
    sg_metered = metered;
    sg_failure = nil;
    memset(sg_restarted, 0, sizeof sg_restarted);
    SGSetInt(SGKeySingModelDownload, metered ? 2 : 1);
    SGSetInt(kDownloadKindKey, chosenKind());
    startMissing();
    installIfComplete();
    post(NO);
}

void SGSingModelCancel(void) {
    load();
    if (!sg_want) return;
    sg_failure = nil;
    stopTasks(YES);
    post(NO);
}

void SGSingModelRemove(void) {
    load();
    SGLog(@"Sing voice model removed");
    sg_epoch++;
    stopTasks(NO);
    sg_installed = NO;
    sg_failure = nil;
    memset(sg_done, 0, sizeof sg_done);
    memset(sg_checking, 0, sizeof sg_checking);
    memset(sg_bytes, 0, sizeof sg_bytes);
    // The warm model goes now; its files after anything already queued for them.
    SGStemWorkerPurge();
    NSURL *installed = installedModel(), *folder = staging();
    dispatch_async(disk(), ^{
        [NSFileManager.defaultManager removeItemAtURL:installed error:nil];
        [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
    });
    post(NO);
}

BOOL SGSingModelHandlesSession(NSString *identifier, void (^completion)(void)) {
    if (![identifier isEqualToString:kSessionIdentifier]) return NO;
    sg_sessionCompletion = [completion copy];
    load();
    session();   // the events come to the session once it exists again
    return YES;
}

void SGSingModelReconnect(void) {
    load();
    NSInteger mode = SGInt(SGKeySingModelDownload, 0);
    if (!mode) return;
    if (SGInt(kDownloadKindKey, SGSingModelFull) != chosenKind()) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kDownloadKindKey];
        [session() getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
            for (NSURLSessionTask *task in tasks) [task cancel];
        }];
        return;
    }
    if (sg_installed) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySingModelDownload];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kDownloadKindKey];
        return;
    }
    sg_want = YES;
    sg_metered = mode == 2;
    NSUInteger epoch = sg_epoch;
    [session() getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (epoch != sg_epoch || !sg_want) {
                for (NSURLSessionTask *task in tasks) [task cancel];
                return;
            }
            for (NSURLSessionTask *task in tasks) {
                int i = indexOf(task);
                if (i < 0 || sg_done[i] || sg_checking[i] || sg_tasks[@(i)] || ![task isKindOfClass:NSURLSessionDownloadTask.class]) {
                    [task cancel];
                    continue;
                }
                sg_tasks[@(i)] = (NSURLSessionDownloadTask *)task;
                sg_bytes[i] = task.countOfBytesReceived;
            }
            SGLog(@"Sing voice model download picked up with %lu running", (unsigned long)sg_tasks.count);
            startMissing();
            installIfComplete();
            post(NO);
        });
    }];
    post(NO);
}
