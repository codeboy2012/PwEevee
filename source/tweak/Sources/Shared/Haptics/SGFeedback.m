#import "Core/SGCore.h"
#import "Haptics.h"

typedef struct {
    NSInteger style;      // a UIImpactFeedbackStyle, or kSelection
    CGFloat intensity;
} Tap;

static const NSInteger kSelection = -1;
// A rigid impact at this intensity stands in for a selection tick (a bet: UIKit gives the tick no number).
static const CGFloat kTickIntensity = 0.5;

static Tap tapFor(SGFeedback feedback) {
    switch (feedback) {
        case SGFeedbackPlay: return (Tap){UIImpactFeedbackStyleRigid, 0.8};
        case SGFeedbackPause: return (Tap){UIImpactFeedbackStyleSoft, 1};
        case SGFeedbackSkip: return (Tap){UIImpactFeedbackStyleLight, 1};
        case SGFeedbackToggle: return (Tap){kSelection, 1};
        case SGFeedbackAdd: return (Tap){UIImpactFeedbackStyleMedium, 0.8};
        case SGFeedbackGrab: return (Tap){UIImpactFeedbackStyleLight, 0.7};
        case SGFeedbackDetent: return (Tap){kSelection, 1};
        case SGFeedbackEdge: return (Tap){UIImpactFeedbackStyleRigid, 0.6};
        case SGFeedbackRelease: return (Tap){UIImpactFeedbackStyleSoft, 0.8};
    }
    return (Tap){kSelection, 1};
}

static Tap tapAtStrength(SGFeedback feedback) {
    Tap tap = tapFor(feedback);
    double strength = SGHapticsStrength(SGKeyControlStrength);
    if (strength >= 1) return tap;
    if (tap.style == kSelection) return (Tap){UIImpactFeedbackStyleRigid, kTickIntensity * strength};
    return (Tap){tap.style, tap.intensity * strength};
}

static UIFeedbackGenerator *generatorFor(NSInteger style) {
    static NSMutableDictionary<NSNumber *, UIFeedbackGenerator *> *generators;
    if (!generators) generators = [NSMutableDictionary dictionary];
    UIFeedbackGenerator *generator = generators[@(style)];
    if (!generator) {
        generator = style == kSelection ? [UISelectionFeedbackGenerator new] : [[UIImpactFeedbackGenerator alloc] initWithStyle:(UIImpactFeedbackStyle)style];
        generators[@(style)] = generator;
    }
    return generator;
}

void SGPlayFeedback(SGFeedback feedback) {
    if (!SGEnabled(SGKeyControlHaptics)) return;
    Tap tap = tapAtStrength(feedback);
    UIFeedbackGenerator *generator = generatorFor(tap.style);
    if (tap.style == kSelection) [(UISelectionFeedbackGenerator *)generator selectionChanged];
    else [(UIImpactFeedbackGenerator *)generator impactOccurredWithIntensity:tap.intensity];
}

void SGPrepareFeedback(SGFeedback feedback) {
    if (!SGEnabled(SGKeyControlHaptics)) return;
    [generatorFor(tapAtStrength(feedback).style) prepare];
}
