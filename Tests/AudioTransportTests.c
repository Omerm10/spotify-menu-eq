#include "../AudioTransport.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { UInt32 count; AudioBuffer buffers[2]; } StereoList;
static AudioBufferList *planar(StereoList *list, float *l, float *r, uint32_t n) {
    *list = (StereoList){2, {{1,n*4,l}, {1,n*4,r}}};
    return (AudioBufferList *)list;
}
static void basics(void) {
    EQAudioTransport *t = EQAudioTransportCreate(8, 2); assert(t);
    float l[12], r[12], outL[12], outR[12];
    for (int i=0;i<12;i++) { l[i]=(float)i/10; r[i]=-(float)i/10; }
    StereoList in, out;
    AudioBufferList *input=planar(&in,l,r,12), *output=planar(&out,outL,outR,4);
    EQAudioTransportCapture(t,input,false);
    EQAudioMetrics m=EQAudioTransportMetrics(t);
    assert(m.capturedFrames==12 && m.overflowFrames==4 && m.highWaterFrames==8);
    assert(fabsf(m.inputPeak-1.1f)<1e-6);
    EQAudioTransportRender(t,output,4);
    for(int i=0;i<4;i++) assert(outL[i]==l[i] && outR[i]==r[i]);
    EQAudioTransportCapture(t,planar(&in,l,r,4),false);
    EQAudioTransportRender(t,planar(&out,outL,outR,10),10);
    for(int i=0;i<4;i++) assert(outL[i]==l[i+4]);
    for(int i=4;i<8;i++) assert(outL[i]==l[i-4]);
    assert(outL[8]==0 && outR[9]==0);
    m=EQAudioTransportMetrics(t); assert(m.renderedFrames==12 && m.underrunFrames==2);
    input=planar(&in,l,r,4); in.buffers[1].mDataByteSize=4;
    EQAudioTransportCapture(t,input,false);
    m=EQAudioTransportMetrics(t); assert(m.invalidBuffers==1 && m.capturedFrames==16);
    float interleaved[4]={NAN,INFINITY,0.2f,-0.3f};
    AudioBufferList inter={1,{{2,16,interleaved}}};
    EQAudioTransportCapture(t,&inter,true);
    EQAudioTransportRender(t,planar(&out,outL,outR,2),2);
    assert(outL[0]==0 && outR[0]==0 && outL[1]==0.2f && outR[1]==-0.3f);
    m=EQAudioTransportMetrics(t); assert(m.nonfiniteSamples==2);
    outL[0]=1.1f;
    EQAudioTransportObserveOutput(t,(AudioBufferList*)&out);
    m=EQAudioTransportMetrics(t); assert(m.clippedOutputSamples==1 && m.outputPeak==1.1f);
    EQAudioTransportDestroy(t);
}
#define TOTAL 1000000
static void *produce(void *context) {
    EQAudioTransport *t=context; float l[61],r[61]; StereoList list;
    uint32_t next=1;
    while(next<=TOTAL) {
        uint32_t count=TOTAL-next+1; if(count>61)count=61;
        if(EQAudioTransportMetrics(t).queuedFrames>1024-count) { sched_yield();continue; }
        for(uint32_t i=0;i<count;i++) {l[i]=(float)(next+i);r[i]=-l[i];}
        EQAudioTransportCapture(t,planar(&list,l,r,count),false);next+=count;
    }
    return NULL;
}
static void concurrency(void) {
    // Prefill one frame so the final short chunk can drain.
    EQAudioTransport *t=EQAudioTransportCreate(1024,1); assert(t);
    pthread_t thread; assert(pthread_create(&thread,NULL,produce,t)==0);
    float l[37],r[37]; StereoList list; uint32_t expected=1;
    while(expected<=TOTAL) {
        EQAudioTransportRender(t,planar(&list,l,r,37),37);
        for(int i=0;i<37;i++) if(l[i]!=0) {assert(l[i]==(float)expected && r[i]==-(float)expected);expected++;}
    }
    pthread_join(thread,NULL);
    EQAudioMetrics m=EQAudioTransportMetrics(t);
    assert(m.capturedFrames==TOTAL && m.renderedFrames==TOTAL && m.overflowFrames==0 && m.highWaterFrames<=1024);
    printf("Transport: %d frames ordered across concurrent callbacks, highWater=%llu overflow=%llu\n",TOTAL,m.highWaterFrames,m.overflowFrames);
    EQAudioTransportDestroy(t);
}
int main(void) { basics(); concurrency(); puts("Audio transport tests passed"); }
