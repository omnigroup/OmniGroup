// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBBacktraceBuffer.h>

/*
 This is an internal header for OmniBase and OmniCrashCatcher to communicate information about the backtrace buffer. Other code shouldn't need to see it.
*/

/* These can be adjusted as needed - CrashCatcher reads their values from the crashed process's OBBacktraceBufferInfo */
#define OBBacktraceBufferAddressCount (64)    /* Max depth of stack to record per trace */
#define OBBacktraceBufferTraceCount (16)       /* Number of recent traces to retain */

struct OBBacktraceBuffer {
    volatile OBBacktraceBufferType type;
    const char *message;
    const void *context;
    uintptr_t tv_sec, tv_usec;
    void *frames[OBBacktraceBufferAddressCount];
};

#define OBBacktraceBufferInfoVersionMagic  4
struct OBBacktraceBufferInfo {
    // The first four fields provide info for CrashCatcher
    unsigned char version;
    unsigned char infoSize;
    unsigned char addressesPerTrace;
    unsigned char traceCount;
    
    // A pointer to the array of backtrace buffers
    struct OBBacktraceBuffer *backtraces;
    // A pointer to the integer which holds the index of the next free buffer entry
    volatile int32_t *nextTrace;
};
