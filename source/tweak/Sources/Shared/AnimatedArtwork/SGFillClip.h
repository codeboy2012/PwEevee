#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// The lock-screen version of Redesigned/Kit's Fill field, rendered at the requested clip size.
CGImageRef SGFillClipFrame(CGImageRef cover, CGSize size) CF_RETURNS_RETAINED;
BOOL SGFillClipWriteFrame(NSURL *file, CGImageRef frame, CGSize size);
