#import <Foundation/Foundation.h>

// Runs the sampler until the matching stop, or for `seconds` when that is above 0 (no stop then).
void SGHangSamplerStart(NSString *reason, NSTimeInterval seconds);
void SGHangSamplerStop(void);
