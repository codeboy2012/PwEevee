#import "Core/SGCore.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import <objc/runtime.h>

NSArray *SGArtworkOrder(void) { return @[@"canvas", @"applemusic"]; }
void SGLogMessage(NSString *message) {}

static void require(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}

static void setViews(NSArray *order, SGLockArtwork style, BOOL lyrics) {
    [NSUserDefaults.standardUserDefaults setObject:order forKey:SGKeyLockScreenStarViews];
    SGSetInt(SGKeyFullScreenArtwork, style);
    SGLockScreenCanvasLyricsSetEnabled(lyrics);
}

static NSUInteger preferenceWrites;
static void (*setBoolOriginal)(id, SEL, BOOL, NSString *);
static void (*setIntOriginal)(id, SEL, NSInteger, NSString *);
static void (*setObjectOriginal)(id, SEL, id, NSString *);

static void countedBool(id store, SEL selector, BOOL value, NSString *key) {
    if ([key hasPrefix:@"spotifyglass."]) preferenceWrites++;
    setBoolOriginal(store, selector, value, key);
}

static void countedInt(id store, SEL selector, NSInteger value, NSString *key) {
    if ([key hasPrefix:@"spotifyglass."]) preferenceWrites++;
    setIntOriginal(store, selector, value, key);
}

static void countedObject(id store, SEL selector, id value, NSString *key) {
    if ([key hasPrefix:@"spotifyglass."]) preferenceWrites++;
    setObjectOriginal(store, selector, value, key);
}

