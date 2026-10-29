// What the stand-in Core Haptics (fakehaptics.m) was asked to play since it was last asked.
#import <Foundation/Foundation.h>

typedef struct {
    unsigned kicks, snares;          // taps, told apart by their sharpness
    double tapIntensity;             // their intensities, summed
    unsigned rumbleStarts, rumbleStops, levels;
    double levelSum, levelMax;       // the rumble's intensities as sent
    BOOL rumbling;                   // carried over
} FakeHaptics;

// The counts since the last call, and a fresh start.
FakeHaptics FakeHapticsTake(void);
