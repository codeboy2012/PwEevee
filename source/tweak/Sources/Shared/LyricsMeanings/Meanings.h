#import <UIKit/UIKit.h>
#import "Shared/Lyrics/Lyrics.h"

// Whose annotations show, as SGLyricsMeaningsLevel; unset is off.
#define SGKeyLyricsMeanings @"spotifyglass.lyricsMeanings"
#define SGKeyLyricsMeaningMarkers @"spotifyglass.lyricsMeanings.markers"
extern NSNotificationName const SGLyricsMeaningMarkersDidChangeNotification;

typedef NS_ENUM(NSInteger, SGLyricsMeaningsLevel) {
    SGLyricsMeaningsOff = 0,
    SGLyricsMeaningsArtist,    // written or verified by the artist
    SGLyricsMeaningsEditors,   // and the ones Genius's editors accepted
    SGLyricsMeaningsAll,       // and the community's not yet reviewed
};

// Ordered as they are listed, the artist's first.
typedef NS_ENUM(NSUInteger, SGLyricsMeaningAuthor) {
    SGLyricsMeaningByArtist = 0,
    SGLyricsMeaningByEditors,
    SGLyricsMeaningByCommunity,
};

@interface SGLyricsMeaning : NSObject
@property (nonatomic, copy) NSString *fragment;   // the words it explains, as Genius has them
@property (nonatomic, copy) NSString *body;
@property (nonatomic) SGLyricsMeaningAuthor author;
@property (nonatomic, copy) NSString *url;
@end

SGLyricsMeaningsLevel SGLyricsMeaningsShown(void);
@class SGModRow;
SGModRow *SGLyricsMeaningsRow(void);
SGModRow *SGLyricsMeaningMarkersRow(void);
BOOL SGLyricsMeaningMarkersShown(void);

void SGLyricsMeaningsFor(NSString *trackID, NSArray<SGKaraokeLine *> *lines,
                         void (^done)(NSDictionary<NSNumber *, NSArray<SGLyricsMeaning *> *> *byLine));
