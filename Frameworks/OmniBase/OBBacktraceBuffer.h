// Copyright 1997-2022 Omni Development, Inc. All rights reserved.
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

static inline void _OBRecordBacktraceU8(const uint8_t *message, OBBacktraceBufferType optype) {
    OBRecordBacktrace((const char *)message, optype);
}
static inline void _OBRecordBacktraceWithContextU8(const uint8_t *message, OBBacktraceBufferType optype, id context) {
    OBRecordBacktraceWithContext((const char *)message, optype, (__bridge const void *)context);
}
static inline void _OBRecordBacktraceWithContextI8(const int8_t *message, OBBacktraceBufferType optype, id context) {
    OBRecordBacktraceWithContext((const char *)message, optype, (__bridge const void *)context);
}
static inline void _OBRecordBacktraceWithIntContextU8(const uint8_t *message, OBBacktraceBufferType optype, uintptr_t context) {
    OBRecordBacktraceWithContext((const char *)message, optype, (const void *)context);
}

static inline void OBRecordBacktraceWithSelector(SEL selector) {
    OBRecordBacktrace(sel_getName(selector), OBBacktraceBuffer_PerformSelector);
}
static inline void  OBRecordBacktraceWithSelectorAndContext(SEL selector, const void *context) {
    OBRecordBacktraceWithContext(sel_getName(selector), OBBacktraceBuffer_PerformSelector, context);
}

// Make a copy of the original non-constant string that will live long enough to be used as the message for a backtrace buffer. Should only be used for non-constant strings.
extern const char *OBAddCopiedTemporaryString(NSString *original);

// Support for copying standalone backtrace buffers, which won't be reported unless later added.
extern struct OBBacktraceBuffer *OBCreateBacktraceBuffer(const char *message, OBBacktraceBufferType optype, const void *context);
extern void OBFreeBacktraceBuffer(struct OBBacktraceBuffer *buffer);
extern void OBAddBacktraceBuffer(struct OBBacktraceBuffer *buffer);

#ifdef DEBUG
extern void OBBacktraceDumpEntries(void);
#endif