static void checkPreferencesSettle(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    Method method = class_getInstanceMethod(NSUserDefaults.class, @selector(setBool:forKey:));
    setBoolOriginal = (void *)method_setImplementation(method, (IMP)countedBool);
    method = class_getInstanceMethod(NSUserDefaults.class, @selector(setInteger:forKey:));
    setIntOriginal = (void *)method_setImplementation(method, (IMP)countedInt);
    method = class_getInstanceMethod(NSUserDefaults.class, @selector(setObject:forKey:));
    setObjectOriginal = (void *)method_setImplementation(method, (IMP)countedObject);

    SGSetEnabled(SGKeyLockScreenStar, NO);
    SGSetEnabled(SGKeyLockScreenExclusiveLyrics, YES);
    setViews(@[@"canvas", @"fill", @"lyrics"], SGLockArtworkMotion, NO);
    SGLockScreenSetEffectiveArtwork(SGLockArtworkFill);
    __block NSUInteger refreshes = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                require(++refreshes < 64, @"Defaults refreshes must stop rather than enqueue themselves forever");
                SGLockScreenStarEnsureView();
                SGLockScreenStarEnsureView();
            });
        }];
    preferenceWrites = 0;
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:store];
    for (NSUInteger i = 0; i < 8; i++)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    require(refreshes > 0, @"The queued defaults observers must run");
    require(preferenceWrites == 0, @"A settled star-disabled hierarchy must not write preferences during defaults refreshes");
    require(SGLockScreenEffectiveArtwork() == SGLockArtworkFill,
            @"Unrelated defaults refreshes must preserve this track's Canvas fallback with star cycling off");
    [NSNotificationCenter.defaultCenter removeObserver:observer];

    NSArray *views = @[@"canvas", @"lyrics", @"fill", @"colorful", @"default"];
    for (NSString *view in views) {
        [store setObject:@[view] forKey:SGKeyLockScreenStarViews];
        SGLockScreenStarEnsureView();
        preferenceWrites = 0;
        for (NSUInteger i = 0; i < 20; i++) {
            SGLockScreenStarEnsureView();
            SGLockScreenStarSelectView(view);
        }
        require(preferenceWrites == 0, @"Every already-selected style must be idempotent, including explicit selection");
        require([SGLockScreenCurrentStarView() isEqualToString:view], @"Every style must remain available");
    }

    SGSetEnabled(SGKeyLockScreenLyrics, YES);
    SGLockScreenStarSelectView(@"lyrics");
    require(!SGFlag(SGKeyLockScreenLyrics, NO), @"Artwork Lyrics must suppress artist-name lyrics when exclusive");
    preferenceWrites = 0;
    for (NSUInteger i = 0; i < 20; i++) SGLockScreenStarSelectView(@"lyrics");
    require(preferenceWrites == 0, @"Reselecting Lyrics must not restore then suppress artist-name lyrics repeatedly");
    SGLockScreenStarSelectView(@"canvas");
    require(SGFlag(SGKeyLockScreenLyrics, NO), @"Leaving artwork Lyrics must restore artist-name lyrics");
    SGLockScreenStarSelectView(@"lyrics");
    SGSetEnabled(SGKeyLockScreenExclusiveLyrics, NO);
    SGLockScreenLyricsExclusivityChanged(NO);
    require(SGFlag(SGKeyLockScreenLyrics, NO), @"Turning exclusivity off must restore artist-name lyrics");
    preferenceWrites = 0;
    SGLockScreenStarSelectView(@"lyrics");
    require(preferenceWrites == 0 && SGFlag(SGKeyLockScreenLyrics, NO),
            @"Both lyric features must stay enabled without redundant writes when exclusivity is off");

    SGSetEnabled(SGKeyLockScreenStar, YES);
    [store setObject:@[@"canvas", @"fill", @"lyrics"] forKey:SGKeyLockScreenStarViews];
    SGLockScreenStarSelectView(@"fill");
    preferenceWrites = 0;
    SGLockScreenStarEnsureView();
    require(preferenceWrites == 0 && [SGLockScreenCurrentStarView() isEqualToString:@"fill"],
            @"Star cycling must preserve a manually selected enabled view");
    [store setObject:@[@"canvas", @"lyrics"] forKey:SGKeyLockScreenStarViews];
    SGLockScreenStarEnsureView();
    require([SGLockScreenCurrentStarView() isEqualToString:@"canvas"], @"Disabling the selected style must select the first enabled style");
    SGLockScreenStarAdvanceView();
    require([SGLockScreenCurrentStarView() isEqualToString:@"lyrics"], @"The star must advance to the next enabled style");
    SGLockScreenStarAdvanceView();
    require([SGLockScreenCurrentStarView() isEqualToString:@"canvas"], @"The star must wrap through the configured order");
    puts("PASS: defaults observers settle without writes, per-track fallback survives refreshes, and all styles/cycling/lyric exclusivity remain available");
}

