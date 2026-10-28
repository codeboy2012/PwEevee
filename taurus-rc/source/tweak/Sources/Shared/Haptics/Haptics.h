// Vibrations (Mod Settings > Vibrations), under either look: the Taptic Engine answering
// what a finger does to playback (Controls), and playing along with the music (Music Haptics).
//
//     SGFeedback.m         which tap each kind of control gets, played while Controls is on
//     ControlHaptics.x     the player's and the now playing bar's controls, the scrubber, the cover swipes, the gestures
//     MusicHaptics.x       Spotify's audio output listened to, and Core Haptics played along with it
//     SGMusicAnalyzer.m    the listening: taps and a rumble out of the samples
//     SystemMusicHaptics.x iOS's own Music Haptics given the song's Apple Music id or ISRC (In the Background)
//     SGHapticTrack.m      the pure steps behind it: Spotify's extended metadata asked and read, Apple's songs matched
//     HapticsSettings.m    the Vibrations page: its cards, each one's strength, what Music Haptics follows, its two
//                          switches, and the move to them from the one choice of before
//     SGVibrationsPreview.m the rings at the top of the page, which ripple and play the first feature on when tapped
//
// Everything on them applies at once, without a restart. Everything hooked is Spotify's own (its controls
// by accessibility identifier, its scrubber, its cover and title lists, its audio unit), so all of it works
// on Spotify's own screens and on the redesign's alike. The redesigned lyrics page's tap to seek plays its
// feedback from Redesigned/Lyrics/SGRKaraokeView.m.
// Threading: main thread only.
#import <UIKit/UIKit.h>

#define SGKeyControlHaptics @"spotifyglass.haptics.controls"
// Music Haptics, the mod's own, worked out from the sound while Spotify is in front. Off until switched on.
#define SGKeyMusicHaptics @"spotifyglass.haptics.music"
// In the Background: the song named to iOS's own Music Haptics, which plays on the lock screen and in other apps
// too. Off until switched on.
#define SGKeyMusicHapticsBackground @"spotifyglass.haptics.music.background"
// The one choice of before the two switches, None 0, Generated 1 or Native iOS 2; SGMigrateMusicHaptics moves it.
#define SGKeyMusicHapticsMode @"spotifyglass.haptics.music.mode"
// How hard the taps are, a percentage within the range below; 100 is the feel each shipped with.
#define SGKeyControlStrength @"spotifyglass.haptics.controls.strength"
#define SGKeyMusicStrength @"spotifyglass.haptics.music.strength"
// What Music Haptics plays along with, an SGMusicFollows.
#define SGKeyMusicFollows @"spotifyglass.haptics.music.follows"
// What the keys were called while this was the redesign's alone; the %ctors move them over.
#define SGKeyControlHapticsWas @"spotifyglass.redesign.haptics.controls"
#define SGKeyMusicHapticsWas @"spotifyglass.redesign.haptics.music"
#define SGKeyControlStrengthWas @"spotifyglass.redesign.haptics.controls.strength"
#define SGKeyMusicStrengthWas @"spotifyglass.redesign.haptics.music.strength"
#define SGKeyMusicFollowsWas @"spotifyglass.redesign.haptics.music.follows"

// Controls go softer only: most of their taps are UIKit's at full intensity already. Music Haptics goes
// either way: at 200% the rumble reaches 0.7 of the Taptic Engine's most, and most taps their most.
enum {
    SGControlStrengthMin = 10, SGControlStrengthMax = 100,
    SGMusicStrengthMin = 20, SGMusicStrengthMax = 200,
    SGStrengthStep = 10,
};

typedef NS_ENUM(NSInteger, SGMusicFollows) {
    SGMusicFollowsEverything,   // a tap on each kick and snare, and the rumble under the bass
    SGMusicFollowsBeat,         // a tap on each kick and snare, no rumble
    SGMusicFollowsBass,         // a tap on each kick, and the rumble
};

