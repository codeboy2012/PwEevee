// Keys the mod adds to Spotify's now playing info, under one hook of the setter: the lock screen's moving
// artwork, the song's ISRC for iOS's Music Haptics. Each feature sets its own keys for one title, and
// they ride on every dictionary Spotify sends for that title until the feature sets others.
//
// Lock screen lyrics hooks the same setter and keeps Spotify's own dictionary behind the getter, so
// nothing here stores Spotify's: when extras change, or are cleared while the info still carries them,
// the info the getter gives back is sent again without the old ones and with its clock moved on.
#import <Foundation/Foundation.h>

// `extras` nil or empty clears the owner's. Main thread.
void SGNowPlayingSetExtras(NSString *owner, NSDictionary *extras, NSString *title);
BOOL SGNowPlayingTitlesMatch(id left, id right);
