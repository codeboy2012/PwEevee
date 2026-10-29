// The plays Listening stats counts, kept on the phone: recorded as they happen, merged in from Spotify's own
// data export, and added up into tops for a period. Foundation only, so the Mac harness
// (harness/listening-stats) builds it as the tweak does.
//
// The log is a text file of one play per line, appended to as plays end, so recording costs one write:
//     end <tab> ms <tab> uri <tab> title <tab> artist <tab> album
// `end` is when the play stopped, in Unix seconds, which is what both of Spotify's export shapes record.
//
// Threading: an SGPlayLog is used from one thread (the main one in the tweak). The parsers are pure and
// run on any.
#import <Foundation/Foundation.h>

@interface SGPlay : NSObject
@property (nonatomic) int64_t end;   // Unix seconds, when the play stopped
@property (nonatomic) int64_t ms;    // how long it was listened to
@property (nonatomic, copy) NSString *uri, *title, *artist, *album;   // uri and album may be empty, never nil
@end

// A play counts once it has run 30 s, or half of a track shorter than a minute.
enum { SGPlayMinimumMs = 30000 };
BOOL SGPlayCounts(double listenedSeconds, double durationSeconds);

// The plays in one of the export's JSON files, either shape: StreamingHistory_music_*.json (endTime,
// artistName, trackName, msPlayed) or the extended Streaming_History_Audio_*.json (ts, ms_played,
// master_metadata_*, spotify_track_uri). Podcasts and plays under SGPlayMinimumMs are left out. Nil when
// the data is not one of those files.
NSArray<SGPlay *> *SGPlaysFromExport(NSData *json);
// The .json files inside a zip, such as the export as Spotify mails it. Empty when it is not a zip.
NSArray<NSData *> *SGJSONFilesInZip(NSData *zip);

@interface SGPlayLog : NSObject
- (instancetype)initWithPath:(NSString *)path;
// Every play, read from the file the first time it is asked for.
@property (nonatomic, readonly) NSArray<SGPlay *> *plays;
- (void)record:(SGPlay *)play;
// Adds the plays the log does not have yet, and answers how many that was: a play it has is the same
// track and artist ending within 90 s of it, which covers the basic export's whole minutes and a
// clock's drift, so importing a file twice, or both shapes of one export, adds nothing.
- (NSUInteger)merge:(NSArray<SGPlay *> *)plays;
- (void)erase;
@end

// One line of a top list: a track (detail is its artist), an artist (no detail) or an album (its artist).
@interface SGStatEntry : NSObject
@property (nonatomic, copy) NSString *name, *detail;
@property (nonatomic) NSUInteger plays;
@property (nonatomic) int64_t ms;
@end

@interface SGStats : NSObject
@property (nonatomic) NSUInteger plays;
@property (nonatomic) int64_t ms;
// Most played first, then most listened to; at most `top` of each.
@property (nonatomic, copy) NSArray<SGStatEntry *> *tracks, *artists, *albums;
@end

// The plays that ended at or after `since` (Unix seconds; 0 for all of them), added up.
SGStats *SGStatsSince(NSArray<SGPlay *> *plays, int64_t since, NSUInteger top);
