#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SGRDownloadState) {
    SGRDownloadNone,
    SGRDownloadWaiting,       // queued, or downloading with no progress to show: the ring turns
    SGRDownloadDownloading,
    SGRDownloadDownloaded,
    SGRDownloadError,
};

BOOL SGRReadDownload(UIView *source, SGRDownloadState *state, CGFloat *progress);

BOOL SGRReadAddTo(UIView *source, BOOL *added);

@interface SGRDownloadGlyph : UIView
@property (nonatomic, readonly) SGRDownloadState state;
@property (nonatomic, readonly) BOOL showsState;   // NO until the first -showState:
- (void)showState:(SGRDownloadState)state progress:(CGFloat)progress animated:(BOOL)animated;
@end
