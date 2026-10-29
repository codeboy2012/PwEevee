#import <UIKit/UIKit.h>

typedef NS_OPTIONS(NSUInteger, SGRRevealPart) {
    SGRRevealPicture = 1 << 0,   // the hero has its picture
    SGRRevealColor   = 1 << 1,   // the field has the page's colour (SGRArtworkField's -whenColored:)
    SGRRevealHeader  = 1 << 2,   // the header has its text and Play
    SGRRevealList    = 1 << 3,   // the list has a row with its text, not a loading row
    SGRRevealPage    = SGRRevealPicture | SGRRevealColor | SGRRevealHeader | SGRRevealList,
};

// How long a page waits for its parts before it is shown as it is.
extern const NSTimeInterval SGRRevealCap;   // 1.2

void SGRRevealHold(UIView *page, SGRRevealPart parts);
void SGRRevealMark(UIView *page, SGRRevealPart part);
BOOL SGRRevealWaitsFor(UIView *page, SGRRevealPart part);
void SGRRevealBringToFront(UIView *page, UIView *view);
// YES when a label under `root` has text in it. A loading row draws grey bars with empty labels in them.
BOOL SGRRevealShowsText(UIView *root);
