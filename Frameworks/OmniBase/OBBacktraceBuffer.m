// Copyright 2008-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>
#import "OBBacktraceBuffer-Internal.h"
#include <execinfo.h>  // For backtrace()
#include <sys/time.h>
#include <assert.h>

RCS_ID("$Id$")

#if !defined(OB_BUILTIN_ATOMICS_AVAILABLE)
    #import <libkern/OSAtomic.h>
#endif

static struct OBBacktraceBuffer backtraces[OBBacktraceBufferTraceCount];
static volatile int32_t next_available_backtrace;
static struct OBBacktraceBuffer *OBAcquireBacktraceBuffer(void);

/* this is non-static so that CrashCatcher can find it even in a stripped build */
const struct OBBacktraceBufferInfo OBBacktraceBufferInfo = {
    OBBacktraceBufferInfoVersionMagic, sizeof(struct OBBacktraceBufferInfo),
    OBBacktraceBufferAddressCount, OBBacktraceBufferTraceCount,
    backtraces, &next_available_backtrace
};

void OBRecordBacktrace(const char *message, OBBacktraceBufferType optype)
{
    OBRecordBacktraceWithContext(message, optype, NULL);
}

void OBRecordBacktraceWithContext(const char *message, OBBacktraceBufferType optype, const void *context)
{
    assert(optype != OBBacktraceBuffer_Unused && optype != OBBacktraceBuffer_Allocated); // 0 and 1 reserved for us
    
    struct OBBacktraceBuffer *buf = OBAcquireBacktraceBuffer();
    
    buf->message = message;
    buf->context = context;
    int got = backtrace(buf->frames, OBBacktraceBufferAddressCount);
    if (got >= 0) {
        while (got < OBBacktraceBufferAddressCount)
            buf->frames[got ++] = 0;
    }
    
    struct timeval timestamp;
    if (gettimeofday(&timestamp, NULL) == 0) {
        buf->tv_sec = timestamp.tv_sec;
        buf->tv_usec = timestamp.tv_usec;
    } else {
        buf->tv_sec = 0;
        buf->tv_usec = 0;
    }
    
    // Memory barrier. We want everything we just did to be committed before we update 'type'.
#ifdef OB_BUILTIN_ATOMICS_AVAILABLE
    __sync_synchronize();
#else
    OSMemoryBarrier();
#endif
    
    buf->type = optype;
}

static struct OBBacktraceBuffer *OBAcquireBacktraceBuffer(void)
{
    int32_t slot;
    
    for(;;) {
        slot = next_available_backtrace;
        int32_t next_slot = ( slot >= ( OBBacktraceBufferTraceCount-1 ) ) ? 0 : slot+1;
#ifdef OB_BUILTIN_ATOMICS_AVAILABLE
        bool did_swap = __sync_bool_compare_and_swap(&next_available_backtrace, slot, next_slot);
#else
        bool did_swap = OSAtomicCompareAndSwap32(slot, next_slot, &next_available_backtrace);
#endif
        if (__builtin_expect(did_swap, 1))
            break;
    }
    
    struct OBBacktraceBuffer *buf = &(backtraces[slot]);
    buf->type = OBBacktraceBuffer_Allocated;
    
    return buf;
}

#ifdef DEBUG

static const char *OBBacktraceOpTypeName(enum OBBacktraceBufferType op)
{
#define CASE(x) case OBBacktraceBuffer_ ## x: return #x
    switch (op) {
        CASE(Unused);
        CASE(Allocated);
        CASE(OBAssertionFailure);
        CASE(NSAssertionFailure);
        CASE(NSException);
        CASE(Generic);
        CASE(CxxException);
        CASE(PerformSelector);
        default: {
            return "???";
        }
    }
}

void OBBacktraceDumpEntries(void)
{
    for (int32_t slot = 0; slot < OBBacktraceBufferTraceCount; slot++) {
        struct OBBacktraceBuffer *buf = &backtraces[slot];
        const char *opName = OBBacktraceOpTypeName(buf->type);

        fprintf(stderr, "slot:%d %s", slot, opName);
        if (buf->type > OBBacktraceBuffer_Allocated) {
            // Not printing the stack snapshot addresses for the time being, but we could.
            fprintf(stderr, " message:\"%s\", context:%p\n", buf->message, buf->context);

            int32_t frameCount = 0;
            while (buf->frames[frameCount] != NULL) {
                frameCount++;
            }

            backtrace_symbols_fd(buf->frames, frameCount, fileno(stderr));

            fprintf(stderr, "\n\n");
        }
    }
}
#endif
