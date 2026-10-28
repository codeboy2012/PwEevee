// When a page's scroll minimizes the glass bar and when it brings it back (TabBarMinimize.x), apart from
// UIKit so harness/tabbar/minimize-check.c runs it on the Mac.
//
// A scroll down of kSGRMinimizeTravel from where the page last turned minimizes the bar, and a scroll back up
// of as much expands it again, anywhere in the list: the Music app's bar does the same. Less than that is a
// finger resting on the glass, not a scroll. Reaching the top always expands it. Pulling past either end is
// not counted, so the page springing back from its foot does not read as a scroll up, and a page with less
// than kSGRMinimizeRange to scroll leaves the bar as it is.
#include <CoreGraphics/CGBase.h>
#include <math.h>
#include <stdbool.h>

static const CGFloat kSGRMinimizeTravel = 24;
static const CGFloat kSGRMinimizeRange = 120;

typedef struct {
    CGFloat turn;     // where the scroll last turned: its lowest offset while expanded, its highest while minimized
    bool minimized;
} SGRMinimizeTrack;

// One step of a scroll: `offset` the content offset, `top` and `bottom` the least and most it rests at.
static inline bool SGRMinimizeStep(SGRMinimizeTrack *track, CGFloat offset, CGFloat top, CGFloat bottom) {
    if (bottom - top < kSGRMinimizeRange) return track->minimized;
    offset = fmin(fmax(offset, top), bottom);
    if (offset <= top + 1) {
        track->minimized = false;
        track->turn = offset;
    } else if (track->minimized ? offset > track->turn : offset < track->turn) {
        track->turn = offset;
    } else if (fabs(offset - track->turn) >= kSGRMinimizeTravel) {
        track->minimized = !track->minimized;
        track->turn = offset;
    }
    return track->minimized;
}
