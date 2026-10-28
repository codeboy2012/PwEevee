// The track the settings pages' previews show (the Player page's card, the Sing page's card): the one Spotify has
// now, playing or paused; with none, the last one played, kept across launches; with none ever, nothing, and the
// preview draws SGPlaceholderArtwork under "Not Playing".
//
// The last track is stored when the player reports a new one (a player state observer of its own, from launch):
// its title, artist, album, the picture its metadata names and its Canvas's address, nothing of the sound.
//
// Threading: main thread only; the artwork is fetched and decoded off it and handed back on it.
#import <UIKit/UIKit.h>

#define SGKeyLastTrack @"spotifyglass.lastTrack"

@interface SGShownTrack : NSObject
@property (nonatomic, copy, readonly) NSString *uri, *title, *artist, *album;
// The cover's address (i.scdn.co, or a local file's cover on the phone) and the Canvas video's; nil for none.
@property (nonatomic, readonly) NSURL *artworkURL, *canvasURL;
// Spotify has it now, playing or paused; NO for the last track played.
@property (nonatomic, readonly) BOOL current;
@end

// nil when Spotify has no track and none was ever played.
SGShownTrack *SGShownTrackNow(void);
// The track's cover, fetched (from the URL cache when it is there) and decoded off the main thread, then `done`
// on it with the image, or nil when there is none or it did not come. The last one is kept for the next ask.
void SGShownTrackArtwork(SGShownTrack *track, void (^done)(UIImage *image));
// The artwork of no track: a calm gradient of `tint`, a faint note in its middle.
UIImage *SGPlaceholderArtwork(UIColor *tint);
