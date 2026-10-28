#import <UIKit/UIKit.h>
#import "Shared/Player/PlayerState.h"

extern const CGFloat SGRHeaderInfoBottom;     // 14, under the content
extern const CGFloat SGRHeaderInfoTitleRise;  // 56, of the content over the picture

@interface SGRHeaderInfo : UIView <SGPlayerStateObserver>
// YES when anything shown changed. nil or empty hides that line.
- (BOOL)showTitle:(NSString *)title creator:(NSString *)creator length:(NSString *)length about:(NSString *)about;
// A title image such as an artist's logo; nil restores the spoken title.
- (void)showTitleImage:(UIImage *)image;
// A card under the row (the artist page's upcoming concerts), or nil to take it away. It sizes itself with
// sizeThatFits:. The page's picture is laid out without it, so it rises over the picture rather than shortening it.
- (void)showCard:(UIView *)card;
- (void)showCreatorLink:(UIView *)control;
@property (nonatomic, copy) BOOL (^trailingState)(BOOL *on);
@property (nonatomic, copy) NSString *trailingOffSymbol;
@property (nonatomic, copy) NSString *trailingOnSymbol;
- (void)trailingStateChanged;
- (void)showShuffle:(UIView *)shuffle play:(UIView *)play trailing:(UIView *)trailing
   trailingFallback:(UIImage *)trailingFallback playColor:(UIColor *)playColor;
// Album and playlist action row: shuffle, download and add share a scrollable group beside Play.
- (void)showAlbumShuffle:(UIView *)shuffle play:(UIView *)play download:(UIView *)download
                    add:(UIView *)add playColor:(UIColor *)playColor;
// The height the content wants at `width`, from the top of the title to the bottom of the description.
- (CGFloat)contentHeightForWidth:(CGFloat)width;
@end
