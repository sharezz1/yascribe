#include "YascribeAEC.h"
#include <speex/speex_echo.h>
#include <speex/speex_preprocess.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

int yascribe_align_reference(const float *sys, size_t ns, float *out, size_t n,
                            const double *mf, const double *mt, size_t nm,
                            const double *sf, const double *st, size_t nk) {
    if (nm<2 || nk<2 || ns<2) return -1;
    size_t m=0, s=0;
    for (size_t i=0; i<n; i++) {
        while (m+2<nm && mf[m+1]<=(double)i) m++;
        double t=mt[m]+((double)i-mf[m])*(mt[m+1]-mt[m])/(mf[m+1]-mf[m]);
        while (s+2<nk && st[s+1]<=t) s++;
        double pos=sf[s]+(t-st[s])*(sf[s+1]-sf[s])/(st[s+1]-st[s]);
        if (!isfinite(pos)) return -1;
        if (pos<0 || pos>=(double)ns) { out[i]=0; continue; }
        size_t j=(size_t)pos;
        out[i]=j+1<ns ? (float)(sys[j]+(sys[j+1]-sys[j])*(pos-j)) : sys[j];
    }
    return 0;
}

/* Inspect up to eight separated two-second windows with strong reference
   energy. Full-resolution lag search, dot products sampled every eight frames:
   bounded work, no assumption that acoustic delay is a multiple of 1 ms. */
YascribeEchoEvidence yascribe_echo_evidence(const float *mic, const float *ref, size_t n) {
    enum { window=32000, capacity=8, max_lag=4800 };
    double energy[capacity]={0}, correlations[capacity]={0};
    size_t positions[capacity]={0};
    int lags[capacity]={0}, used=0;
    for (size_t start=0; start+window<=n; start+=window) {
        double rr=0, mm=0;
        for (size_t j=start; j<start+window; j+=8) { rr+=(double)ref[j]*ref[j]; mm+=(double)mic[j]*mic[j]; }
        if (rr<0.00004 || mm<0.00004) continue;
        int index=used;
        if (used<capacity) used++;
        else {
            index=0;
            for (int k=1;k<capacity;k++) if (energy[k]<energy[index]) index=k;
            if (rr<=energy[index]) continue;
        }
        positions[index]=start; energy[index]=rr;
    }
    for (int k=0;k<used;k++) {
        const float *x=mic+positions[k], *y=ref+positions[k];
        for (int lag=0;lag<=max_lag;lag++) {
            double sx=0,sy=0,xx=0,yy=0,xy=0; int samples=0;
            for (int j=lag;j<window;j+=8) {
                double a=x[j], b=y[j-lag];
                sx+=a; sy+=b; xx+=a*a; yy+=b*b; xy+=a*b; samples++;
            }
            xx-=sx*sx/samples; yy-=sy*sy/samples; xy-=sx*sy/samples;
            double score=xx>0 && yy>0 ? fabs(xy/sqrt(xx*yy)) : 0;
            if (score>correlations[k]) { correlations[k]=score; lags[k]=lag; }
        }
    }
    YascribeEchoEvidence result={0,0,0};
    for (int a=0;a<used;a++) for (int b=a+1;b<used;b++) {
        int delta=lags[a]-lags[b];
        double confidence=fmin(correlations[a],correlations[b]);
        if (confidence>=0.25 && delta>=-160 && delta<=160 && confidence>result.correlation)
            result=(YascribeEchoEvidence){confidence,(lags[a]+lags[b])/2,2};
    }
    return result;
}

static int16_t pcm(float x) {
    double value=fmax(-32768,fmin(32767,(double)x*32768));
    return (int16_t)lrint(value);
}

/* One uninterrupted span. The caller partitions at gaps/mutes. WOLA is
   drained per span so latency compensation never moves audio across a reset. */
int yascribe_cancel_echo(const float *mic, const float *ref, float *out, size_t n) {
    enum { frame=256, tail=4096 };
    if (!n) return 0;
    int rate=16000, zero=0, one=1, suppress=-40, active=-15, result=0;
    SpeexEchoState *e=speex_echo_state_init(frame,tail);
    if (!e) return -1;
    SpeexPreprocessState *p=speex_preprocess_state_init(frame,rate);
    if (!p) { speex_echo_state_destroy(e); return -1; }
    if (speex_echo_ctl(e,SPEEX_ECHO_SET_SAMPLING_RATE,&rate) ||
        speex_preprocess_ctl(p,SPEEX_PREPROCESS_SET_DENOISE,&one) ||
        speex_preprocess_ctl(p,SPEEX_PREPROCESS_SET_NOISE_SUPPRESS,&zero) ||
        speex_preprocess_ctl(p,SPEEX_PREPROCESS_SET_AGC,&zero) ||
        speex_preprocess_ctl(p,SPEEX_PREPROCESS_SET_ECHO_SUPPRESS,&suppress) ||
        speex_preprocess_ctl(p,SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE,&active) ||
        speex_preprocess_ctl(p,SPEEX_PREPROCESS_SET_ECHO_STATE,e)) { result=-2; goto cleanup; }
    size_t padded=((n+frame-1)/frame)*frame;
    for (size_t i=0;i<padded+frame;i+=frame) {
        int16_t a[frame]={0},b[frame]={0},c[frame]={0};
        size_t count=i<n ? (n-i<frame?n-i:frame) : 0;
        for (size_t j=0;j<count;j++) {
            if (!isfinite(mic[i+j]) || !isfinite(ref[i+j])) { result=-3; goto cleanup; }
            a[j]=pcm(mic[i+j]); b[j]=pcm(ref[i+j]);
        }
        speex_echo_cancellation(e,a,b,c);
        speex_preprocess_run(p,c);
        if (i>=frame && i-frame<n) {
            size_t start=i-frame, count=n-start<frame?n-start:frame;
            for (size_t j=0;j<count;j++) out[start+j]=mic[start+j]==0 ? 0 : (float)c[j]/32768;
        }
    }
cleanup:
    speex_preprocess_state_destroy(p);
    speex_echo_state_destroy(e);
    return result;
}
