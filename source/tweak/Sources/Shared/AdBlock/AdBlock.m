#import "Core/SGCore.h"
#import "AdBlock.h"

#pragma mark - flags

// Both lists are EeveeSpotify's, kept to the flags this Spotify has.
static NSString *const adFlags[] = {
    @"ios-feature-adonappopen.enabled",
    @"ios-feature-adonappopen.cta_card_enabled",
    @"ios-nowplaying-scroll-impl.unified_leavebehind_npv_scroll_music_enabled",
    @"ios-nowplaying-scroll-impl.unified_leavebehind_npv_scroll_podcast_enabled",
    @"ios-feature-embeddedplaylist.use_unified_leavebehind_fetch",
    @"ios-adsnowplaying-embeddednpv-impl.foreground_enabled",
    @"ios-adsnowplaying-embeddednpv-impl.music_track_change_enabled",
    @"ios-adsnowplaying-embeddednpv-impl.enable_ads_on_podcast",
    @"ios-feature-adsbase.enable_ads_connect_state_observer",
    @"ios-feature-adsbase.enable_minimal_preroll_management",
    @"ios-feature-adsnowplayingui.embedded_npv_video_show_with_canvas",
    @"ios-feature-adssponsoredcontext.sponsored_playlist_v2_enabled",
    @"ios-feature-adssponsoredcontext.sponsored_context_mismatch_aderror_enabled",
    @"ios-feature-adssponsoredcontextnpbattachment.sponsored_npb_slot_fetch_enabled",
};

static NSString *const upsellFlags[] = {
    @"ios-feature-shuffletoggleupsell.is_enabled_pt2",
    @"ios-feature-shuffletoggleupsell.linear_upsell_new_style_experiment_enabled",
    @"ios-feature-shuffletoggleupsell.play_modes_upsell_new_style_experiment_enabled",
    @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled",
    @"ios-jam-freeusershuffleupsellsheetpage-impl.free_user_shuffle_upsell_sheet_enabled",
    @"ios-jam-freeuserskipupsellpage-impl.free_user_skip_upsell_sheet_enabled",
    @"ios-jam-freehostedjamsupsell-impl.free_hosted_jams_upsell_enabled",
    @"ios-reinventfree-contextualupsellpremiumpromo-impl.is_promo_cta_enabled",
    @"ios-reinventfree-contextualupsellpremiumpromo-impl.show_time_cap_upsell_with_premium_badge",
    @"ios-reinventfree-controllerui-impl.enable_video_time_cap_upsell",
    @"ios-reinventfree-controllerui-impl.enable_video_time_cap_upsell_on_search",
    @"ios-reinventfree-timecappivot-impl.music_video_upsell_enabled",
    @"ios-settings-mediaqualitypageplugin-impl.is_gbb_upsell_enabled",
    @"ios-settings-mediaqualitypageplugin-impl.should_show_pigeon_upsell",
    @"ios-system-listeningparties.preview_ended_upsell_enabled",
};

// More of what Hide ads sets, by value: the ad features off, their guards and Skip buttons pinned on, and the
// ad cards' timings pushed past use. Each key, type and value was checked against 9.1.88's and 9.1.90's flag
// tables. canvas_skeleton_enabled and podcast_like_check_enabled are 9.1.90's. Enums are left alone: the table
// does not name their values.
static NSDictionary<NSString *, NSNumber *> *adValues(void) {
    static NSDictionary *values;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        values = @{
            @"ios-adsnowplaying-embeddednpv-impl.embedded_ad_html_element_enabled": @NO,
            @"ios-adsnowplaying-embeddednpv-impl.reopen_refresh_enabled": @NO,
            @"ios-adsnowplaying-embeddednpv-impl.canvas_skeleton_enabled": @NO,
            @"ios-feature-adonappopen.core_fetch_enabled": @NO,
            @"ios-home-evopage-impl.video_brand_ads_tagline_and_logo_enabled": @NO,
            @"ios-jam-adsdisclaimersheetpage-impl.ads_disclaimer_sheet_enabled": @NO,
            @"ios-reinventfree-adunlockeligibility-impl.ad_unlocked_on_demand_enabled": @NO,
            @"ios-adsplatform-elementimpl.display_ad_prevent_dismiss_on_iawb_present": @NO,
            @"ios-adsnowplaying-embeddednpv-impl.car_connection_check_enabled": @YES,
            @"ios-adsnowplaying-embeddednpv-impl.podcast_like_check_enabled": @YES,
            @"ios-adsnowplaying-embeddednpv-impl.prevent_duplicate_element_setup": @YES,
            @"ios-feature-adonappopen.skip_button_enabled": @YES,
            @"ios-feature-nowplayingbar.show_skip_button_during_skippable_ads": @YES,
            // The table's largest delay: a card waits nearly three hours to show.
            @"ios-adsnowplaying-embeddednpv-impl.render_delay_ms": @9999999,
            @"ios-adsnowplaying-embeddednpv-impl.canvas_render_delay_ms": @9999999,
            @"ios-feature-adonappopen.skippable_ad_delay_ms": @0,
            @"ios-feature-adonappopen.cached_ad_expiration_period_seconds": @0,
            @"ios-feature-adonappopen.background_refresh_frequency_seconds": @INT32_MAX,
        };
    });
    return values;
}

static BOOL listed(NSString *key, NSString *const list[], size_t count) {
    for (size_t i = 0; i < count; i++) {
        if ([key isEqualToString:list[i]]) return YES;
    }
    return NO;
}

