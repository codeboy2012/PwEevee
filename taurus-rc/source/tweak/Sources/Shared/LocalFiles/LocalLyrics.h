// Imported LRC files: the user's own .lrc files, for the local files no source has lyrics for (rare
// or self-made recordings), under either look. Kept in Documents/spoti.pw/Lyrics as UTF-8, each by the
// name it came with. A file is linked to a local file's URI ("Import for current track"), and that file
// is the track's whatever its tags say; any other track is matched against every file by title and
// artist, folded (case, diacritics, width and everything but letters and digits ignored).
//
//     LocalLyrics.m       the files, the links, the LRC read into lines and the match
//     LocalLyricsPage.m   the Imported LRC files page on the Lyrics page
//
// The lyrics engine asks for a local file's imported lines before any source (Shared/Lyrics/KaraokeSource.x).
#import <UIKit/UIKit.h>
#import "Shared/LyricsSources/LyricsSources.h"

// Local file URI -> the name of the file linked to it.
#define SGKeyImportedLRCLinks @"spotifyglass.localFiles.lrcLinks"

// The source's key in the lyrics sources order, and its ask: it needs no name, since a linked file is
// found by the track's URI. The order moves it to the top at the first import and at every link, once
// LyricsSources lists a provider by this key.
extern NSString *const SGImportedLRCKey;
extern SGLyricsAsk SGImportedLRCAsk;

// The imported files' names, sorted. Safe from any thread.
NSArray<NSString *> *SGImportedLRCFiles(void);
// Copies an .lrc file in (empty, over 1 MB, not UTF-8 or UTF-16, or with no "]" is refused, with an
// error to show), linked to `uri` when that is a local file's. The name it is kept under, nil on a refusal.
// Main thread.
NSString *SGImportLRC(NSURL *url, NSString *uri, NSError **error);
// Removes the file and any link to it. Main thread.
BOOL SGDeleteImportedLRC(NSString *name);
// The file linked to a local file, by its URI or its lyrics key; nil for none. Safe from any thread.
NSString *SGImportedLRCLinkedTo(NSString *uri);
// The lines for a track: its linked file, else the first file whose title and artist match the names
// given (for a local file, nil names are read from the file's URI and the player's track). nil when no
// file has it. Safe from any thread.
SGLyricsResult *SGImportedLRCFor(NSString *trackID, NSString *title, NSString *artist);
// Posted on the main thread after an import or a delete.
extern NSNotificationName const SGImportedLRCDidChangeNotification;

// LocalLyricsPage.m
UIViewController *SGImportedLRCPage(void);
