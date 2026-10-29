#import "Core/SGCore.h"
#import "SGRedesign.h"

%hook SPTHubViewController
- (BOOL)prefersLiquidGlassNavigationBar {
    return YES;
}
%end

%ctor {
    SGRedesignForceFlags(@"glass design", @{
        @"ios-reprise-liquid-glass-properties.context_menu_in_navigation_bar_enabled": @YES,
        @"ios-feature-encoreexperiments.new_npv_slider_enabled": @YES,
        @"ios-feature-nowplaying.sheet_style_npv": @YES,
        @"ios-feature-nowplaying.bottom_sheet_queue_enabled": @YES,
        @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled": @YES,
        @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet": @YES,
        @"ios-playbackcontrol-audiovideoswitcher-impl.enable_connect_bottom_sheet": @YES,
        @"ios-feature-sleeptimer.use_options_sheet": @YES,
    });
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTHubViewController"]);
}
