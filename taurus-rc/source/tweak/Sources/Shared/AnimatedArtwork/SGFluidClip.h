// The lock screen's artwork for a song with no moving artwork of its own (LockScreenMotion.x): its cover,
// sharp, over copies of it blurred and slowly turning, the way the redesign's Fluid field draws the player
// (Redesigned/Kit/SGRFluid.m, which Shared cannot use). A short 3:4 clip that loops without a seam: every
// copy sways and drifts through whole cycles over the loop. Core Graphics, Core Image and AVFoundation on
// the CPU only, since the lock screen asks while Spotify is in the background, so harness/fluid-clip
// renders the same files on the Mac.
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// The clip's first frame, for the lock screen's preview image. `size` is SGLyricsClipSize's.
// `coverScale` is the album cover's side as a share of the clip width.
CGImageRef SGFluidClipFrame(CGImageRef cover, CGSize size, CGFloat coverScale) CF_RETURNS_RETAINED;
// Writes the loop as H.264 to `file`, replacing it, and returns once it is written; NO if it was not.
BOOL SGFluidClipWrite(NSURL *file, CGImageRef cover, CGSize size, CGFloat coverScale);
