#import <Foundation/Foundation.h>
#import <SafariServices/SafariServices.h>

// All routing stays in the web extension. No native messaging or network access is needed.
@interface PwEeveeSafariWebExtensionHandler : NSObject <NSExtensionRequestHandling>
@end
@implementation PwEeveeSafariWebExtensionHandler
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context {
    [context completeRequestReturningItems:@[] completionHandler:nil];
}
@end
