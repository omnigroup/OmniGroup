// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

/*
 This is an internal header for OmniBase and OmniCrashCatcher to communicate information about the backtrace buffer. Other code shouldn't need to see it.
*/

#define OBBacktraceBufferAddressCount 16
#define OBBacktraceBufferTraceCount 8

enum OBBacktraceBufferType {
    OBBacktraceBuffer_Unused = 0,
    OBBacktraceBuffer_Allocated = 1,
    OBBacktraceBuffer_OBAssertionFailure = 2
};

struct OBBacktraceBuffer {
    volatile uintptr_t type;
    uintptr_t context;
    void *frames[OBBacktraceBufferAddressCount];
};

#define OBBacktraceBufferInfoVersionMagic  2
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

