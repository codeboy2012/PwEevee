#import <UIKit/UIKit.h>

@class SGModRow, SGModSection, SGKaraokeLine;
SGModSection *SGLyricsSourcesSection(BOOL namingSource);
SGModRow *SGLockScreenLyricsRow(void);
SGModRow *SGLyricsTranslationLanguageRow(void);
SGModRow *SGLyricsWordTimingRow(void);
SGModRow *SGLyricsRomanisedRow(void);
SGModRow *SGLyricsDelayRow(void);

#define SGKeyLyricsSimulateWords @"spotifyglass.lyricsSimulateWords"
#define SGKeyLyricsDelay @"spotifyglass.lyricsDelay"
// Shows a line in another alphabet again in Latin letters (Romanise.m), under the lyrics.
#define SGKeyLyricsRomanised @"spotifyglass.lyricsRomanised"
extern NSNotificationName const SGLyricsRomanisedDidChangeNotification;
NSString *SGLyricsRomanised(NSString *text, BOOL japanese);   // nil where there is nothing to read
BOOL SGLyricsLooksJapanese(NSArray<SGKaraokeLine *> *lines);

// The Lyrics page's "Use these sources anyway", for an EeveeSpotify whose settings read wrong.
#define SGKeyLyricsBesideEevee @"spotifyglass.lyrics.besideEevee"
BOOL SGEeveeLyricsOn(void);
BOOL SGLyricsStandAsideForEevee(void);

typedef NS_ENUM(NSUInteger, SGKaraokeTiming) {
    SGKaraokeTimingWords = 0,   // every word or syllable timed by the source
    SGKaraokeTimingLine,        // the line's start (and maybe its end); the words estimated
    SGKaraokeTimingNone,        // plain text, nothing timed
};

typedef NS_ENUM(NSUInteger, SGKaraokeAlign) {
    SGKaraokeAlignLeading = 0,
    SGKaraokeAlignTrailing,
};

// Times in milliseconds from the start of the track.
@interface SGKaraokeWord : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic) NSInteger start, end;
@property (nonatomic) BOOL joined;
@end

@interface SGKaraokeLine : NSObject <NSCopying>
@property (nonatomic, copy) NSArray<SGKaraokeWord *> *words;
@property (nonatomic) NSInteger start, end;
@property (nonatomic, copy) NSString *voice;
@property (nonatomic) SGKaraokeAlign align;
// How finely the source timed it; the words of a line built here from timed words are timed.
@property (nonatomic) SGKaraokeTiming timing;
@property (nonatomic, strong) SGKaraokeLine *backing;
@property (nonatomic, strong) SGKaraokeLine *pronunciation;
// The line in another language, the backing's words with it; nil where the source has none.
@property (nonatomic, copy) NSString *translation;
// The translation came from a translator of the lyrics' menu (LyricsTranslation), not from the source.
@property (nonatomic) BOOL translationMade;
// The line in Latin letters (SGLyricsRomanised), worked out for the view when the Lyrics page asks
// for it; nil otherwise or where there is nothing to read. Not part of the source's own data.
@property (nonatomic, copy) NSString *romanised;
@end

// The line as one string, a space between the words that are not joined.
NSString *SGKaraokeLineText(SGKaraokeLine *line);
// When the singing of a line is over: its own end, or its backing's when that runs on past it.
NSInteger SGKaraokeSungEnd(SGKaraokeLine *line);
NSInteger SGKaraokeLeadLine(NSArray<SGKaraokeLine *> *lines, NSInteger ms);
// The page's own delay in milliseconds, added to Spotify's position before a line is found.
NSInteger SGKaraokeDelayMs(void);
BOOL SGKaraokeUnspacedScript(NSString *text);
void SGKaraokeAlignVoices(NSArray<SGKaraokeLine *> *lines);

NSArray<SGKaraokeLine *> *SGKaraokeLinesFromBody(NSData *body);
// Lines timed only by their starts, the words inside them estimated; a ♪ or empty text is a break.
NSArray<SGKaraokeLine *> *SGKaraokeEstimatedLines(NSArray<NSNumber *> *starts, NSArray<NSString *> *texts);
// Lines with no time at all, for lyrics that come as plain text; a ♪ or empty text is dropped.
NSArray<SGKaraokeLine *> *SGKaraokeStaticLines(NSArray<NSString *> *texts);
// The finest timing any of the lines has; SGKaraokeTimingNone for none at all.
SGKaraokeTiming SGKaraokeLinesTiming(NSArray<SGKaraokeLine *> *lines);
// The lines sorted by their starts, where a source listed one out of its place in time.
NSArray<SGKaraokeLine *> *SGKaraokeInTimeOrder(NSArray<SGKaraokeLine *> *lines);

NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID);   // nil until the lyrics came
void SGKaraokeKeepLines(NSString *trackID, NSArray<SGKaraokeLine *> *lines);
// Posted on the main queue when a track's lines are kept, with the track's id as the object.
extern NSNotificationName const SGKaraokeLinesDidChangeNotification;
void SGKaraokeRequestLyrics(NSString *trackID);
// Replaces this track's source choice and refreshes its lyrics immediately; nil restores Automatic.
void SGKaraokeSetProviderForTrack(NSString *trackID, NSString *providerKey);
// YES while this track's own timed lyrics are still being looked up (KaraokeSource.x).
BOOL SGKaraokeLooking(NSString *trackID);
void SGKaraokeAskSpotifyForTiming(NSString *trackID);
NSString *SGKaraokeSpotifyAuthorization(void);
// The headers Spotify sends its own spclient requests, as the signed-in app (KaraokeSource.x).
void SGSpclientHeaders(void (^use)(NSDictionary<NSString *, NSString *> *headers));
NSString *SGKaraokePlayingTrack(void);   // the base62 id, nil before the player reported
NSInteger SGKaraokePositionMs(void);     // negative when unknown
void SGKaraokeSeek(NSInteger ms);
id SGKaraokePlayer(void);                // SPTEsperantoPlayer, nil before the app asked it for its state
// A track the player has reported, by its base62 id; nil for one it has not played this session.
@class SPTPlayerTrack;
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID);
// Keeps a track seen elsewhere, so a source can name it before the player has reported it.
void SGKaraokeRememberTrack(SPTPlayerTrack *track);
