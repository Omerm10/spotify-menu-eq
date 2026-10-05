#include "AudioTransport.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// Exactly one capture producer and one render consumer. Neither callback allocates,
// blocks, invokes Swift, nor changes the other callback's cursor. Release/acquire
// publishes sample writes and prevents overwrite until the consumer has finished.
struct EQAudioTransport {
    float *samples;
    uint32_t capacity, prefill;
    bool primed; // Consumer-owned.
    _Atomic uint64_t writeIndex, readIndex;
    _Atomic uint64_t captured, rendered, overflow, underrun, invalid, nonfinite, highWater;
    _Atomic uint32_t inputPeak, outputPeak;
    _Atomic uint64_t clipped;
};
static void peakStore(_Atomic uint32_t *destination, float peak) {
    uint32_t bits;
    memcpy(&bits, &peak, sizeof(bits));
    // One writer per peak; positive float ordering matches bit ordering.
    if (bits > atomic_load_explicit(destination, memory_order_relaxed))
        atomic_store_explicit(destination, bits, memory_order_relaxed);
}
EQAudioTransport *EQAudioTransportCreate(uint32_t capacity, uint32_t prefill) {
    if (!capacity || !prefill || prefill > capacity) return NULL;
    EQAudioTransport *t = calloc(1, sizeof(*t));
    if (!t) return NULL;
    t->samples = calloc((size_t)capacity * 2, sizeof(float));
    if (!t->samples) { free(t); return NULL; }
    t->capacity = capacity; t->prefill = prefill;
    atomic_init(&t->writeIndex, 0); atomic_init(&t->readIndex, 0);
    atomic_init(&t->captured, 0); atomic_init(&t->rendered, 0);
    atomic_init(&t->overflow, 0); atomic_init(&t->underrun, 0);
    atomic_init(&t->invalid, 0); atomic_init(&t->nonfinite, 0);
    atomic_init(&t->highWater, 0); atomic_init(&t->inputPeak, 0);
    atomic_init(&t->outputPeak, 0); atomic_init(&t->clipped, 0);
    // Fail setup instead of falling back to an implementation with hidden locks.
    if (!atomic_is_lock_free(&t->writeIndex) || !atomic_is_lock_free(&t->inputPeak)) {
        free(t->samples); free(t); return NULL;
    }
    return t;
}
void EQAudioTransportDestroy(EQAudioTransport *t) {
    if (t) { free(t->samples); free(t); }
}
void EQAudioTransportCapture(EQAudioTransport *t, const AudioBufferList *input, bool interleaved) {
    if (!input || input->mNumberBuffers != (interleaved ? 1 : 2)) goto invalid;
    const AudioBuffer *left = &input->mBuffers[0];
    uint32_t stride = interleaved ? 8 : 4;
    if (!left->mData || left->mNumberChannels != (interleaved ? 2 : 1) || left->mDataByteSize % stride) goto invalid;
    uint32_t frames = left->mDataByteSize / stride;
    if (!interleaved && (!input->mBuffers[1].mData || input->mBuffers[1].mNumberChannels != 1 ||
        input->mBuffers[1].mDataByteSize != left->mDataByteSize)) goto invalid;
    uint64_t write = atomic_load_explicit(&t->writeIndex, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&t->readIndex, memory_order_acquire);
    atomic_fetch_add_explicit(&t->captured, frames, memory_order_relaxed);
    uint32_t available = t->capacity - (uint32_t)(write - read);
    uint32_t accepted = frames < available ? frames : available;
    const float *l = left->mData;
    const float *r = interleaved ? l + 1 : input->mBuffers[1].mData;
    float peak = 0; uint64_t nonfinite = 0;
    for (uint32_t i = 0; i < frames; ++i) {
        float a = l[i * (interleaved ? 2 : 1)], b = r[i * (interleaved ? 2 : 1)];
        if (!isfinite(a)) { a = 0; nonfinite++; }
        if (!isfinite(b)) { b = 0; nonfinite++; }
        peak = fmaxf(peak, fmaxf(fabsf(a), fabsf(b)));
        if (i < accepted) {
            size_t offset = ((write + i) % t->capacity) * 2;
            t->samples[offset] = a; t->samples[offset + 1] = b;
        }
    }
    peakStore(&t->inputPeak, peak);
    atomic_fetch_add_explicit(&t->nonfinite, nonfinite, memory_order_relaxed);
    atomic_fetch_add_explicit(&t->overflow, frames - accepted, memory_order_relaxed);
    uint64_t queued = write + accepted - read;
    if (queued > atomic_load_explicit(&t->highWater, memory_order_relaxed))
        atomic_store_explicit(&t->highWater, queued, memory_order_relaxed);
    atomic_store_explicit(&t->writeIndex, write + accepted, memory_order_release);
    return;
invalid:
    atomic_fetch_add_explicit(&t->invalid, 1, memory_order_relaxed);
}
void EQAudioTransportRender(EQAudioTransport *t, AudioBufferList *output, uint32_t frames) {
    // Engine connection is planar stereo; clear all provided memory before validation.
    for (uint32_t c = 0; c < output->mNumberBuffers; ++c)
        if (output->mBuffers[c].mData) memset(output->mBuffers[c].mData, 0, output->mBuffers[c].mDataByteSize);
    if (output->mNumberBuffers != 2 || frames > UINT32_MAX / 4) return;
    for (uint32_t c = 0; c < 2; ++c)
        if (!output->mBuffers[c].mData || output->mBuffers[c].mNumberChannels != 1 || output->mBuffers[c].mDataByteSize < frames * 4) return;
    uint64_t read = atomic_load_explicit(&t->readIndex, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&t->writeIndex, memory_order_acquire);
    uint64_t available = write - read;
    if (!t->primed) {
        if (available < t->prefill) return;
        t->primed = true;
    }
    uint32_t consumed = available < frames ? (uint32_t)available : frames;
    float *l = output->mBuffers[0].mData, *r = output->mBuffers[1].mData;
    for (uint32_t i = 0; i < consumed; ++i) {
        size_t offset = ((read + i) % t->capacity) * 2;
        l[i] = t->samples[offset]; r[i] = t->samples[offset + 1];
    }
    atomic_store_explicit(&t->readIndex, read + consumed, memory_order_release);
    atomic_fetch_add_explicit(&t->rendered, consumed, memory_order_relaxed);
    atomic_fetch_add_explicit(&t->underrun, frames - consumed, memory_order_relaxed);
    if (consumed < frames) t->primed = false;
}
void EQAudioTransportObserveOutput(EQAudioTransport *t, const AudioBufferList *output) {
    float peak = 0; uint64_t clipped = 0;
    for (uint32_t c = 0; c < output->mNumberBuffers; ++c) {
        const float *data = output->mBuffers[c].mData;
        if (!data) continue;
        for (uint32_t i = 0; i < output->mBuffers[c].mDataByteSize / 4; ++i) {
            float value = fabsf(data[i]);
            if (isfinite(value)) peak = fmaxf(peak, value);
            if (!isfinite(value) || value > 1) clipped++;
        }
    }
    peakStore(&t->outputPeak, peak);
    atomic_fetch_add_explicit(&t->clipped, clipped, memory_order_relaxed);
}
EQAudioMetrics EQAudioTransportMetrics(const EQAudioTransport *t) {
    EQAudioMetrics m = {0};
    m.capturedFrames = atomic_load(&t->captured); m.renderedFrames = atomic_load(&t->rendered);
    m.overflowFrames = atomic_load(&t->overflow); m.underrunFrames = atomic_load(&t->underrun);
    m.invalidBuffers = atomic_load(&t->invalid); m.nonfiniteSamples = atomic_load(&t->nonfinite);
    uint64_t read = atomic_load(&t->readIndex), write = atomic_load(&t->writeIndex);
    m.queuedFrames = write >= read ? write - read : 0; // Approximate concurrent snapshot.
    if (m.queuedFrames > t->capacity) m.queuedFrames = t->capacity;
    m.highWaterFrames = atomic_load(&t->highWater);
    uint32_t bits = atomic_load(&t->inputPeak); memcpy(&m.inputPeak, &bits, 4);
    bits = atomic_load(&t->outputPeak); memcpy(&m.outputPeak, &bits, 4);
    m.clippedOutputSamples = atomic_load(&t->clipped);
    return m;
}
