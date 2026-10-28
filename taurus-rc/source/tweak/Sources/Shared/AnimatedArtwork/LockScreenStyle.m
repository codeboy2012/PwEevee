// Saved choices stay separate from a track's temporary fallback artwork.
#import "Core/SGCore.h"
#import "AnimatedArtwork.h"
#import "Shared/LockScreenArtwork/LockScreenArtwork.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"

static NSString *const kStarCanvas = @"canvas";
static NSString *const kStarLyrics = @"lyrics";
static NSString *const kLegacyStarCanvasLyrics = @"canvasLyrics";
static NSString *const kStarFill = @"fill";
static NSString *const kStarDefault = @"default";
static NSString *const kStarColorful = @"colorful";
static NSString *const kArtistLyricsWasEnabled = @"spotifyglass.lockscreen.artistLyricsWasEnabled";
static NSString *const kStarViewsMigrated = @"spotifyglass.lockscreen.starViews.migrated";
static SGLockArtwork sg_effectiveArtwork;

static NSArray<NSString *> *defaultStarViewOrder(void) {
    return @[kStarCanvas, kStarLyrics, kStarFill, kStarColorful, kStarDefault];
}

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
            SGMigrateKey(SGKeyLockScreenMotion, SGKeyFullScreenArtwork);
            SGMigrateKey(SGKeyLegacyLockScreenArtwork, SGKeyFullScreenArtwork);
            if (![store objectForKey:SGKeyFullScreenArtwork]) {
                SGSetInt(SGKeyFullScreenArtwork, SGFlag(SGKeyLegacyLockScreenArtwork, YES)
                         ? SGLockArtworkMotion : SGLockArtworkOff);
            }
            NSInteger stored = SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
            if (stored == SGLockArtworkLyrics) {
                SGLockScreenCanvasLyricsSetEnabled(NO);
            } else if (SGLockArtworkHasMotion((SGLockArtwork)stored) && SGLockScreenCanvasLyricsEnabled()) {
                SGSetInt(SGKeyFullScreenArtwork, SGLockArtworkLyrics);
                SGLockScreenCanvasLyricsSetEnabled(NO);
            }
            if (![store objectForKey:SGKeyMotionSources] && [store objectForKey:SGKeyLockScreenArtworkSources]) {
                NSArray<NSString *> *legacy = SGArtworkOrder();
                if (legacy.count) [store setObject:legacy forKey:SGKeyMotionSources];
            }
            sg_effectiveArtwork = (SGLockArtwork)SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
        });
        return (SGLockArtwork)SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
    }
    return SGLockArtworkOff;
}

SGLockArtwork SGLockScreenEffectiveArtwork(void) {
    SGLockScreenArtwork();
    return sg_effectiveArtwork;
}

void SGLockScreenSetEffectiveArtwork(SGLockArtwork artwork) {
    SGLockScreenArtwork();
    if (sg_effectiveArtwork == artwork) return;
    sg_effectiveArtwork = artwork;
    [NSNotificationCenter.defaultCenter postNotificationName:SGNotificationLockScreenEffectiveArtworkChanged object:nil];
}

NSArray<NSString *> *SGLockScreenStarViewOrder(void) {
    id stored = [NSUserDefaults.standardUserDefaults arrayForKey:SGKeyLockScreenStarViews];
    if (![stored isKindOfClass:NSArray.class]) return defaultStarViewOrder();
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    for (id key in (NSArray *)stored) {
        NSString *normalized = [key isEqual:kLegacyStarCanvasLyrics] ? kStarLyrics : key;
        if (([normalized isEqual:kStarCanvas] || [normalized isEqual:kStarLyrics] || [normalized isEqual:kStarFill]
             || [normalized isEqual:kStarDefault] || [normalized isEqual:kStarColorful])
            && ![order containsObject:normalized]) {
            [order addObject:normalized];
        }
    }
    if (!SGFlag(kStarViewsMigrated, NO)) {
        if (order.count) {
            for (NSString *key in @[kStarColorful, kStarDefault]) {
                if (![order containsObject:key]) [order addObject:key];
            }
        }
        [NSUserDefaults.standardUserDefaults setObject:order forKey:SGKeyLockScreenStarViews];
        SGSetEnabled(kStarViewsMigrated, YES);
    }
    return order.count ? order : defaultStarViewOrder();
}

