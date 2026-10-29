// A page that orders sources, the lyrics' and the animated artwork's: drag them into the order they are
// asked; the ones below the line are off, and a tap moves one across.
#import <UIKit/UIKit.h>

@interface SGSource : NSObject
@property (nonatomic, copy) NSString *key, *name, *detail;
+ (instancetype)sourceWithKey:(NSString *)key name:(NSString *)name detail:(NSString *)detail;
@end

// `all` is every source in the order the ones that are off are listed in; `order` and `setOrder` read and
// keep the keys that are on, in the order they are asked.
UIViewController *SGSourcesPageMake(NSString *title, NSString *note, NSArray<SGSource *> *all,
                                    NSArray<NSString *> *(^order)(void), void (^setOrder)(NSArray<NSString *> *keys));
// For an ordered choice that must keep at least this many sources enabled.
UIViewController *SGSourcesPageMakeWithMinimumOnCount(NSString *title, NSString *note, NSArray<SGSource *> *all,
                                                      NSArray<NSString *> *(^order)(void),
                                                      void (^setOrder)(NSArray<NSString *> *keys),
                                                      NSUInteger minimumOnCount);
