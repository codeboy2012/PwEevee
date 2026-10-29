#import <stdbool.h>
#import <stddef.h>
#import <stdint.h>

enum { kSGDSPConvolverBlock = 1024 };
// The longest response kept, in frames at the output's rate; past it a response is faded out and cut.
enum { kSGDSPConvolverMaxFrames = 1 << 19 };

typedef struct SGDSPConvolver SGDSPConvolver;

SGDSPConvolver *SGDSPConvolverCreate(const float *const *responses, int paths, size_t length);
void SGDSPConvolverFree(SGDSPConvolver *convolver);
// A block of kSGDSPConvolverBlock frames through it, in place.
void SGDSPConvolverProcess(SGDSPConvolver *convolver, float *left, float *right);

typedef struct {
    float *responses[4];
    int paths;
    size_t length;
} SGDSPImpulse;

typedef enum {
    SGDSPImpulseOriginal,
    SGDSPImpulseTrimmed,        // the tail under -80 dB of the peak cut off
    SGDSPImpulseMinimumPhase,   // each path made minimum phase, then trimmed
} SGDSPImpulseMode;

bool SGDSPReadImpulse(const char *path, double rate, SGDSPImpulseMode mode, SGDSPImpulse *impulse, char *error, size_t errorSize);
void SGDSPFreeImpulse(SGDSPImpulse *impulse);
