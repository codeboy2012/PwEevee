#import <Foundation/Foundation.h>

#define SGKeyLockScreenLyrics @"spotifyglass.lockScreenLyrics"

// The moving clip found for the playing track; LyricsArtwork draws synced lines over it when enabled.
void SGLyricsArtworkSetMotion(NSString *uri, NSURL *file);
