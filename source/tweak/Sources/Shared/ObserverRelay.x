// Posts no longer wait for queued observers. Every playlist-play hang we traced bottoms out the
// same way: a worker queue (the Mobius model store, the Cosmos resolver, CFNetwork protocols,
// Spotify's widget manager) posts a notification, and CFX delivers block observers registered with
// an NSOperationQueue by scheduling an operation on it and blocking the poster with
// -[NSOperation waitUntilFinished] until it ran. When the op lands on a queue that is busy or is
// itself the poster's lane, the two close a cycle and the watchdog kills us (0x8BADF00D). Re-routing
// every queue-registered observer through a queue:nil registration plus one async hop keeps their
// semantics — the block still runs on its queue — while the post never waits for anything.
// Inline (queue:nil) registrations are untouched: they run on the poster and stay unlocked.
// Shared: applies in both looks.
#import <Foundation/Foundation.h>

%hook NSNotificationCenter
- (id)addObserverForName:(NSString *)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block {
  if (!block || !queue) return %orig;
  NSOperationQueue *target = queue;
  return %orig(name, obj, nil, ^(NSNotification *note) {
    if (target.underlyingQueue) dispatch_async(target.underlyingQueue, ^{ block(note); });
    else [target addOperation:[NSBlockOperation blockOperationWithBlock:^{ block(note); }]];
  });
}
%end
