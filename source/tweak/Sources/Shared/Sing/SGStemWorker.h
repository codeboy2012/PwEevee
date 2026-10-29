// Worker callbacks run off the render thread. context remains owned by the caller until Finished.
#pragma once
#include <stdint.h>
enum { SGStemLoading = 1, SGStemReady, SGStemFinished, SGStemFailed };
typedef int32_t (*SGStemRead)(void *context, float *pcm, uint64_t *metadata);
// Write returns 1 when accepted, 0 when the generation has ended, -1 on a transport failure.
typedef int32_t (*SGStemWrite)(void *context, const float *pcm, uint32_t frames,
                              uint64_t generation, uint64_t track, uint64_t sourceFrame, uint32_t format);
typedef void (*SGStemStatus)(void *context, int32_t status);
void *SGStemWorkerStart(void *context, const char *modelPath, uint32_t windowFrames, uint32_t hopFrames,
                       SGStemRead read, SGStemWrite write, SGStemStatus status);
void SGStemWorkerCancel(void *handle, int32_t unload);
// Drops the warm model at once, for memory, heat, or a model about to be removed.
void SGStemWorkerPurge(void);
