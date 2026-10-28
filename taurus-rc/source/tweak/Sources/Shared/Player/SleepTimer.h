// The sleep timer, the mod's own, under either look: it pauses Spotify at a time, at the end of the track
// playing, or at the end of the album or playlist playing, and over the last seconds before that (the Fade
// out choice, 30 s unless picked) it fades the sound out through the mod's own gain (SGPlayerSetGain), not
// the system volume. A second after the pause the gain is back to normal, so the next play is at full
// volume. The Live Activity's Timer tab, the Sleep Timer shortcut and its Control Center control set it
// (Shared/LiveActivity), and the card reads it back.
//
// It lasts until it is up or canceled, or Spotify quits; nothing is stored but the fade's length. While one
// is set a timer checks it four times a second, on the main thread, playing or paused.
//
// Threading: main thread only.
#import <Foundation/Foundation.h>

@class SPTPlayerState;

typedef NS_ENUM(NSInteger, SGSleepTimerMode) {
    SGSleepTimerOff = 0,
    SGSleepTimerAtTime,      // at SGSleepTimerEnd()
    SGSleepTimerEndOfTrack,  // just before the end of the track playing when it was set
    SGSleepTimerEndOfAlbum,  // just before the end of the last track of the album or playlist playing
};

// The fade's length, an index into SGSleepTimerFadeNames() (Live Activity page, Sleep timer section). Read
// on every check, so a change applies to a timer already running. For a time it fades over the last seconds
// before the end; at the end of the track or the album over the last seconds of the (last) track, by the
// player's position and the track's length, and over the whole track when the track is shorter.
#define SGKeySleepTimerFade @"spotifyglass.sleepTimer.fade"
NSArray<NSString *> *SGSleepTimerFadeNames(void);
// The index picked, the default for none or one out of range.
NSInteger SGSleepTimerFadeChoice(void);
// The fade picked, in seconds; 0 for Off, which pauses at full volume.
NSTimeInterval SGSleepTimerFade(void);

SGSleepTimerMode SGSleepTimerCurrentMode(void);
// The end of an SGSleepTimerAtTime timer, nil for the others.
NSDate *SGSleepTimerEnd(void);

// Sets a timer up `seconds` from now (SGSleepTimerAtTime, `seconds` then counting) or at the end of the
// track or the album (`seconds` ignored), in place of any set before. SGSleepTimerOff cancels.
void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds);
// Moves an SGSleepTimerAtTime timer's end `seconds` on; starts one from now when none is set or another kind is.
void SGSleepTimerAdd(NSTimeInterval seconds);

// What the timer goes by, here for harness/sleep-timer to check on the Mac.
//
// The gain `left` seconds before the pause, fading over `fade` seconds: 1 until the fade, then down by the
// same number of decibels each second, 60 dB over the fade, which the ear hears as an even fade. 1 all the
// way when `fade` is 0.
float SGSleepTimerGain(NSTimeInterval left, NSTimeInterval fade);
// Whether the playing track is the last of its album or playlist: no track of the context follows it in
// the state's tracks to come (tracks queued by hand and autoplay's don't count), or the next one already
// played, which is repeat starting the album over.
BOOL SGSleepTimerOnLastOfContext(SPTPlayerState *state);
// Seconds of the playing track left, by the player's position and the track's length; -1 when either is
// not known. Spotify's own timer's End of track fades by it too (SpotifySleepTimer.m).
NSTimeInterval SGSleepTimerTrackLeft(SPTPlayerState *state);