static void checkOptionalLockScreenLyrics(void) {
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    [store removeObjectForKey:SGKeyLockScreenLyricsView];
    require(SGLockScreenLyricsViewEnabled(), @"Existing Lyrics choices remain enabled until switched off");
    SGSetEnabled(SGKeyLockScreenExclusiveLyrics, YES);
    SGSetEnabled(SGKeyLockScreenLyrics, YES);
    SGSetEnabled(SGKeyLockScreenStar, YES);
    NSArray *saved = @[@"canvas", @"lyrics", @"fill", @"default"];
    setViews(saved, SGLockArtworkMotion, NO);
    SGLockScreenStarSelectView(@"lyrics");
    require(!SGFlag(SGKeyLockScreenLyrics, NO), @"Selecting Lyrics still applies lyric exclusivity");

    SGSetEnabled(SGKeyLockScreenLyricsView, NO);
    SGLockScreenStarEnsureView();
    SGLockScreenLyricsExclusivityChanged(YES);
    require(SGLockScreenArtwork() == SGLockArtworkMotion, @"Switching lyrics off keeps an enabled artwork view");
    require(SGFlag(SGKeyLockScreenLyrics, NO), @"Switching the full-screen view off restores artist-name lyrics");
    require([SGLockScreenStarViewOrder() isEqual:saved], @"The lyrics switch must preserve the saved hierarchy");
    require([SGLockScreenAvailableStarViews() isEqual:@[@"canvas", @"fill", @"default"]],
            @"Disabled Lyrics is excluded from the available views");
    SGLockScreenStarSelectView(@"lyrics");
    require(SGLockScreenArtwork() == SGLockArtworkMotion, @"Direct selection cannot bypass the lyrics switch");
    for (NSUInteger i = 0; i < 6; i++) {
        SGLockScreenStarAdvanceView();
        require(SGLockScreenArtwork() != SGLockArtworkLyrics, @"Star cycling must skip disabled Lyrics");
    }
    SGLockScreenStarSelectView(@"canvas");
    require(SGLockScreenSkipUnavailableMotion() == SGLockArtworkFill,
            @"Missing Canvas falls through to artwork instead of disabled Lyrics");
    SGSetEnabled(SGKeyLockScreenCanvasLyrics, YES);
    require(!SGLockScreenCanvasLyricsEnabled(), @"The switch also suppresses legacy lyrics over moving artwork");
    SGSetEnabled(SGKeyLockScreenCanvasLyrics, NO);

    NSArray *views = @[@"canvas", @"fill", @"colorful", @"default"];
    NSArray *styles = @[@(SGLockArtworkMotion), @(SGLockArtworkFill), @(SGLockArtworkEverySong), @(SGLockArtworkOff)];
    for (NSUInteger i = 0; i < views.count; i++) {
        setViews(@[views[i]], SGLockArtworkLyrics, NO);
        SGLockScreenStarEnsureView();
        require(SGLockScreenArtwork() == [styles[i] integerValue], @"Every non-lyrics artwork style remains available");
    }
    setViews(@[@"lyrics"], SGLockArtworkLyrics, NO);
    SGLockScreenStarEnsureView();
    require(SGLockScreenArtwork() == SGLockArtworkOff, @"A Lyrics-only hierarchy falls back to iOS artwork while disabled");
    require([SGLockScreenStarViewOrder() isEqual:@[@"lyrics"]], @"A Lyrics-only hierarchy is retained for re-enabling");
    preferenceWrites = 0;
    for (NSUInteger i = 0; i < 20; i++) SGLockScreenStarEnsureView();
    require(preferenceWrites == 0, @"Disabled Lyrics must not reintroduce the defaults-write loop");

    SGSetEnabled(SGKeyLockScreenLyricsView, YES);
    SGLockScreenStarEnsureView();
    require(SGLockScreenArtwork() == SGLockArtworkLyrics, @"Re-enabling restores the saved Lyrics-only choice");
    setViews(saved, SGLockArtworkMotion, NO);
    require([SGLockScreenAvailableStarViews() isEqual:saved], @"Re-enabling restores the full configured order");
    require(SGLockScreenSkipUnavailableMotion() == SGLockArtworkLyrics, @"Lyrics can be used as fallback again when enabled");
    puts("PASS: optional lock-screen lyrics, artwork-only fallback/cycling, saved hierarchy, artist-name lyrics and idempotent refreshes");
}
int main(void) {
    @autoreleasepool {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        [store removeObjectForKey:SGKeyLockScreenLyricsView];
        SGSetEnabled(SGKeyLockScreenStar, YES);
        SGSetEnabled(SGKeyLockScreenLyrics, NO);
        [store removeObjectForKey:@"spotifyglass.lockscreen.starViews.migrated"];

        setViews(@[@"canvas", @"fill", @"colorful", @"default"], SGLockArtworkMotion, NO);
        SGLockScreenStarEnsureView();
        require([SGLockScreenCurrentStarView() isEqual:@"canvas"], @"Canvas is the configured first style");
        require(SGLockScreenSkipUnavailableMotion() == SGLockArtworkFill, @"Missing Canvas must use the next enabled style");
        require(SGLockScreenEffectiveArtwork() == SGLockArtworkFill, @"Fallback style must be applied to this track");
        require(SGLockScreenArtwork() == SGLockArtworkMotion, @"Fallback must not overwrite the configured style");
        require([SGLockScreenCurrentStarView() isEqual:@"canvas"], @"Fallback must not move the selected style");
        require([SGLockScreenStarViewOrder() isEqualToArray:@[@"canvas", @"fill", @"colorful", @"default"]],
                @"Fallback must not change the hierarchy");

        SGLockScreenSetEffectiveArtwork(SGLockScreenArtwork());
        require(SGLockScreenEffectiveArtwork() == SGLockArtworkMotion, @"A new track must retry the configured Canvas style");
        require(SGLockScreenSkipUnavailableMotion() == SGLockArtworkFill, @"Canvas fallback must follow the configured order again");

        setViews(@[@"fill", @"canvas", @"default"], SGLockArtworkMotion, NO);
        SGSetEnabled(SGKeyLockScreenStar, NO);
        SGLockScreenStarEnsureView();
        require(SGLockScreenArtwork() == SGLockArtworkFill, @"When Canvas is not first, use the first configured style");
        require(SGLockScreenEffectiveArtwork() == SGLockArtworkFill, @"Non-Canvas first style must bypass Canvas lookup");

        SGSetEnabled(SGKeyLockScreenStar, YES);
        setViews(@[@"canvas", @"lyrics", @"fill", @"colorful", @"default"], SGLockArtworkMotion, NO);
        SGLockScreenStarEnsureView();
        require(SGLockScreenSkipUnavailableMotion() == SGLockArtworkLyrics, @"Lyrics must be the next fallback when ordered after Canvas");
        require(SGLockScreenEffectiveArtwork() == SGLockArtworkLyrics, @"Lyrics fallback must activate the track-local lyrics style");
        SGLockScreenSetEffectiveArtwork(SGLockScreenArtwork());
        require(SGLockScreenEffectiveArtwork() == SGLockArtworkMotion, @"Canvas must be retried after a lyrics fallback on the previous track");

        NSArray *keys = @[@"canvas", @"lyrics", @"fill", @"colorful", @"default"];
        NSArray *styles = @[@(SGLockArtworkMotion), @(SGLockArtworkLyrics), @(SGLockArtworkFill),
                            @(SGLockArtworkEverySong), @(SGLockArtworkOff)];
        for (NSUInteger i = 0; i < keys.count; i++) {
            setViews(@[keys[i]], SGLockArtworkFill, NO);
            SGLockScreenStarEnsureView();
            require(SGLockScreenArtwork() == [styles[i] integerValue], @"Each single enabled view must select its style");
            require([SGLockScreenCurrentStarView() isEqual:keys[i]], @"Single-choice mode must report its selected style");
        }

        setViews(@[@"canvas", @"canvasLyrics", @"fill"], SGLockArtworkMotion, NO);
        require([SGLockScreenStarViewOrder() isEqualToArray:@[@"canvas", @"lyrics", @"fill"]],
                @"Legacy Canvas-lyrics style keys must migrate to Lyrics");
        setViews(@[@"canvas", @"bad", @"canvas", @"fill"], SGLockArtworkMotion, NO);
        require([SGLockScreenStarViewOrder() isEqualToArray:@[@"canvas", @"fill"]], @"Unknown and repeated views must be removed");

        setViews(@[], SGLockArtworkFill, NO);
        SGSetEnabled(SGKeyLockScreenStar, NO);
        require(SGLockScreenArtwork() == SGLockArtworkFill, @"An empty cycle must leave manual artwork selection intact");
        puts("PASS: ordered track-local fallback, Canvas retry, non-Canvas priority, Lyrics fallback and style migration");
        checkPreferencesSettle();
        checkOptionalLockScreenLyrics();
    }
    return 0;
}
