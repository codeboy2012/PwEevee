// Lossless: a local FLAC or ALAC file of the same recording plays in place of Spotify's sound.
//
//     SGLosslessEngine.m   finds where Spotify plays in the file by matching its sound, and swaps the file in
//     SGLosslessStore.m    which file belongs to which Spotify track
//     Lossless.x           anchors again at each track start, seek or resume (the switch below)
//     SGSourceEvents.x     drops the anchor at a seek, skip, pause or route change
#import <Foundation/Foundation.h>
#import "Shared/Player/PlayerSource.h"

#define SGKeyLossless @"spotifyglass.lossless"   // off unless set

NS_ASSUME_NONNULL_BEGIN
// Off the main and render threads; blocks about 4 s while it records Spotify's sound. Decodes `path` once and keeps
// it until another path or SGLosslessStop(YES). The search looks within 8 s of hintSeconds, or the whole file when
// hintSeconds is negative. Nil with *error when Spotify's sound does not match the file or the source changed.
NSDictionary *_Nullable SGLosslessAnchor(NSString *path, double hintSeconds, NSString *_Nullable *_Nonnull error);
// Off the main thread: the offset in frames between Spotify's sound and the file where the anchor puts it.
NSDictionary *_Nullable SGLosslessCheck(NSString *_Nullable *_Nonnull error);
// Spotify's own sound again; `release` also frees the decoded file.
void SGLosslessStop(BOOL release);
// Whether the file plays now: anchored, and nothing has changed the source since.
BOOL SGLosslessPlaying(void);
NS_ASSUME_NONNULL_END
