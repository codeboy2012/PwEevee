// Spotify's image request for a local file's cover: -loadLocalFileImage reads it out of the file at the
// path its spotify:localfileimage: address names, and -dispatchSuccess: hands the bytes to the delegate's
// imageLoaderRequest:didLoadImageData: on the main queue.
#import <Foundation/Foundation.h>

@interface SPTLocalAVAssetImageLoaderRequest : NSObject
@property (nonatomic, readonly) NSURL *URL;
- (void)dispatchSuccess:(NSData *)data;
@end
