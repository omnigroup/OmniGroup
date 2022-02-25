// Copyright 2008-2022 Omni Development, Inc. All rights reserved.
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
#include <os/lock.h>

#if !defined(OB_BUILTIN_ATOMICS_AVAILABLE)
    #import <libkern/OSAtomic.h>
#endif

static struct OBBacktraceBuffer backtraces[OBBacktraceBufferTraceCount];
static volatile int32_t next_available_backtrace;
static void OBFillBacktraceBuffer(struct OBBacktraceBuffer *buf, const char *message, OBBacktraceBufferType optype, const void *context);
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
    OBFillBacktraceBuffer(buf, message, optype, context);
}

static void OBFillBacktraceBuffer(struct OBBacktraceBuffer *buf, const char *message, OBBacktraceBufferType optype, const void *context)
{
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
    
    // Memory barrier (for the shared circular buffer). We want everything we just did to be committed before we update 'type'.
#ifdef OB_BUILTIN_ATOMICS_AVAILABLE
    __sync_synchronize();
#else
    OSMemoryBarrier();
#endif
    
    buf->type = optype;
}

static os_unfair_lock StringTableLock = OS_UNFAIR_LOCK_INIT;
static NSMutableArray *OldTemporaryStrings = nil;
static NSMutableArray *CurrentTemporaryStrings = nil;

static struct OBBacktraceBuffer *OBAcquireBacktraceBuffer(void)
{
    // This only works correctly under light contention.

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

    if (slot == 0) {
        // We've wrapped around, so clear the older generation of strings and move the current generation to be the old.
        os_unfair_lock_lock(&StringTableLock);
        OldTemporaryStrings = CurrentTemporaryStrings;
        CurrentTemporaryStrings = nil;
        os_unfair_lock_unlock(&StringTableLock);
    }

    struct OBBacktraceBuffer *buf = &(backtraces[slot]);
    buf->type = OBBacktraceBuffer_Allocated;
    
    return buf;
}

const char *OBAddCopiedTemporaryString(NSString *original)
{
    original = [original copy];

    os_unfair_lock_lock(&StringTableLock);
    if (CurrentTemporaryStrings == nil) {
        CurrentTemporaryStrings = [[NSMutableArray alloc] init];
    }
    [CurrentTemporaryStrings addObject:original];
    os_unfair_lock_unlock(&StringTableLock);

    const char *result = [original UTF8String];
    if (result == NULL) {
        OBASSERT_NOT_REACHED("Unable to generate UTF8String");
        return "???";
    }
    return result;
}

struct OBBacktraceBuffer *OBCreateBacktraceBuffer(const char *message, OBBacktraceBufferType optype, const void *context)
{
    struct OBBacktraceBuffer *buf = calloc(1, sizeof(*buf));
    OBFillBacktraceBuffer(buf, message, optype, context);
    return buf;
}

void OBFreeBacktraceBuffer(struct OBBacktraceBuffer *buffer)
{
    free(buffer);
}

void OBAddBacktraceBuffer(struct OBBacktraceBuffer *buffer)
{
    struct OBBacktraceBuffer *dst = OBAcquireBacktraceBuffer();
    memcpy(dst, buffer, sizeof(*dst));

    // We've already written the type field here, and currently the only callers of this are on crashing paths. It would be better to leave the `type` field as OBBacktraceBuffer_Allocated and write it after the memory barrier though.
#ifdef OB_BUILTIN_ATOMICS_AVAILABLE
    __sync_synchronize();
#else
    OSMemoryBarrier();
#endif
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
    // Print the buffers in order, assuming that we are stopped in the debugger and next_available_backtrace is fixed

    for (int32_t countPrinted = 0; countPrinted < OBBacktraceBufferTraceCount; countPrinted++) {
        int32_t slot = (next_available_backtrace + countPrinted) % OBBacktraceBufferTraceCount;

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
        }

        fprintf(stderr, "\n\n");
    }
}
#endif
