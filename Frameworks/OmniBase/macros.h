// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AvailabilityMacros.h>
#import <Foundation/NSAutoreleasePool.h>

// ARC/MRR support
#if defined(__has_feature) && __has_feature(objc_arc)
    #define OB_ARC 1
    #define OB_STRONG __strong
    #define OB_BRIDGE __bridge
    #define OB_BRIDGE_RETAIN __bridge_retain
    #define OB_BRIDGE_TRANSFER __bridge_transfer
    #define OB_AUTORELEASING __autoreleasing
    #define OB_RETAIN(x) (x) // For assignment to a strong local, not for retain in place
    #define OB_RELEASE(x) (x = nil)
    #define OB_AUTORELEASE(x) (x)
#else
    #define OB_ARC 0
    #define OB_STRONG
    #define OB_BRIDGE
    #define OB_BRIDGE_RETAIN
    #define OB_BRIDGE_TRANSFER
    #define OB_AUTORELEASING
    #define OB_RETAIN(x) [(x) retain] // For assignment to a strong local, not for retain in place
    #define OB_RELEASE(x) [(x) release]
    #define OB_AUTORELEASE(x) [(x) autorelease]
#endif

#if !defined(SWAP)
#define SWAP(A, B) do { __typeof__(A) __temp = (A); (A) = (B); (B) = __temp;} while(0)
#endif

#if OB_ARC
    #define OB_REQUIRE_ARC
#else
    #define OB_REQUIRE_ARC ARC_must_be_enabled_for_this_file
#endif


#define OB_NANP * __nullable OB_AUTORELEASING * __nullable  // Nullable autoreleasing object, nullable pointer
#define OB_NANNP * __nullable OB_AUTORELEASING * __nonnull  // Nullable autoreleasing object, nonnullable pointer

// These macros are expanded out because if you do something like MIN(MIN(A,B),C), you'll get a shadowed local variable warning. It's harmless in that case but the warning does occasionally point out bad code elsewhere, so I want to avoid causing it spuriously.

#define MIN3(A, B, C) ({ __typeof__(A) __temp1 = (A); __typeof__(B) __temp2 = (B); if (__temp2 < __temp1) { __temp1 = __temp2; } __temp2 = (C); (__temp2 < __temp1)? __temp2 : __temp1; }) 
#define MAX3(A, B, C) ({ __typeof__(A) __temp1 = (A); __typeof__(B) __temp2 = (B); if (__temp2 > __temp1) { __temp1 = __temp2; } __temp2 = (C); (__temp2 > __temp1)? __temp2 : __temp1; }) 

#define MIN4(A, B, C, D) ({ __typeof__(A) __temp1 = (A); __typeof__(B) __temp2 = (B); if (__temp2 < __temp1) { __temp1 = __temp2; } __typeof__(C) __temp3 = (C); __typeof__(D) __temp4 = (D);  if (__temp4 < __temp3) { __temp3 = __temp4; } (__temp1 < __temp3)? __temp1 : __temp3; })
#define MAX4(A, B, C, D) ({ __typeof__(A) __temp1 = (A); __typeof__(B) __temp2 = (B); if (__temp2 > __temp1) { __temp1 = __temp2; } __typeof__(C) __temp3 = (C); __typeof__(D) __temp4 = (D);  if (__temp4 > __temp3) { __temp3 = __temp4; } (__temp1 > __temp3)? __temp1 : __temp3; })

/* The CLAMP() macro constrains a value to a range, like MIN(MAX()). Min and max are implicitly coerced to the same type as value. */
#define CLAMP(value, min, max) ({ __typeof__(value) __temp_value = (value); __typeof__(value) __temp_min = (min); ( __temp_value < __temp_min )? __temp_min : ({ __typeof__(value) __temp_max = (max); ( __temp_value > __temp_max )? __temp_max : __temp_value; }); })

// On Solaris, when _TS_ERRNO is defined <errno.h> defines errno as the thread-safe ___errno() function.
// On NT, errno is defined to be '(*_errno())' and presumably this function is also thread safe.
// On MacOS X, errno is defined to be '(*__error())', which is also presumably thread safe. 

#import <errno.h>
#define OMNI_ERRNO() errno

