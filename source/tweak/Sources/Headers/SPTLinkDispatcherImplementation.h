#import <Foundation/Foundation.h>

@interface SPTLinkDispatcherImplementation : NSObject
// 9.1.78's navigate entry point, gone from 9.1.90 — it became
// navigateToURI:options:reason:completionHandler:resultHandler:, whose reason argument
// is a Swift enum no ObjC caller can construct, so the mod calls neither and routes
// through the system deep link instead (see Shared/Navigation/Links.x).
- (void)navigateToURI:(NSURL *)uri options:(long long)options interactionID:(id)interactionID;
@end
