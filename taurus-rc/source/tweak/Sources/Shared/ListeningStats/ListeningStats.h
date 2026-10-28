// Listening stats (Mod Settings > Listening stats), under either look: plays counted on the phone as they
// happen, Spotify's own data export merged in, and the top tracks, artists and albums of a week, a month,
// a year and all time.
//
//     SGPlayLog.m            the log, the export's parsers and the adding up; the Mac harness runs it
//     ListeningStats.x       the player watched, a play written down once it counts
//     ListeningStatsPage.m   the page, and the export picked and imported
//
// Nothing leaves the phone: the log is a file in Application Support, out of the settings backup.
// Threading: main thread only.
#import <UIKit/UIKit.h>

@class SGPlayLog;

// Plays are written down unless this is switched off; it applies at once.
#define SGKeyListeningStats @"spotifyglass.stats.record"

SGPlayLog *SGListeningLog(void);
UIViewController *SGListeningStatsPage(void);
