// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

typedef CF_ENUM(uintptr_t, OBBacktraceBufferType) {
    OBBacktraceBuffer_Unused = 0,      /* Indicates an unused slot */
    OBBacktraceBuffer_Allocated = 1,   /* Allocated but not filled slot */
    
    /* Remaining integers represent different reasons for recording a backtrace */
    OBBacktraceBuffer_OBAssertionFailure = 2,
    OBBacktraceBuffer_NSAssertionFailure = 3,
    OBBacktraceBuffer_NSException = 4,
    OBBacktraceBuffer_Generic = 5,
    OBBacktraceBuffer_CxxException = 6,
    OBBacktraceBuffer_PerformSelector = 7,
};

extern void OBRecordBacktrace(const char *message, OBBacktraceBufferType optype);
extern void OBRecordBacktraceWithContext(const char *message, OBBacktraceBufferType optype, const void *context);
/*.doc.
 Records a backtrace for possible debugging use in the future. The input message must be a constant string. The optype must be greater than one. The context pointer is not examined at all, but just stored. This allows matching up call sites where delayed operations are enqueued with where they are performed in a crash report.
 */


#ifdef DEBUG
extern void OBBacktraceDumpEntries(void);
#endif
