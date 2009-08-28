// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>
#import <OmniBase/OBBacktraceBuffer.h>
#import <OmniBase/rcsid.h>
#include <execinfo.h>  // For backtrace()

RCS_ID("$Id$")

#if defined(__GNUC__) && ((__GNUC__ * 100 + __GNUC_MINOR__ ) >= 401)
#define BUILTIN_ATOMICS  /* GCC 4.1.x has some builtins for atomic operations */ 
#else
#import <libkern/OSAtomic.h>
#endif


static struct OBBacktraceBuffer backtraces[OBBacktraceBufferTraceCount];
static int next_available_backtrace;
static struct OBBacktraceBuffer *OBAcquireBacktraceBuffer();

const struct OBBacktraceBufferInfo OBBacktraceBufferInfo = {
    OBBacktraceBufferInfoVersionMagic, sizeof(struct OBBacktraceBufferInfo),
    OBBacktraceBufferAddressCount, OBBacktraceBufferTraceCount,
    (uintptr_t)backtraces, (uintptr_t)&next_available_backtrace
};

void OBRecordBacktrace(uintptr_t ctxt, int optype)
{
    assert(optype != OBBacktraceBuffer_Unused && optype != OBBacktraceBuffer_Allocated); // 0 and 1 reserved for us
    
    struct OBBacktraceBuffer *buf = OBAcquireBacktraceBuffer();
    
    buf->context = ctxt;
    int got = backtrace(buf->frames, OBBacktraceBufferAddressCount);
    if (got >= 0) {
        while (got < OBBacktraceBufferAddressCount)
            buf->frames[got ++] = 0;
    }
    
    // Memory barrier. We want everything we just did to be committed before we update 'type'.
#ifdef BUILTIN_ATOMICS
    __sync_synchronize();
#else
    OSMemoryBarrier();
#endif
    
    buf->type = optype;
}

static struct OBBacktraceBuffer *OBAcquireBacktraceBuffer()
{
    int slot = next_available_backtrace;
    
    for(;;) {
        int next_slot = ( slot >= ( OBBacktraceBufferTraceCount-1 ) ) ? 0 : slot+1;
        int was_slot;
#ifdef BUILTIN_ATOMICS
        was_slot = __sync_val_compare_and_swap(&next_available_backtrace, slot, next_slot);
#else
        was_slot = OSAtomicCompareAndSwapInt(slot, next_slot, &next_available_backtrace);
#endif
        if (__builtin_expect(was_slot == slot, 1))
            break;
        else
            slot = was_slot;
    }
    
    struct OBBacktraceBuffer *buf = &(backtraces[slot]);
    buf->type = OBBacktraceBuffer_Allocated;
    
#ifdef BUILTIN_ATOMICS
    __sync_synchronize();
#else
    OSMemoryBarrier();
#endif
    
    return buf;
}