BOOL SGLockScreenLyricsViewEnabled(void) {
    return SGEnabled(SGKeyLockScreenLyricsView);
}

NSArray<NSString *> *SGLockScreenAvailableStarViews(void) {
    NSArray<NSString *> *order = SGLockScreenStarViewOrder();
    if (SGLockScreenLyricsViewEnabled()) return order;
    NSMutableArray<NSString *> *available = [order mutableCopy];
    [available removeObject:kStarLyrics];
    return available.count ? available : @[kStarDefault];
}

NSString *SGLockScreenCurrentStarView(void) {
    SGLockArtwork artwork = SGLockScreenArtwork();
    if (artwork == SGLockArtworkOff) return kStarDefault;
    if (artwork == SGLockArtworkEverySong) return kStarColorful;
    if (artwork == SGLockArtworkFill) return kStarFill;
    if (artwork == SGLockArtworkLyrics || SGLockScreenCanvasLyricsEnabled()) return kStarLyrics;
    return artwork == SGLockArtworkMotion ? kStarCanvas : nil;
}

NSString *SGLockScreenStarViewName(NSString *view) {
    if ([view isEqualToString:kStarCanvas]) return @"Canvas";
    if ([view isEqualToString:kStarLyrics]) return @"Lyrics";
    if ([view isEqualToString:kStarFill]) return @"Fill";
    if ([view isEqualToString:kStarColorful]) return @"Colourful";
    return @"Default";
}

void SGLockScreenStarSelectView(NSString *view) {
    if ([view isEqualToString:kStarLyrics] && !SGLockScreenLyricsViewEnabled())
        view = SGLockScreenAvailableStarViews().firstObject;
    SGLockArtwork artwork;
    if ([view isEqualToString:kStarDefault]) {
        artwork = SGLockArtworkOff;
    } else if ([view isEqualToString:kStarColorful]) {
        artwork = SGLockArtworkEverySong;
    } else if ([view isEqualToString:kStarFill]) {
        artwork = SGLockArtworkFill;
    } else if ([view isEqualToString:kStarLyrics]) {
        artwork = SGLockArtworkLyrics;
    } else if ([view isEqualToString:kStarCanvas]) {
        artwork = SGLockArtworkMotion;
    } else return;
    if (SGLockScreenArtwork() != artwork) SGSetInt(SGKeyFullScreenArtwork, artwork);
    SGLockScreenCanvasLyricsSetEnabled(NO);
    SGLockScreenSetEffectiveArtwork(SGLockScreenArtwork());
}

void SGLockScreenStarEnsureView(void) {
    NSArray<NSString *> *order = SGLockScreenAvailableStarViews();
    if (!order.count) return;
    NSString *current = SGLockScreenCurrentStarView();
    NSString *selected = SGHidden(SGKeyLockScreenStar) && current && [order containsObject:current]
        ? current : order.firstObject;
    if (![selected isEqualToString:current]) SGLockScreenStarSelectView(selected);
}

void SGLockScreenStarAdvanceView(void) {
    NSArray<NSString *> *order = SGLockScreenAvailableStarViews();
    if (!order.count) return;
    NSString *current = SGLockScreenCurrentStarView();
    SGLockArtwork effective = SGLockScreenEffectiveArtwork();
    if (current && [current isEqualToString:kStarCanvas] && effective != SGLockArtworkMotion) {
        current = effective == SGLockArtworkLyrics ? kStarLyrics
            : effective == SGLockArtworkFill ? kStarFill
            : effective == SGLockArtworkEverySong ? kStarColorful : kStarDefault;
    }
    NSUInteger index = current ? [order indexOfObject:current] : NSNotFound;
    NSString *next = order[index == NSNotFound ? 0 : (index + 1) % order.count];
    SGLockScreenStarSelectView(next);
    SGLog(@"lock star: switched to %@", next);
}

