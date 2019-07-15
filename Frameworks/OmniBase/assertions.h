// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <objc/objc.h>
#import <Foundation/NSObjCRuntime.h>
#import <OmniBase/OBBacktraceBuffer.h>

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

/*
 When building with clang, we want it to understand that some of our assertions mean certain paths through the code shouldn't be analyzed. A very common case is asserting that some object is non-nil and then sending a non-void * sized returning message to it.  In this case we'd like to do:
 
 OBASSERT(object);
 
 CGFloat thing = [object stuff];
 
 So, we can annotate the body of the assertion failure with a special clang attribute to discontinue the analysis on that path.  Unlike using __attribute__((noreturn)), this doesn't lie to the compiler's data flow and possibly cause problems due to a function returning when it said it wouldn't.
 */

#ifdef __clang__
    #define CLANG_ANALYZER_NORETURN __attribute__((analyzer_noreturn))
#else
    #define CLANG_ANALYZER_NORETURN
#endif

// This is useful for providing hints to the clang static analyzer about paths that cannot be reached.
static inline void OBAnalyzerNotReached(void) CLANG_ANALYZER_NORETURN;
static inline void OBAnalyzerNotReached(void) { }


// Clang extensions -- Compatibility with non-clang compilers.
#ifndef __has_feature
    #define __has_feature(x) 0
