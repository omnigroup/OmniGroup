// Copyright 1997-2005, 2008-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <objc/objc.h>

#if defined(DEBUG) || defined(OMNI_FORCE_ASSERTIONS)
#define OMNI_ASSERTIONS_ON
#endif

// This allows you to turn off assertions when debugging
#if defined(OMNI_FORCE_ASSERTIONS_OFF)
#undef OMNI_ASSERTIONS_ON
#warning Forcing assertions off!
#endif


// Make sure that we don't accidentally use the ASSERT macro instead of OBASSERT
#ifdef ASSERT
#undef ASSERT
#endif

#if defined(__cplusplus)
extern "C" {
#endif    

typedef void (*OBAssertionFailureHandler)(const char *type, const char *expression, const char *file, unsigned int lineNumber);

extern void OBLogAssertionFailure(const char *type, const char *expression, const char *file, unsigned int lineNumber); // in case you want to integrate the normal behavior with your handler

#if defined(OMNI_ASSERTIONS_ON)
    
    extern void OBSetAssertionFailureHandler(OBAssertionFailureHandler handler);

    extern void OBInvokeAssertionFailureHandler(const char *type, const char *expression, const char *file, unsigned int lineNumber);
    extern void OBAssertFailed(void) __attribute__((noinline)); // This is a convenience breakpoint for in the debugger.
    
    extern BOOL OBEnableExpensiveAssertions;

    #define OBPRECONDITION(expression)                                            \
    do {                                                                        \
        if (!(expression))                                                      \
            OBInvokeAssertionFailureHandler("PRECONDITION", #expression, __FILE__, __LINE__); \
    } while (NO)

    #define OBPOSTCONDITION(expression)                                           \
    do {                                                                        \
        if (!(expression))                                                      \
            OBInvokeAssertionFailureHandler("POSTCONDITION", #expression, __FILE__, __LINE__); \
    } while (NO)

    #define OBINVARIANT(expression)                                               \
    do {                                                                        \
        if (!(expression))                                                      \
            OBInvokeAssertionFailureHandler("INVARIANT", #expression, __FILE__, __LINE__); \
    } while (NO)

    #define OBASSERT(expression)                                                  \
    do {                                                                        \
        if (!(expression))                                                      \
            OBInvokeAssertionFailureHandler("ASSERT", #expression, __FILE__, __LINE__); \
    } while (NO)

    #define OBASSERT_NOT_REACHED(reason)                                        \
    do {                                                                        \
        OBInvokeAssertionFailureHandler("NOTREACHED", reason, __FILE__, __LINE__); \
    } while (NO)

    #define OBPRECONDITION_EXPENSIVE(expression) do { \
        if (OBEnableExpensiveAssertions) \
            OBPRECONDITION(expression); \
    } while(NO)

    #define OBPOSTCONDITION_EXPENSIVE(expression) do { \
        if (OBEnableExpensiveAssertions) \
            OBPOSTCONDITION(expression); \
    } while(NO)

    #define OBINVARIANT_EXPENSIVE(expression) do { \
        if (OBEnableExpensiveAssertions) \
            OBINVARIANT(expression); \
    } while(NO)

    #define OBASSERT_EXPENSIVE(expression) do { \
        if (OBEnableExpensiveAssertions) \
            OBASSERT(expression); \
    } while(NO)

    #ifdef __OBJC__
        #import <Foundation/NSObject.h>
        // Useful when you are changing subclass or delegate API and you want to ensure there aren't lingering implementations of API that will no longer get called.
        static inline void _OBAssertNotImplemented(id self, SEL sel)
        {
            if ([self respondsToSelector:sel]) {
                NSLog(@"%@ has implementation of %@", NSStringFromClass([self class]), NSStringFromSelector(sel));
                OBAssertFailed();
            }
        }
        #define OBASSERT_NOT_IMPLEMENTED(obj, sel) _OBAssertNotImplemented(obj, sel)
    #endif
    
#else	// else insert blank lines into the code

    #define OBPRECONDITION(expression)
    #define OBPOSTCONDITION(expression)
    #define OBINVARIANT(expression)
    #define OBASSERT(expression)
    #define OBASSERT_NOT_REACHED(reason)

    #define OBPRECONDITION_EXPENSIVE(expression)
    #define OBPOSTCONDITION_EXPENSIVE(expression)
    #define OBINVARIANT_EXPENSIVE(expression)
    #define OBASSERT_EXPENSIVE(expression)

    #define OBASSERT_NOT_IMPLEMENTED(obj, sel)
#endif
#if defined(__cplusplus)
} // extern "C"
#endif
