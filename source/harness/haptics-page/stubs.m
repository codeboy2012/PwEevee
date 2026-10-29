// Music Haptics' side of Haptics.h (MusicHaptics.x in the tweak), which the page calls as its switch and its
// settings change: each call is logged with what the hook would read at that moment.
#import "Core/SGCore.h"
#import "Shared/Haptics/Haptics.h"

void SGSetMusicHapticsEnabled(BOOL on) {
    NSLog(@"[harness] Music Haptics %@", on ? @"on" : @"off");
}

void SGMusicHapticsSettingsChanged(void) {
    NSLog(@"[harness] Music Haptics reads strength %.0f%%, follows %ld", SGHapticsStrength(SGKeyMusicStrength) * 100, (long)SGMusicHapticsFollows());
}
