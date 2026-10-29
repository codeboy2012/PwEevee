#import <UIKit/UIKit.h>

@interface SGRPlayerMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
// A template drawn in the row's colour: an SF Symbol at its own size, anything else fitted to the glyph box.
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL destructive;
@property (nonatomic) BOOL disabled;
// What a tap does, for a plain row.
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, copy) NSArray<SGRPlayerMenuItem *> *children;
@property (nonatomic, copy) UIView *(^makeExpansion)(void);
@property (nonatomic) CGFloat expansionHeight;
@property (nonatomic, copy) NSString *key;
+ (instancetype)itemWithTitle:(NSString *)title image:(UIImage *)image action:(void (^)(void))action;
@end

@interface SGRPlayerMenuSection : NSObject
@property (nonatomic, copy) NSArray<SGRPlayerMenuItem *> *items;
// Up to three across, each a glyph over its words, as the Music app's Download, Favorite and Share.
@property (nonatomic) BOOL tiles;
+ (instancetype)sectionWithItems:(NSArray<SGRPlayerMenuItem *> *)items tiles:(BOOL)tiles;
@end

// The width the card is laid out at.
extern const CGFloat SGRPlayerMenuWidth;

@interface SGRPlayerMenuCard : UIView
// Content taller than this scrolls. 0 is no limit.
@property (nonatomic) CGFloat maxHeight;
@property (nonatomic, copy) void (^sizeChanged)(SGRPlayerMenuCard *card);
// VoiceOver's escape gesture.
@property (nonatomic, copy) void (^onEscape)(void);

- (void)showSections:(NSArray<SGRPlayerMenuSection *> *)sections;
// A spinner in place of the rows, while the caller waits for them.
- (void)showLoading;
// A row's line under its words, in place; nil takes it away.
- (void)setSubtitle:(NSString *)subtitle forKey:(NSString *)key;
// A row's view grew or shrank: its expansionHeight, in place, the card following when it is open.
- (void)setExpansionHeight:(CGFloat)height forKey:(NSString *)key;
// The content's height at SGRPlayerMenuWidth, uncapped.
- (CGFloat)preferredHeight;

- (void)growFrom:(CGPoint)anchor;
- (void)shrinkAway:(void (^)(void))completion;
@end
