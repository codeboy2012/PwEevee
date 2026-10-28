#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "AdBlock.h"
#import "Shared/Privacy/Privacy.h"

NSString *const SGFakePremiumWarning = @"This is the part of EeveeSpotify Spotify's takedown went after, and it has not been tested here. It can end in a forced logout or worse for the account. A Premium account gains nothing from it.";

static UIViewController *adFlagsPage(void) {
    return [[SGModPage alloc] initWithTitle:@"Ad and upsell flags" intro:SGRestartNote sections:@[
        SGNotedSection(@"Ads", @[
            SGKillRow(@"Block the ad when the app opens", @"ios-feature-adonappopen.enabled"),
            SGKillRow(@"Block its CTA card", @"ios-feature-adonappopen.cta_card_enabled"),
        ], @"Locked while Hide ads is on."),
        SGNotedSection(@"Upsells", @[
            SGKillRow(@"Hide the shuffle toggle upsell", @"ios-feature-shuffletoggleupsell.is_enabled_pt2"),
            SGKillRow(@"Hide the shuffle upsell in the video player", @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled"),
        ], @"Locked while Hide upsells is on."),
        SGSection(@"Reduce interventions", @[
            SGFlagRow(@"Reduce interventions", @"ios-messaging-reduceinterventions-impl.enabled"),
        ]),
        SGSection(@"Tooltips", @[
            SGKillRow(@"Hide the smart shuffle helper", @"ios-messaging-reduceinterventions-impl.enable_message_smart_shuffle_helper_tooltip"),
            SGKillRow(@"Hide the data saver tip", @"ios-feature-nowplayingbar.data_saver_tooltip"),
            SGKillRow(@"Hide the player suggestions upsell", @"ios-messaging-reduceinterventions-impl.enable_message_reinvent_free_n_p_v_suggestions_upsell"),
            SGKillRow(@"Hide the AI playlist creation tip", @"ios-messaging-reduceinterventions-impl.enable_message_your_library_ai_playlist_creation_tooltip"),
            SGKillRow(@"Hide the watch feed explorer tip", @"ios-messaging-reduceinterventions-impl.enable_message_watch_feed_entity_explorer_tooltip"),
            SGKillRow(@"Hide the account switching tip", @"ios-messaging-reduceinterventions-impl.enable_message_account_switching_tooltip"),
            SGKillRow(@"Hide the concert notifications tip", @"ios-messaging-reduceinterventions-impl.enable_message_live_events_concert_notifications_tooltip"),
            SGKillRow(@"Hide the live event tip", @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_safe_tooltip"),
            SGKillRow(@"Hide the live event venue tip", @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_venuename_header_tooltip"),
            SGKillRow(@"Hide the Puffin nudge", @"ios-messaging-reduceinterventions-impl.enable_message_puffin_nudge_end_optimization"),
        ]),
    ] footer:nil];
}

// The switches first and what they have stopped last, so the counters bury no setting.
UIViewController *SGAdsSettingsPage(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGAdBlockLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            NSUInteger checked = SGAdBlockChecked(label);
            return checked == NSNotFound ? @(SGAdBlockCount(label)).stringValue
                : [NSString stringWithFormat:@"%lu of %lu", (unsigned long)SGAdBlockCount(label), (unsigned long)checked];
        })];
    }
    [counts addObject:SGStatRow(@"Total", ^NSString *{
        return @(SGAdBlockCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(@"Reset the counters", nil, ^{ SGResetAdBlock(); })];

    SGModRow *fakePremium = SGOptionRow(@"Spoof Premium", nil, SGKeyFakePremium);
    fakePremium.defaultOn = YES;
    fakePremium.warning = SGFakePremiumWarning;

    // The redesign's Search keeps only its category cards, so the video carousel switch is the native look's.
    NSMutableArray<SGModRow *> *ads = [NSMutableArray arrayWithObjects:
        SGWithSymbol(SGSwitchRow(@"Hide ads", nil, SGKeyHideAds), @"speaker.slash"),
        SGWithSymbol(SGSwitchRow(@"Hide upsells", nil, SGKeyHideUpsells), @"hand.raised"), nil];
    if (!SGRedesignedUIStored()) [ads addObject:SGWithSymbol(SGSwitchRow(@"Hide the video carousel in Search", nil, SGKeyHideSearchVideos), @"play.rectangle.on.rectangle")];
    [ads addObject:SGWithSymbol(SGPageRow(@"Ad and upsell flags", ^UIViewController *{ return adFlagsPage(); }), @"flag")];

    return [[SGModPage alloc] initWithTitle:@"Premium, ads & privacy" intro:SGRestartNote sections:@[
        SGNotedSection(@"Ads", ads, @"Audio ads between songs need Spoof Premium."),
        SGNotedSection(@"Premium", @[
            SGWithSymbol(fakePremium, @"crown"),
        ], @"Enabled by default. For free accounts only; Spoof Premium is unstable and may force a logout."),
        SGPrivacySection(),
        SGNotedSection(@"Ads blocked so far", counts,
                       @"\"3 of 214\" is 3 stopped of 214 checked. 0 of 0 means Spotify never asked, so that part does nothing on this version."),
        SGPrivacyCountersSection(),
    ] footer:nil];
}
