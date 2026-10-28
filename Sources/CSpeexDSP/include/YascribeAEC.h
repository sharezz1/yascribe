#ifndef YASCRIBE_AEC_H
#define YASCRIBE_AEC_H
#include <stddef.h>

typedef struct {
    double correlation;
    int lag_frames;
    int matching_windows;
} YascribeEchoEvidence;

int yascribe_align_reference(const float *system, size_t system_count, float *out, size_t count,
                            const double *mic_frames, const double *mic_times, size_t mic_anchors,
                            const double *system_frames, const double *system_times, size_t system_anchors);
YascribeEchoEvidence yascribe_echo_evidence(const float *mic, const float *reference, size_t count);
int yascribe_cancel_echo(const float *mic, const float *reference, float *out, size_t count);
#endif
