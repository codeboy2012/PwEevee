#import <Foundation/Foundation.h>

@class SGCanvas;

void SGAppleArtworkFind(NSString *artist, NSString *album, BOOL tall, void (^done)(SGCanvas *canvas, NSString *note));

// The steps with no network in them.
NSString *SGAppleTokenIn(NSString *script);
NSDate *SGAppleTokenExpiry(NSString *token);
NSURL *SGAppleCoverPlaylist(NSArray *albums, NSString *artist, NSString *album, BOOL tall);
// The stream at about the lock screen's width, HEVC where there is one, out of the master playlist.
NSURL *SGAppleStream(NSString *master, NSURL *base);
// The one file every segment of the stream is a byte range of; nil when they are separate files.
NSURL *SGAppleStreamFile(NSString *media, NSURL *base);
