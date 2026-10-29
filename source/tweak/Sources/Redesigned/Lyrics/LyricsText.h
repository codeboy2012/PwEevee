#import <UIKit/UIKit.h>

// A line's three texts. The order puts them largest first; the lyrics are always among them.
typedef NS_ENUM(NSInteger, SGRLyricsText) {
    SGRLyricsTextLyrics = 0,
    SGRLyricsTextPronunciation,
    SGRLyricsTextTranslation,
};

#define SGRKeyLyricsPronunciation @"spotifyglass.redesign.lyricsPronunciation"   // off until switched on
#define SGRKeyLyricsTranslation @"spotifyglass.redesign.lyricsTranslation"       // off until switched on
// The three as the words "lyrics", "pronunciation" and "translation", largest first.
#define SGRKeyLyricsTextOrder @"spotifyglass.redesign.lyricsTextOrder"

// Posted on the main queue when either switch or the order changes.
extern NSNotificationName const SGRLyricsTextDidChangeNotification;

// The order, SGRLyricsText values largest first; unset is Apple Music's: lyrics, pronunciation, translation.
NSArray<NSNumber *> *SGRLyricsTextOrder(void);
void SGRSetLyricsTextOrder(NSArray<NSNumber *> *order);
NSString *SGRLyricsTextName(SGRLyricsText text);
void SGRSetLyricsTextShown(SGRLyricsText text, BOOL shown);

// LyricsTextSettings.m: the Lyrics page's row for the order, which opens a list of the three to drag.
@class SGModRow;
SGModRow *SGRLyricsTextSizesRow(void);
