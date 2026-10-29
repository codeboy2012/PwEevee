#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// AVFoundation's aggregate tasks inherit NSURLSessionTask but throw from its request getters.
static inline NSURLRequest *SGURLSessionTaskRequest(NSURLSessionTask *task, BOOL original) {
    if ([task isKindOfClass:AVAssetDownloadTask.class]
        || [task isKindOfClass:AVAggregateAssetDownloadTask.class]) return nil;
    @try {
        return original ? task.originalRequest : task.currentRequest;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static inline NSURL *SGURLSessionTaskURL(NSURLSessionTask *task) {
    return SGURLSessionTaskRequest(task, NO).URL ?: SGURLSessionTaskRequest(task, YES).URL;
}
