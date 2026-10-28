// Core Haptics stood in for, since the simulator has no Taptic Engine: the classes MusicHaptics.x uses, which
// record what it schedules instead of playing it. The harness links this rather than CoreHaptics.framework.
#import <CoreHaptics/CoreHaptics.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#import "fakehaptics.h"

// Only what MusicHaptics.x calls is stood in for.
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

CHHapticEventParameterID CHHapticEventParameterIDHapticIntensity = @"HapticIntensity";
CHHapticEventParameterID CHHapticEventParameterIDHapticSharpness = @"HapticSharpness";
CHHapticDynamicParameterID CHHapticDynamicParameterIDHapticIntensityControl = @"HapticIntensityControl";
CHHapticDynamicParameterID CHHapticDynamicParameterIDHapticSharpnessControl = @"HapticSharpnessControl";
CHHapticEventType CHHapticEventTypeHapticTransient = @"HapticTransient";
CHHapticEventType CHHapticEventTypeHapticContinuous = @"HapticContinuous";

static os_unfair_lock sg_lock = OS_UNFAIR_LOCK_INIT;
static FakeHaptics sg_counts;

FakeHaptics FakeHapticsTake(void) {
    os_unfair_lock_lock(&sg_lock);
    FakeHaptics counts = sg_counts;
    sg_counts = (FakeHaptics){0};
    sg_counts.rumbling = counts.rumbling;
    os_unfair_lock_unlock(&sg_lock);
    return counts;
}

static void record(void (^change)(FakeHaptics *counts)) {
    os_unfair_lock_lock(&sg_lock);
    change(&sg_counts);
    os_unfair_lock_unlock(&sg_lock);
}

// An event's parameters or a player's dynamic ones: both classes answer parameterID and value.
static float valueOf(NSArray *parameters, NSString *identifier) {
    for (CHHapticEventParameter *parameter in parameters) {
        if ([parameter.parameterID isEqualToString:identifier]) return parameter.value;
    }
    return -1;
}

@interface FakeCapability : NSObject <CHHapticDeviceCapability> @end
@implementation FakeCapability
- (BOOL)supportsHaptics { return YES; }
- (BOOL)supportsAudio { return NO; }
- (id<CHHapticParameterAttributes>)attributesForEventParameter:(CHHapticEventParameterID)p eventType:(CHHapticEventType)t error:(NSError **)e { return nil; }
- (id<CHHapticParameterAttributes>)attributesForDynamicParameter:(CHHapticDynamicParameterID)p error:(NSError **)e { return nil; }
@end

@implementation CHHapticEventParameter
- (instancetype)initWithParameterID:(CHHapticEventParameterID)parameterID value:(float)value { if ((self = [super init])) { _parameterID = parameterID; _value = value; } return self; }
@end
@implementation CHHapticDynamicParameter
- (instancetype)initWithParameterID:(CHHapticDynamicParameterID)parameterID value:(float)value relativeTime:(NSTimeInterval)time { if ((self = [super init])) { _parameterID = parameterID; _value = value; _relativeTime = time; } return self; }
@end
@implementation CHHapticEvent
- (instancetype)initWithEventType:(CHHapticEventType)type parameters:(NSArray *)parameters relativeTime:(NSTimeInterval)time { if ((self = [super init])) { _type = type; _eventParameters = parameters; _relativeTime = time; } return self; }
- (instancetype)initWithEventType:(CHHapticEventType)type parameters:(NSArray *)parameters relativeTime:(NSTimeInterval)time duration:(NSTimeInterval)duration { if ((self = [self initWithEventType:type parameters:parameters relativeTime:time])) { _duration = duration; } return self; }
@end
@interface CHHapticPattern ()
@property NSArray<CHHapticEvent *> *fakeEvents;
@end
@implementation CHHapticPattern
- (instancetype)initWithEvents:(NSArray<CHHapticEvent *> *)events parameters:(NSArray *)parameters error:(NSError **)error { if ((self = [super init])) { _fakeEvents = events; } return self; }
@end

@interface FakePlayer : NSObject <CHHapticAdvancedPatternPlayer>
@property CHHapticPattern *pattern;
@end

@implementation CHHapticEngine
@synthesize stoppedHandler = _stoppedHandler, resetHandler = _resetHandler, playsHapticsOnly = _playsHapticsOnly, autoShutdownEnabled = _autoShutdownEnabled;
+ (id<CHHapticDeviceCapability>)capabilitiesForHardware { return [FakeCapability new]; }
- (instancetype)initAndReturnError:(NSError **)error { return [super init]; }
- (instancetype)initWithAudioSession:(AVAudioSession *)audioSession error:(NSError **)error { return [super init]; }
- (NSTimeInterval)currentTime { return CACurrentMediaTime(); }
- (BOOL)startAndReturnError:(NSError **)outError { return YES; }
- (void)stopWithCompletionHandler:(CHHapticCompletionHandler)handler {}
- (id<CHHapticPatternPlayer>)createPlayerWithPattern:(CHHapticPattern *)pattern error:(NSError **)outError { FakePlayer *p = [FakePlayer new]; p.pattern = pattern; return p; }
- (id<CHHapticAdvancedPatternPlayer>)createAdvancedPlayerWithPattern:(CHHapticPattern *)pattern error:(NSError **)outError { FakePlayer *p = [FakePlayer new]; p.pattern = pattern; return p; }
@end

@implementation FakePlayer
@synthesize loopEnabled, loopEnd, playbackRate, isMuted, completionHandler;
- (BOOL)startAtTime:(NSTimeInterval)time error:(NSError **)outError {
    CHHapticEvent *event = self.pattern.fakeEvents.firstObject;
    if ([event.type isEqualToString:CHHapticEventTypeHapticTransient]) {
        float intensity = valueOf(event.eventParameters, CHHapticEventParameterIDHapticIntensity);
        float sharpness = valueOf(event.eventParameters, CHHapticEventParameterIDHapticSharpness);
        record(^(FakeHaptics *counts) {
            // The analyzer's kicks are 0.15 to 0.45 sharp, its snares 0.55 to 0.95.
            if (sharpness < 0.5f) counts->kicks++;
            else counts->snares++;
            counts->tapIntensity += intensity;
        });
    } else {
        record(^(FakeHaptics *counts) {
            counts->rumbleStarts++;
            counts->rumbling = YES;
        });
    }
    return YES;
}
- (BOOL)stopAtTime:(NSTimeInterval)time error:(NSError **)outError {
    record(^(FakeHaptics *counts) {
        counts->rumbleStops++;
        counts->rumbling = NO;
    });
    return YES;
}
- (BOOL)sendParameters:(NSArray *)parameters atTime:(NSTimeInterval)time error:(NSError **)outError {
    float level = valueOf(parameters, CHHapticDynamicParameterIDHapticIntensityControl);
    record(^(FakeHaptics *counts) {
        counts->levels++;
        counts->levelSum += level;
        counts->levelMax = MAX(counts->levelMax, level);
    });
    return YES;
}
- (BOOL)scheduleParameterCurve:(CHHapticParameterCurve *)parameterCurve atTime:(NSTimeInterval)time error:(NSError **)outError { return YES; }
- (BOOL)cancelAndReturnError:(NSError **)outError { return YES; }
- (BOOL)pauseAtTime:(NSTimeInterval)time error:(NSError **)outError { return YES; }
- (BOOL)resumeAtTime:(NSTimeInterval)time error:(NSError **)outError { return YES; }
- (BOOL)seekToOffset:(NSTimeInterval)offsetTime error:(NSError **)outError { return YES; }
@end
