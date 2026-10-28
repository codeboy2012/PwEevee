#import <UIKit/UIKit.h>

@class SGRArtworkField;
@class SGModSection;

// The field behind the player.
#define SGRKeyPlayerBackground @"spotifyglass.redesign.player.background"
#define SGRKeyPlayerAnimatedFallback @"spotifyglass.redesign.player.animatedFallback"
typedef NS_ENUM(NSInteger, SGRPlayerBackgroundKind) {
    SGRPlayerBackgroundStill,
    SGRPlayerBackgroundColours,
    SGRPlayerBackgroundFluid,
    SGRPlayerBackgroundAnimated,
    SGRPlayerBackgroundVisualiser,
    SGRPlayerBackgroundFill,
};
SGRPlayerBackgroundKind SGRPlayerBackground(void);
SGRPlayerBackgroundKind SGRPlayerAnimatedFallback(void);
NSArray<NSString *> *SGRPlayerBackgroundNames(void);

#define SGRKeyPlayerBackdropOpacity @"spotifyglass.redesign.player.backdropOpacity"
#define SGRKeyPlayerFillOpacity @"spotifyglass.redesign.player.fillOpacity"
#define SGRKeyPlayerFluidOpacity @"spotifyglass.redesign.player.fluidOpacity"
#define SGRKeyPlayerCanvasBlurOpacity @"spotifyglass.redesign.player.canvasBlurOpacity"
#define SGRKeyPlayerLyricsBlurOpacity @"spotifyglass.redesign.player.lyricsBlurOpacity"
#define SGRKeyPlayerVisualiserBlurOpacity @"spotifyglass.redesign.player.visualiserBlurOpacity"
extern NSNotificationName const SGRPlayerBlurOpacityDidChangeNotification;
void SGRPlayerApplyBackgroundToField(SGRArtworkField *field, SGRPlayerBackgroundKind kind);

#define SGRKeyPlayerMotion @"spotifyglass.redesign.player.movingBackground"
#pragma mark - the ⋯ menu (PlayerMenu.x)

void SGRPlayerMenuWatchMoreButton(UIView *button);

// The field behind the player, nil until the player has laid out once (PlayerField.x).
SGRArtworkField *SGRPlayerField(void);
void SGRPlayerHoldField(void);

#pragma mark - the cover (PlayerArtwork.x)

// The sideways list of covers behind the player, nil until one has laid out.
UIView *SGRPlayerCoverList(void);
CGRect SGRPlayerCoverFrameIn(UIView *host);
CGRect SGRPlayerArtworkAreaIn(UIView *host);
void SGRPlayerSetCoverHidden(BOOL hidden);
CGFloat SGRPlayerCoverScale(void);

#pragma mark - the lyrics in the player (PlayerLyrics.x)

// Allow the lyrics screen to rotate into its two-column landscape layout.
#define SGRKeyLandscapeLyrics @"spotifyglass.redesign.landscapeLyrics"
void SGRPlayerLyricsOrientationChanged(void);
void SGRPlayerForceLandscapeLyrics(void);

// Whether the playing track has lyrics the player can show.
BOOL SGRPlayerLyricsAvailable(void);
// Whether the player is showing them.
BOOL SGRPlayerLyricsOpen(void);
// Shows them, or puts the cover back; does nothing when there are none to show.
void SGRPlayerToggleLyrics(void);
void SGRPlayerLyricsChanged(void);
#define SGRKeyLyricsAutoHide @"spotifyglass.redesign.lyrics.autoHide"
#define SGRKeyLyricsLandscapeAutoHide @"spotifyglass.redesign.lyrics.landscapeAutoHide"
#define SGRKeyPlayerAllowAutoLock @"spotifyglass.redesign.player.allowAutoLock"
#define SGRKeyPlayerVolumeMatchSlider @"spotifyglass.redesign.player.volume.matchSlider"
#define SGRKeyPlayerKaraokeButton @"spotifyglass.redesign.player.karaokeButton"
#define SGRKeyPlayerTranslateButton @"spotifyglass.redesign.player.translateButton"

// The system volume slider below the player controls.
#define SGRKeyPlayerVolume @"spotifyglass.redesign.player.volume"
#define SGRKeyHidePlayerVolume @"spotifyglass.redesign.player.hideVolume"
#define SGRKeyHidePlayerVolumeThumb @"spotifyglass.redesign.player.hideVolumeThumb"
BOOL SGRPlayerVolumeOn(void);
BOOL SGRPlayerPlaceVolume(UIView *stack, UIView *controls, UIView *row, CGFloat margin);
// PlayerLyrics.x: whether the lyrics fade holds the given bottom-stack view; while it does,
// the lyrics own that view's alpha and the player's own layout passes leave it be.
BOOL SGRLyricsFadedView(UIView *view);

// The cover's color may tint the player's controls.
#define SGRKeyPlayerFollowsCover @"spotifyglass.redesign.player.followsCover"
BOOL SGRPlayerFollowsCover(void);
void SGRPlayerSetCoverAccent(UIColor *cover);
void SGRPlayerPaintCover(UIView *stack);

// Landscape lyrics take over the player when enabled.
#define SGRKeyLyricsLandscape @"spotifyglass.redesign.lyrics.landscape"
void SGRPlayerShowLandscape(BOOL show);

void SGRPlayerMotionLyricsChanged(void);
BOOL SGRPlayerMotionLyricsBlurEnabled(void);
void SGRPlayerMotionSetLyricsBlurEnabled(BOOL enabled);
void SGRPlayerMotionFieldLaidOut(void);
void SGRPlayerMotionCoverLaidOut(void);
BOOL SGRPlayerMotionShowing(void);
UIView *SGRPlayerMotionPreview(void (^arrived)(void));
CGFloat SGRPlayerClipDim(CGFloat luminance, BOOL contrast, BOOL lyrics);

BOOL SGRPlayerVisualiserShowing(void);
void SGRPlayerVisualiserUpdate(void);
UIView *SGRPlayerVisualiserPreview(void);
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind);

void SGRPlayerVanish(UIView *view);

UIViewController *SGRPlayerSettingsPage(NSArray<SGModSection *> *more);
