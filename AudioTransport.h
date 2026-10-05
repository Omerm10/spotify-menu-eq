#ifndef AUDIO_TRANSPORT_H
#define AUDIO_TRANSPORT_H
#include <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>
#include <stdint.h>
typedef struct EQAudioTransport EQAudioTransport;
typedef struct {
    uint64_t capturedFrames, renderedFrames, overflowFrames, underrunFrames;
    uint64_t invalidBuffers, nonfiniteSamples, queuedFrames, highWaterFrames;
    float inputPeak, outputPeak;
    uint64_t clippedOutputSamples;
} EQAudioMetrics;
EQAudioTransport *EQAudioTransportCreate(uint32_t capacity, uint32_t prefill);
void EQAudioTransportDestroy(EQAudioTransport *transport);
void EQAudioTransportCapture(EQAudioTransport *transport, const AudioBufferList *input, bool interleaved);
void EQAudioTransportRender(EQAudioTransport *transport, AudioBufferList *output, uint32_t frames);
void EQAudioTransportObserveOutput(EQAudioTransport *transport, const AudioBufferList *output);
EQAudioMetrics EQAudioTransportMetrics(const EQAudioTransport *transport);
#endif
