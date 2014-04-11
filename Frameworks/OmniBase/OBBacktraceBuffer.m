// Copyright 2008, 2010-2011, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>
#import "OBBacktraceBuffer.h"
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

void OBRecordBacktrace(const char *ctxt, unsigned int optype)
{
    assert(optype != OBBacktraceBuffer_Unused && optype != OBBacktraceBuffer_Allocated); // 0 and 1 reserved for us
    
    struct OBBacktraceBuffer *buf = OBAcquireBacktraceBuffer();
    
    buf->context = ctxt;
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
