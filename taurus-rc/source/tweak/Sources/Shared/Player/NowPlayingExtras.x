// NowPlayingExtras.h says what this is and why it stores nothing of Spotify's.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Shared/Player/NowPlayingExtras.h"

// Read on whatever thread Spotify sets the info from, written on the main one.
static NSObject *sg_lock;
static NSMutableDictionary<NSString *, NSDictionary *> *sg_extras;   // by owner
static NSMutableDictionary<NSString *, NSString *> *sg_titles;       // by owner
static double sg_elapsed, sg_rate;
static CFAbsoluteTime sg_clockAt;

static NSString *titleWithoutTrackNumber(NSString *title) {
    NSString *trimmed = [title stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger index = 0;
    while (index < trimmed.length) {
        unichar character = [trimmed characterAtIndex:index];
        if (character < '0' || character > '9') break;
        index++;
    }
    if (!index || index == trimmed.length) return trimmed;
    unichar separator = [trimmed characterAtIndex:index];
    if (separator != '.' && separator != ')' && separator != '-' && separator != ':') return trimmed;
    index++;
    NSUInteger numberEnd = index;
    while (index < trimmed.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[trimmed characterAtIndex:index]]) index++;
    return index > numberEnd && index < trimmed.length ? [trimmed substringFromIndex:index] : trimmed;
}

BOOL SGNowPlayingTitlesMatch(id left, id right) {
    if (![left isKindOfClass:NSString.class] || ![right isKindOfClass:NSString.class]) return NO;
    NSString *leftTitle = left;
    NSString *rightTitle = right;
    if ([leftTitle isEqualToString:rightTitle]) return YES;
    return [titleWithoutTrackNumber(leftTitle) isEqualToString:titleWithoutTrackNumber(rightTitle)];
}

// `stale` are an owner's old keys: the info the getter gives back can still carry them, and the hook puts
// back only the extras that are current.
static void resend(NSArray *stale) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSMutableDictionary *info = [center.nowPlayingInfo mutableCopy];
    if (!info) return;
    [info removeObjectsForKeys:stale];
    @synchronized (sg_lock) {
        if (sg_clockAt > 0) info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(sg_elapsed + sg_rate * (CFAbsoluteTimeGetCurrent() - sg_clockAt));
    }
    center.nowPlayingInfo = info;
}

void SGNowPlayingSetExtras(NSString *owner, NSDictionary *extras, NSString *title) {
    NSDictionary *old;
    @synchronized (sg_lock) {
        old = sg_extras[owner];
        sg_extras[owner] = extras.count ? extras : nil;
        sg_titles[owner] = extras.count ? title : nil;
    }
    if (extras.count) {
        resend(old.allKeys ?: @[]);
        return;
    }
    // Cleared, they are taken off if they are still on: the next track can have the same title, and then
    // the last track's artwork or ISRC rode on its info.
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    for (id key in old) {
        if (![info[key] isEqual:old[key]]) continue;
        resend(old.allKeys);
        return;
    }
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    NSMutableDictionary *added = nil;
    @synchronized (sg_lock) {
        if (info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
            sg_elapsed = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
            // A rate left out runs at 1, as LockScreenLyrics.x reads it.
            NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
            sg_rate = rate ? rate.doubleValue : 1;
            sg_clockAt = CFAbsoluteTimeGetCurrent();
        }
        id title = info[MPMediaItemPropertyTitle];
        for (NSString *owner in sg_extras) {
            if (!SGNowPlayingTitlesMatch(title, sg_titles[owner])) continue;
            if (!added) added = [NSMutableDictionary dictionary];
            [added addEntriesFromDictionary:sg_extras[owner]];
        }
    }
    if (!added) {
        %orig;
        return;
    }
    NSMutableDictionary *withExtras = [info mutableCopy];
    [withExtras addEntriesFromDictionary:added];
    %orig(withExtras);
}
%end

%ctor {
    sg_lock = [NSObject new];
    sg_extras = [NSMutableDictionary dictionary];
    sg_titles = [NSMutableDictionary dictionary];
    %init;
}
