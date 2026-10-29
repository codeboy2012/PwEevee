#import <UIKit/UIKit.h>

#define SGKeyPlayer @"spotifyglass.player"
#define SGKeyPlayerBackdrop @"spotifyglass.playerBackdrop"
#define SGKeyLyricsCard @"spotifyglass.lyricsCard"

// Parts of the player to hide, one switch each (PlayerDeclutter.x). An unset switch is off.
#define SGHideShuffle @"spotifyglass.hide.shuffle"
#define SGHideRepeat @"spotifyglass.hide.repeat"
#define SGHideConnect @"spotifyglass.hide.connect"
#define SGHideShare @"spotifyglass.hide.share"
#define SGHideQueue @"spotifyglass.hide.queue"
#define SGHideAddTo @"spotifyglass.hide.addTo"
#define SGHideLyricsInline @"spotifyglass.hide.lyricsInline"
#define SGHideLyricsCard @"spotifyglass.hide.lyricsCard"
#define SGHideAboutArtist @"spotifyglass.hide.aboutArtist"
#define SGHideRelatedVideos @"spotifyglass.hide.relatedVideos"
#define SGHideSongDNA @"spotifyglass.hide.songDNA"
#define SGHideLiveEvents @"spotifyglass.hide.liveEvents"
#define SGHideExploreArtist @"spotifyglass.hide.exploreArtist"
#define SGHideCredits @"spotifyglass.hide.credits"
#define SGHideMerch @"spotifyglass.hide.merch"
#define SGHideRecommendations @"spotifyglass.hide.recommendations"

#define SGKeyPlayerLyricsOnly @"spotifyglass.hide.playerLyricsOnly"
void SGSetPlayerLyricsOnly(BOOL on);

@class SGModRow, SGModSection;
NSArray<SGModSection *> *SGNativePlayerScreenSections(void);
UIViewController *SGQueueSettingsPage(void);
SGModRow *SGGlassLyricsRow(void);
