// The parked poster. In normal lifetime -[NSOperation waitUntilFinished]'s only CoreFoundation caller
// is the notification-delivery rendezvous in _CFXNotificationPost: _CFXRegistrationPost enqueued a
// delivery op for a queue-pinned observer (normally to the main queue) and the poster blocks here
// until that queue runs it. Main suspended in any synchronous barrier (our hooks' Spotify chain, a
// dispatch_once, a pure Spotify debounce sync — 17 wedge reports, all shapes) means the op never
// runs and the watchdog kills us (0x8BADF00D). So when the immediate caller of this wait is
// CoreFoundation (dli_fbase match: CFX holds the one waitUntilFinished call site in the image,
// verified across the whole __TEXT — no other CF code waits on ops), we waive the wait: the poster
// returns at once, the worker finishes its block, main's barrier resolves, and the enqueued delivery
// still runs when its queue reaches it (an NSOperationQueue retains ops until execution). Inline
// observers on the posting thread are untouched — the waive happens before any inline dispatch.
// Every non-CF caller waits exactly as before. Forensic narration (ring of last posted names) stays,
// capped; silent in normal running.
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <os/log.h>
#import <Foundation/Foundation.h>

static os_log_t wedgeLog;

static os_log_t sgWedgeLog(void) {
  if (wedgeLog == NULL) wedgeLog = os_log_create("spotifyglass", "wedge");
  return wedgeLog;
}

static NSMutableArray *wedgeRing(void) {
  NSMutableDictionary *mine = [NSThread currentThread].threadDictionary;
  NSMutableArray *ring = mine[@"sgWedgeRing"];
  if (!ring) {
    ring = [[NSMutableArray alloc] init];
    mine[@"sgWedgeRing"] = ring;
  }
  return ring;
}

static void wedgeRemember(NSString *name) {
  NSMutableArray *ring = wedgeRing();
  [ring addObject:name ?: @""];
  while (ring.count > 3) [ring removeObjectAtIndex:0];
}

// Exact base of CoreFoundation, so a name-substring match cannot sweep in libswiftCoreFoundation.
static void *sgCoreFoundationBase(void) {
  static dispatch_once_t once;
  static void *base = NULL;
  dispatch_once(&once, ^{
    Dl_info info;
    if (dladdr((void *)CFNotificationCenterGetLocalCenter, &info)) base = info.dli_fbase;
  });
  return base;
}

%hook NSNotificationCenter
- (void)postNotificationName:(NSString *)name object:(id)object userInfo:(NSDictionary *)userInfo {
  wedgeRemember(name);
  %orig;
}
%end

%hook NSOperation
- (void)waitUntilFinished {
  void *caller = __builtin_return_address(0);
  Dl_info info;
  if (dladdr(caller, &info) && info.dli_fbase == sgCoreFoundationBase()) {
    // CFX's rendezvous loop — the park that closes every wedge shape. Do not wait for it.
    static int32_t rescueMeter = 0;
    int32_t old = __sync_fetch_and_add(&rescueMeter, 1);
    if (old < 40) {
      NSMutableArray *ring = wedgeRing();
      os_log(sgWedgeLog(),
             "rescue: not waiting op=%{public}@ thread=%{public}@ lastposts=[%{public}@ | %{public}@ | %{public}@]",
             self.description, [NSThread currentThread].description,
             ring.count > 0 ? ring[0] : @"-", ring.count > 1 ? ring[1] : @"-", ring.count > 2 ? ring[2] : @"-");
    }
    return;
  }
  // Every other waiter: original semantics; narrate only the early ones (rare outside the wedge).
  static int32_t ringMeter = 0;
  int32_t narrated = __sync_fetch_and_add(&ringMeter, 1);
  if (narrated < 40) {
    NSMutableArray *ring = wedgeRing();
    os_log(sgWedgeLog(),
           "wtf thread=%{public}@ lane=%{public}@ lastposts=[%{public}@ | %{public}@ | %{public}@] op=%{public}@",
           [NSThread currentThread].description, [NSOperationQueue currentQueue].description,
           ring.count > 0 ? ring[0] : @"-", ring.count > 1 ? ring[1] : @"-", ring.count > 2 ? ring[2] : @"-",
           self.description);
  }
  %orig;
}
%end
