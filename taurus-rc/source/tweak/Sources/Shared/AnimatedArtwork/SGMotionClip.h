// Steps of moving artwork with no UIKit in them, so harness/motion runs them on the Mac: a clip cut to the
// shape the lock screen takes, Spotify's Canvas service's request and reply, and when a Canvas that turned
// up late is still wanted.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// The largest size of `ratio` (width over height) inside `shown`, about its middle, in even pixels.
CGSize SGMotionClipCut(CGSize shown, CGFloat ratio);
// Writes `file` cut about its middle to `ratio` to `out` (H.264, the clip's own frame times), replacing it,
// and returns once it is written; NO if it was not. Blocks, so never on the main queue.
BOOL SGMotionClipShape(NSURL *file, CGFloat ratio, NSURL *out);

// The body that asks Spotify's Canvas service (canvaz-cache) for a track's Canvas: field 1, an entity
// whose field 1 is the track's URI.
NSData *SGMotionCanvasAsk(NSString *uri);
// The address of the first video in the service's reply (field 1, a Canvas each: 2 its address, 4 its
// type, of which 1 to 3 are videos), nil when it names none, only a still or a GIF.
NSString *SGMotionCanvasInReply(NSData *reply);

// Whether a Canvas found after a track's walk began is asked for: Canvas is in `order` (source keys, asked
// first to last) and `source`, the source of the clip showing, nil for none, comes after it.
BOOL SGMotionCanvasOutranks(NSArray<NSString *> *order, NSString *source);