#if OB_ARC
    // These macros are not as useful in ARC since it does not NOT handle exceptions (it will leak references) and the 'just a pool' version is easier written with @autoreleasepool. There still is an issue in ARC where an autoreleasing outError can be zombied if it tries to cross pools. In this case, the code needs to rescue the error in a __strong local, close the pool, and then re-set the outError. BUT, we can only safely look at *outError if there was an error. We may come up with a macro pattern for this later, but for now: punt!
#else
    // MRR version
    #define OMNI_POOL_START				\
    do {						\
        NSAutoreleasePool *__pool;			\
        __pool = [[NSAutoreleasePool alloc] init];	\
        @try {

    #define OMNI_POOL_END \
        } @catch (NSException *__exc) { \
            [__exc retain]; \
            [__pool release]; \
            __pool = nil; \
            [__exc autorelease]; \
            [__exc raise]; \
        } @finally { \
            [__pool release]; \
        } \
    } while(0)

    // For when you have an outError to deal with too
    #define OMNI_POOL_ERROR_END \
        } @catch (NSException *__exc) { \
            if (outError) \
                *outError = nil; \
            [__exc retain]; \
            [__pool release]; \
            __pool = nil; \
            [__exc autorelease]; \
            [__exc raise]; \
        } @finally { \
            if (outError) \
                [*outError retain]; \
            [__pool release]; \
            if (outError) \
                [*outError autorelease]; \
        } \
    } while(0)
#endif

// We don't want to use the main-bundle related macros when building other bundle types.  This is sometimes what you want to do, but you shouldn't use the macros since it'll make genstrings emit those strings into your bundle as well.  We can't do this from the .xcconfig files since NSBundle's #define wins vs. command line flags.
#import <Foundation/NSBundle.h> // Make sure this is imported first so that it doesn't get imported afterwards, clobbering our attempted clobbering.
#if defined(OMNI_BUILDING_FRAMEWORK_OR_BUNDLE) && (!defined(TARGET_OS_WATCH) || !TARGET_OS_WATCH)
    #undef NSLocalizedString
    #define NSLocalizedString Use_NSBundle_methods_if_you_really_want_to_look_up_strings_in_the_main_bundle
    #undef NSLocalizedStringFromTable
    #define NSLocalizedStringFromTable Use_NSBundle_methods_if_you_really_want_to_look_up_strings_in_the_main_bundle
#endif

// A wrapper to avoid unlocalized string warnings (in debugging interfaces or messages).
static inline NSString *OBUnlocalized(NSString *value) __attribute__((annotate("returns_localized_nsstring"))) {
    return value;
}

// Hack to define a protocol for OBPerformRuntimeChecks() to check for deprecated dataSource/delegate methods where _implementing_ a method with a given name is considered wrong (likely the method has been removed from the protocol or renamed). The inline is enough to trick the compiler into emitting the protocol into the .o file, though this seems fragile.  OBRuntimeCheck will use this macro itself once and will assert that at least one such deprecated protocol is found, just to make sure this hack keeps working. This macro is intended to be used in a .m file; otherwise the hack function defined would get multiple definitions.
// Since these protocols are only examied when assertions are enabled, this should be wrapped in a OMNI_ASSERTIONS_ON check.
#import <OmniBase/assertions.h> // Since we want you to use OMNI_ASSERTIONS_ON, make sure it is imported
#ifdef OMNI_ASSERTIONS_ON
    extern void OBRuntimeCheckRegisterDeprecatedMethodWithName(const char *name);

    #define OBDEPRECATED_METHOD__(name, line) \
    static void OBRuntimeCheckRegisterDeprecated_ ## line(void) __attribute__((constructor)); \
    static void OBRuntimeCheckRegisterDeprecated_ ## line(void) { \
        OBRuntimeCheckRegisterDeprecatedMethodWithName(#name); \
    }

    #define OBDEPRECATED_METHOD_(name, line) OBDEPRECATED_METHOD__(name, line)
    #define OBDEPRECATED_METHOD(name) OBDEPRECATED_METHOD_(name, __LINE__)
#else
    #define OBDEPRECATED_METHOD(name)
#endif