typedef NS_ENUM(NSInteger, SGFeedback) {
    SGFeedbackPlay,      // playback starts
    SGFeedbackPause,     // playback stops
    SGFeedbackSkip,      // previous, next, a jump in the song (a double tap, a lyric line)
    SGFeedbackToggle,    // shuffle, repeat
    SGFeedbackAdd,       // the add button: liked songs, a playlist
    SGFeedbackGrab,      // a finger takes the scrubber
    SGFeedbackDetent,    // the scrubber passing a tenth of the song, a cover swipe passing halfway
    SGFeedbackEdge,      // the scrubber reaching the start or the end
    SGFeedbackRelease,   // the scrubber let go
};

// Plays `feedback` while Controls is on.
void SGPlayFeedback(SGFeedback feedback);
// Wakes the Taptic Engine for feedback about to follow quickly (a finger on the scrubber).
void SGPrepareFeedback(SGFeedback feedback);

// The two Music Haptics switches. Both may be on: while iOS plays its haptic track for the song (In the
// Background), the mod's own stays quiet; while Spotify is in front and iOS has none, the mod's own plays.
// In the Background reads off below iOS 18, which has no Music Haptics. Main thread.
BOOL SGMusicHapticsOn(void);
BOOL SGMusicHapticsInBackground(void);
// Whether iOS lists this install for Music Haptics: MusicHapticsSupported, which the IPA build writes
// into Info.plist. Without it In the Background has nothing to hand the song to.
BOOL SGMusicHapticsListedByInstall(void);
// The choice of before moved to the switches, once: Generated turns Music Haptics on, Native iOS In the
// Background, None neither. Each reader of the switches calls it first, since none can know it runs first.
void SGMigrateMusicHaptics(void);
// Posted on the main thread when either switch flips; both engines take it up at once.
extern NSNotificationName const SGMusicHapticsSwitchesChangedNotification;
// From SystemMusicHaptics.x: YES while iOS reports the named song playing, and for a short while as it asks
// and names one, so the mod's own stays quiet and the two never play at once. Main thread.
void SGMusicHapticsSetSystemCovers(BOOL covers);
// From its strength and its choice of what to follow: reads them again, for the next tap.
void SGMusicHapticsSettingsChanged(void);
// One kick of the mod's own at its strength, with the rumble under it unless it follows the beat alone, played
// at once: the Vibrations preview's tap. Nothing while the mod's own is not listening.
void SGMusicHapticsPreview(void);
// Each tap the mod's own plays from now on is handed to `watcher` on the main thread as it is felt, with its
// intensity before the strength, 0 to 1; nil stops it. Main thread.
void SGMusicHapticsWatchTaps(void (^watcher)(float intensity));
// What iOS's own Music Haptics is doing, for the settings to read out: SystemMusicHaptics.x sets it. Main thread.
NSString *SGMusicHapticsStatus(void);
void SGSetMusicHapticsStatus(NSString *status);
// Whether Music Haptics is on in Settings > Accessibility, as SystemMusicHaptics.x last read it, YES until it has.
// A change posts SGSystemMusicHapticsChangedNotification, for the page to show or hide its note. Main thread.
BOOL SGSystemMusicHapticsOn(void);
void SGSetSystemMusicHapticsOn(BOOL on);
extern NSNotificationName const SGSystemMusicHapticsChangedNotification;

// A Spotify track URI's ISRC from Spotify's own metadata (SystemMusicHaptics.x), nil for none, on the main queue.
// Kept for the last 100 tracks; `tries` asks again 4 s apart when Spotify does not answer.
void SGSpotifyISRC(NSString *uri, NSUInteger tries, void (^done)(NSString *isrc));

// A strength key's percentage as a factor, 1 for 100%, kept within its range.
double SGHapticsStrength(NSString *key);
SGMusicFollows SGMusicHapticsFollows(void);

// The Vibrations page, linked from Mod Settings' main page: the preview, then a card for Controls and one for Music
// Haptics, each opening out into its settings while it is on.
UIViewController *SGVibrationsSettingsPage(void);
