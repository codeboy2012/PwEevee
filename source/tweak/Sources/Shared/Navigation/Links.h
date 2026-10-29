#import <Foundation/Foundation.h>

// NO before the dispatcher is set up, or for a nil URI.
BOOL SGOpenSpotifyURI(NSURL *uri);
id SGLinkDispatcher(void);   // SPTLinkDispatcherImplementation, nil until it is set up

typedef NS_ENUM(NSInteger, SGLinkRoute) {
    SGLinkRouteUnknown = -1,   // the dispatcher or its registry is not there to ask
    SGLinkRouteNone = 0,
    SGLinkRouteOpens = 1,
};
SGLinkRoute SGSpotifyURIRoute(NSURL *uri, NSString **via);

NSURL *SGSpotifyURIFromText(NSString *text);