SGLockArtwork SGLockScreenSkipUnavailableMotion(void) {
    NSArray<NSString *> *order = SGLockScreenAvailableStarViews();
    NSString *current = SGLockScreenCurrentStarView();
    NSUInteger index = current ? [order indexOfObject:current] : NSNotFound;
    for (NSUInteger step = 1; step <= order.count; step++) {
        NSString *next = order[index == NSNotFound ? step - 1 : (index + step) % order.count];
        if ([next isEqualToString:kStarCanvas]) continue;
        SGLockArtwork artwork = [next isEqualToString:kStarLyrics] ? SGLockArtworkLyrics
            : [next isEqualToString:kStarFill] ? SGLockArtworkFill
            : [next isEqualToString:kStarColorful] ? SGLockArtworkEverySong : SGLockArtworkOff;
        SGLockScreenSetEffectiveArtwork(artwork);
        SGLog(@"lock motion: no animated source; using %@ for this track", SGLockScreenStarViewName(next));
        return artwork;
    }
    SGLockScreenSetEffectiveArtwork(SGLockArtworkOff);
    SGLog(@"lock motion: no animated source or other enabled view; using iOS default artwork for this track");
    return SGLockArtworkOff;
}

BOOL SGLockScreenCanvasLyricsEnabled(void) {
    BOOL canvas = SGLockScreenLyricsViewEnabled() && SGHidden(SGKeyLockScreenCanvasLyrics);
    if (canvas && SGFlag(SGKeyLockScreenLyrics, NO) && SGEnabled(SGKeyLockScreenExclusiveLyrics)) {
        SGSetEnabled(kArtistLyricsWasEnabled, YES);
        SGSetEnabled(SGKeyLockScreenLyrics, NO);
    }
    return canvas;
}

CGFloat SGLockScreenCoverArtworkScale(void) {
    return (CGFloat)SGInt(SGKeyLockScreenCoverArtworkScale, 50) / 100.0;
}

void SGLockScreenCanvasLyricsSetEnabled(BOOL enabled) {
    if (SGHidden(SGKeyLockScreenCanvasLyrics) != enabled) SGSetEnabled(SGKeyLockScreenCanvasLyrics, enabled);
    SGLockScreenLyricsExclusivityChanged(SGEnabled(SGKeyLockScreenExclusiveLyrics));
}

void SGLockScreenLyricsExclusivityChanged(BOOL enabled) {
    SGLockArtwork artwork = (SGLockArtwork)SGInt(SGKeyFullScreenArtwork, SGLockArtworkOff);
    BOOL lockLyrics = SGLockScreenLyricsViewEnabled() && (artwork == SGLockArtworkLyrics
        || (SGHidden(SGKeyLockScreenCanvasLyrics) && SGLockArtworkHasMotion(artwork)));
    if (enabled && lockLyrics && SGFlag(SGKeyLockScreenLyrics, NO)) {
        SGSetEnabled(kArtistLyricsWasEnabled, YES);
        SGSetEnabled(SGKeyLockScreenLyrics, NO);
    } else if ((!enabled || !lockLyrics) && SGFlag(kArtistLyricsWasEnabled, NO)) {
        SGSetEnabled(SGKeyLockScreenLyrics, YES);
        SGSetEnabled(kArtistLyricsWasEnabled, NO);
    }
}

void SGLockScreenArtistLyricsChanged(BOOL enabled) {
    if (enabled && SGEnabled(SGKeyLockScreenExclusiveLyrics)) {
        for (NSString *view in SGLockScreenAvailableStarViews()) {
            if (![view isEqualToString:kStarLyrics]) {
                SGLockScreenStarSelectView(view);
                return;
            }
        }
        SGLockScreenLyricsExclusivityChanged(YES);
    } else if (!enabled) {
        SGSetEnabled(kArtistLyricsWasEnabled, NO);
    }
}
