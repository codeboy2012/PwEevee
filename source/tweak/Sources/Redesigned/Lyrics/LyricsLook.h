// How the redesign's lyrics are set, from the Lyrics page: the size of the words, the room between two
// lines, how strongly the lines away from the one sung blur, and how strongly a held word glows and its
// letters wave. A preset sets all five, the sheet of sliders each one; they apply at once to every lyrics
// view there is, the Lyrics page's own preview among them (LyricsLookSettings.m).
#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// size and spacing in points; blur, glow and wave as shares of Apple Music's, 1 being theirs and 0 none.
typedef struct {
    CGFloat size, spacing, blur, glow, wave;
} SGRLyricsLook;

// The lyrics' font, by the name the Font row lists: System (unset), Rounded, Serif, Mono, the font imported
// from Files, or a family this iPhone carries. It applies at once, in every lyrics view, whatever the app font is.
#define SGRKeyLyricsFont @"spotifyglass.redesign.lyricsFont"

// The five as one dictionary; unset is the first preset, Apple Music's.
#define SGRKeyLyricsLook @"spotifyglass.redesign.lyricsLook"

// Posted on the main queue when the look changes; the object is whoever changed it, nil for none named.
extern NSNotificationName const SGRLyricsLookDidChangeNotification;

SGRLyricsLook SGRLyricsLookNow(void);
void SGRSetLyricsLook(SGRLyricsLook look, id changer);

// The fonts the Font row lists, the chosen one's name, and the font itself at a size and weight.
NSArray<NSString *> *SGRLyricsFontChoices(void);
NSString *SGRLyricsFontChoice(void);
void SGRSetLyricsFontChoice(NSString *choice, id changer);
UIFont *SGRLyricsFont(CGFloat size, UIFontWeight weight);

// The animation of the lines, from a short catalogue: how far a word floats up as it is sung, how soft the
// edge of the sweep is, how much the lines away from the one sung shrink, and how long a word takes to rise.
#define SGRKeyLyricsAnimation @"spotifyglass.redesign.lyricsAnimation"
// Per-letter styles (`letters`): each letter of a sung word rises by `letterLift` points and glows `glow` points
// wide as the sweep reaches it, over `spread` of the word's time, the next letters a beat behind; `bounce`
// makes the rise overshoot. The others lift the whole word by `wordLift`. `feather` is the sweep's soft edge,
// `dimScale` how far the other lines shrink, `riseMs` how long a word takes, `move` and `damping` how the
// lines slide to a new place, `stagger` the delay each line further down adds, `fade` how long a line lit
// whole takes to come up to white. The Glow and Wave sliders scale `glow` and `letterLift`.
typedef struct {
    BOOL letters;
    CGFloat wordLift, letterLift, glow, spread;
    BOOL bounce;
    CGFloat feather, dimScale, riseMs, move, damping, stagger, fade;
} SGRLyricsAnimation;
NSArray<NSString *> *SGRLyricsAnimationNames(void);   // Wave, Glow, Bounce, Ripple, Float, Apple Music, Snappy
// Back to the defaults: the first preset, the system font and Apple Music's animation.
void SGRResetLyricsLook(id changer);
NSInteger SGRLyricsAnimationIndex(void);
void SGRSetLyricsAnimationIndex(NSInteger index, id changer);
SGRLyricsAnimation SGRLyricsAnimationNow(void);

// The presets, by name, Apple Music's first.
NSArray<NSString *> *SGRLyricsLookPresetNames(void);
SGRLyricsLook SGRLyricsLookPreset(NSUInteger index);
// The preset the look is, or -1 for a look of the sliders' own.
NSInteger SGRLyricsLookPresetIndex(SGRLyricsLook look);

// A few lines of the preview's own, words timed, one held long enough to glow and wave, and how long
// they take to come round again.
NSArray<SGKaraokeLine *> *SGRLyricsSampleLines(void);
NSInteger SGRLyricsSampleLength(void);

// LyricsLookSettings.m: the Lyrics page in the redesign, leading with the preview, the presets under it
// and their sliders in a sheet, then `sections`.
@class SGModSection;
UIViewController *SGRLyricsSettingsPage(NSString *title, NSString *intro, NSArray<SGModSection *> *sections);

// SGRLyricsSongPill.m: the glass player pill above the preview. It searches LRCLIB for a song, and `picked`
// gets that song's lines and how long to loop them; `togglePlay` flips the preview between running and paused.
@interface SGRLyricsSongPill : UIView
@property (nonatomic, copy) void (^picked)(NSArray<SGKaraokeLine *> *lines, NSTimeInterval length, NSString *title, NSString *artist);
@property (nonatomic, copy) void (^togglePlay)(BOOL playing);
// Where the list of results goes: over the preview, which the pill sits above.
@property (nonatomic, weak) UIView *resultsHost;
- (void)showSong:(NSString *)title artist:(NSString *)artist;
@end