// The switches that force flags off, one bit each, so the forcer below can read them once.
enum { kAds = 1, kVideos = 2, kUpsells = 4 };

static unsigned switchesNow(void) {
    return (SGFlag(SGKeyHideAds, YES) ? kAds : 0) | (SGFlag(SGKeyHideSearchVideos, YES) ? kVideos : 0)
         | (SGFlag(SGKeyHideUpsells, YES) ? kUpsells : 0);
}

static NSNumber *forcedValue(NSString *key, unsigned on) {
    if (on & kAds) {
        if (listed(key, adFlags, sizeof(adFlags) / sizeof(adFlags[0]))) return @NO;
        NSNumber *value = adValues()[key];
        if (value) return value;
    }
    if ((on & kVideos) && [key isEqualToString:@"ios-feature-search.video_carousel_section_enabled"]) return @NO;
    return (on & kUpsells) && listed(key, upsellFlags, sizeof(upsellFlags) / sizeof(upsellFlags[0])) ? @NO : nil;
}

NSNumber *SGAdBlockForcedFlag(NSString *key) {
    return forcedValue(key, switchesNow());
}

// After an override from the All flags page, and locking the rows that would turn the same flag off.
// Spotify asks for every flag it has as it starts, so the running app's answer reads the switches once
// rather than four defaults lookups a flag (harness/launch); the rows read them as they are stored now.
__attribute__((constructor)) static void registerForcer(void) {
    SGRegisterFlagForcer(NO, ^id(NSString *key) {
        static unsigned atLaunch;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ atLaunch = switchesNow(); });
        return atLaunch ? forcedValue(key, atLaunch) : nil;
    }, ^id(NSString *key) { return SGAdBlockForcedFlag(key); });
}

#pragma mark - counters

static NSString *const kCounts = @"spotifyglass.adblock.counts";
static NSString *const labels[] = {
    @"Ad services", @"Upsell services", @"Popups", @"Page components", @"Feed sections", @"Requests", @"Config rewrites",
};
static NSMutableDictionary<NSString *, NSNumber *> *sg_counts;
static BOOL sg_unsaved;   // checks counted since the counts were last written

static NSString *checkedKey(NSString *label) {
    return [label stringByAppendingString:@" checked"];
}

// The kinds whose hooks count what they look at. The services are stubs Spotify loads, with nothing to look at.
static BOOL countsChecks(NSString *label) {
    return [@[@"Popups", @"Page components", @"Feed sections", @"Requests", @"Config rewrites"] containsObject:label];
}

// Counting happens on whichever thread the hook ran on, the page reads on the main one.
static NSMutableDictionary<NSString *, NSNumber *> *countsLocked(void) {
    if (!sg_counts) {
        sg_counts = [[NSUserDefaults.standardUserDefaults dictionaryForKey:kCounts] mutableCopy] ?: [NSMutableDictionary dictionary];
        // Counts kept before checks were counted start again, so "stopped of checked" counts both from one moment.
        if (sg_counts.count && !sg_counts[checkedKey(@"Requests")]) {
            [sg_counts removeAllObjects];
            sg_counts[checkedKey(@"Requests")] = @0;
            [NSUserDefaults.standardUserDefaults setObject:sg_counts forKey:kCounts];
        }
    }
    return sg_counts;
}

void SGAdBlockCountOne(NSString *label) {
    @synchronized (kCounts) {
        NSMutableDictionary<NSString *, NSNumber *> *counts = countsLocked();
        counts[label] = @(counts[label].unsignedIntegerValue + 1);
        // Counting runs on whichever thread a request finishes on: writing here synchronously deadlocks
        // the app (a defaults write posts its observer relays on this queue while the main thread waits
        // on it; hang 2026-10-23). The counts keep in memory and the leaving observer writes them once.
        sg_unsaved = YES;
    }
}

void SGAdBlockSawOne(NSString *label) {
    @synchronized (kCounts) {
        NSMutableDictionary<NSString *, NSNumber *> *counts = countsLocked();
        NSString *key = checkedKey(label);
        counts[key] = @(counts[key].unsignedIntegerValue + 1);
        sg_unsaved = YES;
    }
}

NSUInteger SGAdBlockChecked(NSString *label) {
    @synchronized (kCounts) {
        return countsChecks(label) ? countsLocked()[checkedKey(label)].unsignedIntegerValue : NSNotFound;
    }
}

// The checks counted since the last stop, written as Spotify leaves the screen.
__attribute__((constructor)) static void saveChecksOnLeaving(void) {
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        @synchronized (kCounts) {
            if (!sg_unsaved) return;
            [NSUserDefaults.standardUserDefaults setObject:countsLocked() forKey:kCounts];
            sg_unsaved = NO;
        }
    }];
}

NSArray<NSString *> *SGAdBlockLabels(void) {
    return [NSArray arrayWithObjects:labels count:sizeof(labels) / sizeof(labels[0])];
}

NSUInteger SGAdBlockCount(NSString *label) {
    @synchronized (kCounts) {
        NSDictionary<NSString *, NSNumber *> *counts = countsLocked();
        if (label) return counts[label].unsignedIntegerValue;
        NSUInteger total = 0;
        for (NSString *each in SGAdBlockLabels()) total += counts[each].unsignedIntegerValue;
        return total;
    }
}

void SGResetAdBlock(void) {
    @synchronized (kCounts) {
        sg_counts = [NSMutableDictionary dictionary];
        sg_unsaved = NO;
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kCounts];
    }
}
