#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "SGSingController.h"
#import "SGSingModel.h"

%hook _TtC24MusicApp_ContainerWiring18SpotifyAppDelegate
%new
- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier
  completionHandler:(void (^)(void))completionHandler {
    SGSingModelHandlesSession(identifier, completionHandler);
}
%end

%ctor {
    if (!SGSingSupported()) return;
    %init;
    SGRequireClasses(@[@"_TtC24MusicApp_ContainerWiring18SpotifyAppDelegate"]);
    dispatch_async(dispatch_get_main_queue(), ^{ SGSingModelReconnect(); });
}