/*
 OB_BUILTIN_ATOMICS_AVAILABLE: Some compilers have builtins which compile to efficient atomic memory operations.
 On x86, it knows to use the LOCK prefix; on ARM, we get the ldrex/strex/dmb instructions, etc. The names seem to be derived from an Intel intrinsics library, but GCC picked them up and then Clang did.
 If the builtins are not available, code can fall back to the routines in <libkern/OSAtomic.h>.
*/

/* Newer clangs have the builtin atomics that GCC does, and the handy __has_builtin macro */
#if defined(__has_builtin)
#if __has_builtin(__sync_synchronize) && __has_builtin(__sync_bool_compare_and_swap)
#define OB_BUILTIN_ATOMICS_AVAILABLE
#endif
#endif
/* GCC 4.1.x has some builtins for atomic operations */
#if !defined(OB_BUILTIN_ATOMICS_AVAILABLE) && defined(__GNUC__)
#if ((__GNUC__ * 100 + __GNUC_MINOR__ ) >= 401)  // gcc version >= 4.1.0
#ifndef __clang__ // Radar 6964106: clang doesn't have __sync_synchronize builtin (but it claims to be GCC)
#define OB_BUILTIN_ATOMICS_AVAILABLE
#endif
#endif
#endif

/* The fully decorated type of the conventional NSError * out parameter */
#define OBNSErrorOutType NSError * __nullable OB_AUTORELEASING * __nullable

/* For doing retain-and-assign or copy-and-assign with CF objects */
#define OB_ASSIGN_CFRELEASE(lval, rval) { __typeof__(rval) new_ ## lval = (rval); if (lval != NULL) { CFRelease(lval); } lval = new_ ## lval; }

/* For filling your NSError out-parameter from the CFErrorRef you got from another function */
#define OB_CFERROR_TO_NS(outNSError, cfError) do{ if(outNSError) { *(outNSError) = CFBridgingRelease(cfError); } else { CFRelease(cfError); } }while(0)

/* Replacement for __private_extern__, which is deprecated as of Xcode 4.6 DP2 */
#define OB_HIDDEN __attribute__((visibility("hidden")))

/* The inverse of OB_HIDDEN / __private_extern__, for frameworks which hide symbols by default */
#define OB_VISIBLE __attribute__((visibility("default")))

/* Mark overrides of a method as required a message to super */
#define OB_REQUIRES_SUPER __attribute__((objc_requires_super))

/* Convert class to string, accepting a nil argument */
#define OB_STRING_FROM_CLASS_OR_NIL(CLS_) ({ \
    typeof(CLS_) CLS__ = (CLS_); \
    (CLS__ != nil ? NSStringFromClass(CLS__) : @"(null)"); \
})

/* Assert that the given value is of the given class and return it after casting */
#define OB_CHECKED_CAST(CLS_, VALUE_) ({ \
    CLS_ *tmp__ = (CLS_ *)(VALUE_); \
    OBASSERT([tmp__ isKindOfClass:[CLS_ class]], @"Expression %s resulted in instance of %@; expected %@", #VALUE_, OB_STRING_FROM_CLASS_OR_NIL([tmp__ class]), NSStringFromClass([CLS_ class])); \
    tmp__; \
})

#define OB_CHECKED_CAST_OR_NIL(CLS_, VALUE_) ({ \
    CLS_ *maybeNil__ = (CLS_ *)(VALUE_); \
    (maybeNil__ != nil ? OB_CHECKED_CAST(CLS_, maybeNil__) : nil); \
})

// Assert that the given value conforms to the specified protocol and return it after casting.
#define OB_CHECKED_CONFORM(PROTOCOL_, VALUE_) ({ \
    id <PROTOCOL_> tmp__ = (id <PROTOCOL_>)(VALUE_); \
    OBASSERT([tmp__ conformsToProtocol:@protocol(PROTOCOL_)], @"Expression %s resulted in instance of %@, which doesn't conform to %s", #VALUE_, OB_STRING_FROM_CLASS_OR_NIL([tmp__ class]), protocol_getName(@protocol(PROTOCOL_))); \
    tmp__; \
})
#define OB_CHECKED_CONFORM_OR_NIL(PROTOCOL_, VALUE_) ({ \
    id <PROTOCOL_> maybeNil__ = (id <PROTOCOL_>)(VALUE_); \
    (maybeNil__ != nil ? OB_CHECKED_CONFORM(PROTOCOL_, maybeNil__) : nil); \
})
