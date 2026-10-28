#import <Foundation/Foundation.h>

#define SGKeyLiveActivity @"spotifyglass.liveActivity"
// Which view it shows, the index into the page's list.
#define SGKeyLiveActivityView @"spotifyglass.liveActivity.view"
// What the keys were called while this was the redesign's alone; LiveActivity.x's %ctor moves them over.
#define SGKeyLiveActivityWas @"spotifyglass.redesign.liveActivity"
#define SGKeyLiveActivityViewWas @"spotifyglass.redesign.liveActivity.view"

typedef NS_ENUM(NSInteger, SGLiveActivityView) {
    SGLiveActivityLyrics = 0,
    SGLiveActivityQueue,
    SGLiveActivityPanel,   // the control menu
};

// The card's look (the page's Card section). The keys are read through SGPrefs, so the page's rows and the
// preview that draws the mock share them; a view of the real card reads the same keys.
#define SGKeyLiveActivityColors @"spotifyglass.liveActivity.colors"
#define SGKeyLiveActivityTextSize @"spotifyglass.liveActivity.textSize"
#define SGKeyLiveActivityWithoutLyrics @"spotifyglass.liveActivity.withoutLyrics"
#define SGKeyLiveActivityAlignment @"spotifyglass.liveActivity.alignment"
#define SGKeyLiveActivityTranslation @"spotifyglass.liveActivity.translation"
#define SGKeyLiveActivityArtwork @"spotifyglass.liveActivity.artwork"
#define SGKeyLiveActivityProgressBar @"spotifyglass.liveActivity.progressBar"

// What the card is filled with.
typedef NS_ENUM(NSInteger, SGLiveActivityColors) {
    SGLiveActivityColorsSpotify = 0,   // the artwork's color, Spotify's green standing in
    SGLiveActivityColorsArtwork,       // the artwork's lightened accent
    SGLiveActivityColorsPlain,         // the system's material
};

// The lines' size.
typedef NS_ENUM(NSInteger, SGLiveActivityTextSize) {
    SGLiveActivityTextSmall = 0,
    SGLiveActivityTextMedium,
    SGLiveActivityTextLarge,
};

// A track with no synced lyrics: the title over a note saying so, or the title at the lines' size.
typedef NS_ENUM(NSInteger, SGLiveActivityWithoutLyrics) {
    SGLiveActivityWithoutLyricsNote = 0,
    SGLiveActivityWithoutLyricsTrack,
};

// The lines and the queue: centered, or along the leading edge.
typedef NS_ENUM(NSInteger, SGLiveActivityAlign) {
    SGLiveActivityAlignCenter = 0,
    SGLiveActivityAlignLeading,
};

// From the switch: starts following the player (and the activity, the app being in front) or ends both.
void SGSetLiveActivityEnabled(BOOL on);

@class UIViewController;
// The Live Activity page: its switch and which view it shows.
UIViewController *SGLiveActivitySettingsPage(void);
// What the root's row reads out beside its chevron: the view shown, or Off.
NSString *SGLiveActivitySummary(void);
