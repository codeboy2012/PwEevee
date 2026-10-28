#import <Foundation/Foundation.h>

// Spotify's streaming quality settings, cellular (metered) and Wi-Fi (non-metered), as its own levels.
// NO until Spotify has made its preferences object.
BOOL SGStreamQuality(NSInteger *metered, NSInteger *nonMetered);
BOOL SGSetStreamQuality(NSInteger metered, NSInteger nonMetered);
// Main thread. Spotify's lowest quality while `lower` (where low is not offered, Spotify plays its next lowest),
// the user's own otherwise. The user's quality is kept across launches and put back at the next launch, even with
// lossless off. A quality the user picks while it is lowered stands.
void SGLosslessLowerQuality(BOOL lower);