#endif
#if __has_feature(attribute_overloadable)
    // Avoid warning about comparison to zero for unsigned arguments
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(double x) { return x < 0.0; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(float x) { return x < 0.0; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(char x) { return x < 0; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(short x) { return x < 0; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(int x) { return x < 0; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(long x) { return x < 0; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(unsigned char x) { return NO; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(unsigned short x) { return NO; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(unsigned int x) { return NO; }
    static inline BOOL __attribute__((overloadable)) _OBIsNegative(unsigned long x) { return NO; }
#else
    #define _OBIsNegative(x) ((x) < 0)
#endif


#if defined(__cplusplus)
extern "C" {
#endif    

typedef void (*OBAssertionFailureHandler)(const char *type, const char *expression, const char *file, unsigned int lineNumber, const char *reason);

extern void OBLogAssertionFailure(const char *type, const char *expression, const char *file, unsigned int lineNumber, const char *reason); // in case you want to integrate the normal behavior with your handler

#if defined(OMNI_ASSERTIONS_ON)
    
    extern void OBInvokeAssertionFailureHandler(const char *type, const char *expression, const char *file, unsigned int lineNumber, NSString *fmt, ...) NS_FORMAT_FUNCTION(5,6) CLANG_ANALYZER_NORETURN;
    extern void OBAssertFailed(const char *message);
    
    extern BOOL OBEnableExpensiveAssertions;
    
    #define _OBASSERT_CORE(type, expression, expr_str, ...) _OBASSERT_CORE0(type, expression, expr_str, __FILE__, __LINE__, __VA_ARGS__)
    #define _OBASSERT_CORE0(type, expression, expr_str, file, line, ...) \
    do { \
        if (!(expression)) \
            OBInvokeAssertionFailureHandler(type, expr_str, file, line, @"" __VA_ARGS__); \
    } while(NO)
    
    #define OBPRECONDITION(expression, ...) _OBASSERT_CORE("PRECONDITION", expression, #expression, __VA_ARGS__)
    #define OBPOSTCONDITION(expression, ...) _OBASSERT_CORE("POSTCONDITION", expression, #expression, __VA_ARGS__)
    #define OBINVARIANT(expression, ...) _OBASSERT_CORE("INVARIANT", expression, #expression, __VA_ARGS__)
    #define OBASSERT(expression, ...) _OBASSERT_CORE("ASSERT", expression, #expression, __VA_ARGS__)
    
    #define OBASSERT_NOT_REACHED(...) \
    do { \
        OBInvokeAssertionFailureHandler("NOTREACHED", NULL, __FILE__, __LINE__, @"" __VA_ARGS__); \
    } while (NO)
    
    #define OBASSERT_IF(condition, implication, ...) _OBASSERT_IF0(condition, implication, #condition " ==> " #implication, __FILE__, __LINE__, __VA_ARGS__)
    #define _OBASSERT_IF0(condition, implication, expr_str, file, line, ...) \
    do { \
        if ((condition) && !(implication)) \
            OBInvokeAssertionFailureHandler("ASSERT_IF", expr_str, file, line, @"" __VA_ARGS__); \
    } while (NO)

    #define OBASSERT_IFF(condition, implication, ...) _OBASSERT_IFF0(condition, implication, #condition " <==> " #implication, __FILE__, __LINE__, __VA_ARGS__)
    #define _OBASSERT_IFF0(condition, implication, expr_str, file, line, ...) \
    do { \
        BOOL OB_condition_value_ = (condition)? YES : NO; \
        BOOL OB_implication_value_ = (implication)? YES : NO; \
        if ((OB_condition_value_ && !OB_implication_value_) || (!OB_condition_value_ && OB_implication_value_)) \
            OBInvokeAssertionFailureHandler("ASSERT_IFF", expr_str, file, line, @"" __VA_ARGS__); \
    } while (NO)

    #define OBPRECONDITION_EXPENSIVE(expression, ...) do { \
        if (OBEnableExpensiveAssertions) \
            _OBASSERT_CORE("PRECONDITION", expression, #expression, __VA_ARGS__); \
    } while(NO)

    #define OBPOSTCONDITION_EXPENSIVE(expression, ...) do { \
        if (OBEnableExpensiveAssertions) \
            _OBASSERT_CORE("POSTCONDITION", expression, #expression, __VA_ARGS__); \
    } while(NO)

    #define OBINVARIANT_EXPENSIVE(expression, ...) do { \
        if (OBEnableExpensiveAssertions) \
            _OBASSERT_CORE("INVARIANT", expression, #expression, __VA_ARGS__); \
    } while(NO)

    #define OBASSERT_EXPENSIVE(expression, ...) do { \
        if (OBEnableExpensiveAssertions) \
            _OBASSERT_CORE("ASSERT", expression, #expression, __VA_ARGS__); \
    } while(NO)

    // Scalar-taking variants that also do the test at compile time to just signal clang attributes.  The input must be a scalar l-value to avoid evaluation of code.  This will mark the value as referenced, though, so we don't get unused variable warnings.
    #define OBASSERT_NULL(pointer, ...) do { \
        if ((pointer) != NULL) { \
            void *valuePtr __attribute__((unused)) = &pointer; /* have compiler check that it is an l-value */ \
            OBInvokeAssertionFailureHandler("OBASSERT_NULL", #pointer, __FILE__, __LINE__, @"" __VA_ARGS__); \
        } \
    } while(NO);
    #define OBASSERT_NOTNULL(pointer, ...) do { \
        if ((pointer) == NULL) { \
            void *valuePtr __attribute__((unused)) = &pointer; /* have compiler check that it is an l-value */ \
            OBInvokeAssertionFailureHandler("OBASSERT_NOTNULL", #pointer, __FILE__, __LINE__, @"" __VA_ARGS__); \
        } \
    } while(NO);

    // Useful for cases where we *currently* have unsigned values that we want to assert are non-negative but that might later become signed. For exmaple, array indexes -- if we switch between NSUInteger and CFIndex.
    #define OBASSERT_NONNEGATIVE(x, ...) do { \
        if (_OBIsNegative(x)) { \
            OBInvokeAssertionFailureHandler("OBASSERT_NONNEGATIVE", #x, __FILE__, __LINE__, @"" __VA_ARGS__); \
        } \
    } while (NO);
    
    #ifdef __OBJC__
        // Useful if you are subclassing a parent class that conforms to a protcocol with @optional methods; can assert that they *still* don't have the superclass method.
        // +instanceMethodForSelector: returns objc_msgForward now.
        #define OBASSERT_NO_SUPER OBASSERT_NO_SUPER_BECAUSE()
        #define OBASSERT_NO_SUPER_BECAUSE(...) do { \
            Class super__ = [[self class] superclass]; \
            Method method__ = class_getInstanceMethod(super__, _cmd); \
            if (method__) \
                OBInvokeAssertionFailureHandler("OBASSERT_NO_SUPER", __PRETTY_FUNCTION__, __FILE__, __LINE__, @"" __VA_ARGS__); \
        } while (NO)
    
        #import <Foundation/NSObject.h>
        // Useful when you are changing subclass or delegate API and you want to ensure there aren't lingering implementations of API that will no longer get called.  Uses 'const char *' to avoid warnings from -Wundeclared-selector.
        extern void _OBAssertNotImplemented(id self, const char *selName);
        #define OBASSERT_NOT_IMPLEMENTED(obj, selName) _OBAssertNotImplemented(obj, #selName)
    #endif
    
    #define OBASSERT_DISPATCH_QUEUE(__queue) do { \
        if (dispatch_assert_queue) { \
            dispatch_assert_queue(__queue); \
        } \
    } while(0)
    #define OBASSERT_DISPATCH_QUEUE_NOT(__queue) do { \
        if (dispatch_assert_queue_not) { \
            dispatch_assert_queue_not(__queue); \
        } \
    } while(0)

#else	// else insert blank lines into the code

    #define OBPRECONDITION(expression, ...) do {} while(0)
    #define OBPOSTCONDITION(expression, ...) do {} while(0)
    #define OBINVARIANT(expression, ...) do {} while(0)
    #define OBASSERT(expression, ...) do {} while(0)
    #define OBASSERT_NOT_REACHED(...) do { OBRecordBacktrace("NOTREACHED", OBBacktraceBuffer_OBAssertionFailure); OBAnalyzerNotReached(); } while(0)
    #define OBASSERT_IF(condition, implication, ...) do {} while(0)
    #define OBASSERT_IFF(condition, implication, ...) do {} while(0)

    #define OBPRECONDITION_EXPENSIVE(expression, ...) do {} while(0)
    #define OBPOSTCONDITION_EXPENSIVE(expression, ...) do {} while(0)
    #define OBINVARIANT_EXPENSIVE(expression, ...) do {} while(0)
    #define OBASSERT_EXPENSIVE(expression, ...) do {} while(0)

    // Pointer checks to satisfy clang scan-build in non-assertion builds too.
    #define OBASSERT_NULL(pointer, ...) do { \
        if ((pointer) != NULL) { \
            void *valuePtr __attribute__((unused)) = &pointer; /* have compiler check that it is an l-value */ \
            OBAnalyzerNotReached(); \
        } \
    } while(NO);
    #define OBASSERT_NOTNULL(pointer, ...) do { \
        if ((pointer) == NULL) { \
            void *valuePtr __attribute__((unused)) = &pointer; /* have compiler check that it is an l-value */ \
            OBAnalyzerNotReached(); \
        } \
    } while(NO);

    #define OBASSERT_NONNEGATIVE(x, ...) do {} while (0)

    #ifdef __OBJC__
        #define OBASSERT_NO_SUPER
        #define OBASSERT_NO_SUPER_BECAUSE(...)
        #define OBASSERT_NOT_IMPLEMENTED(obj, sel, ...)
    #endif
    
    #define OBASSERT_DISPATCH_QUEUE(__queue) do {} while(0)
    #define OBASSERT_DISPATCH_QUEUE_NOT(__queue) do {} while(0)
#endif
#if defined(__cplusplus)
} // extern "C"
#endif
