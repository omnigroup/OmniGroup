// Copyright 1997-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSString.h>
#import <Foundation/NSBundle.h>

#import <OmniBase/assertions.h>
#import <OmniBase/objc.h>

#if defined(__cplusplus)
extern "C" {
#endif
    
#if defined(__GNUC__)
#define NORETURN __attribute__ ((noreturn))
#else
#define NORETURN
#endif

/* The LLVM clang scan-build support has some attributes for declaring exceptions to the normal CF/Cocoa rules.  These are only valid for clang, not GCC. */
#if defined(__clang__)
    #define CLANG_RETURNS_NS_RETAINED __attribute__((ns_returns_retained)) 
    #define CLANG_RETURNS_CF_RETAINED __attribute__((cf_returns_retained)) 
#else
    #define CLANG_RETURNS_NS_RETAINED
    #define CLANG_RETURNS_CF_RETAINED
#endif

/*
 * only certain compilers support __attribute__((deprecated))
 * Apple has a similar definition but it's too inclusive
 */
#if defined(MAC_OS_X_VERSION_10_5) && defined(MAC_OS_X_VERSION_MIN_REQUIRED) && defined(__GNUC__) && ((__GNUC__ >= 4) || ((__GNUC__ == 3) && (__GNUC_MINOR__ >= 1))) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_5)
#define OB_DEPRECATED_ATTRIBUTE __attribute__((deprecated))
#else
#define OB_DEPRECATED_ATTRIBUTE
#endif
    
// This uses the OMNI_BUNDLE_IDENTIFIER compiler define set by the OmniGroup/Configurations/*Global*.xcconfig to look up the bundle for the calling code.
#define OMNI_BUNDLE _OBBundleWithIdentifier(OMNI_BUNDLE_IDENTIFIER)
static inline NSBundle *_OBBundleWithIdentifier(NSString *identifier)
{
    OBPRECONDITION([identifier length] > 0); // Did you forget to set OMNI_BUNDLE_IDENTIFIER in your target?
    NSBundle *bundle = [NSBundle bundleWithIdentifier:identifier];
    OBPOSTCONDITION(bundle); // Did you set it to the wrong thing?
    return bundle;
}

extern void _OBRequestConcreteImplementation(id self, SEL _cmd, const char *file, unsigned int line) NORETURN;
extern void _OBRejectUnusedImplementation(id self, SEL _cmd, const char *file, unsigned int line) NORETURN;
extern void _OBRejectInvalidCall(id self, SEL _cmd, const char *file, unsigned int line, NSString *format, ...) NORETURN;

#define OBRequestConcreteImplementation(self, sel) _OBRequestConcreteImplementation((self), (sel), __FILE__, __LINE__)
#define OBRejectUnusedImplementation(self, sel) _OBRejectUnusedImplementation((self), (sel), __FILE__, __LINE__)
#define OBRejectInvalidCall(self, sel, format, ...) _OBRejectInvalidCall((self), (sel), __FILE__, __LINE__, (format), ## __VA_ARGS__)

extern NSString * const OBAbstractImplementation;
extern NSString * const OBUnusedImplementation;

void OBRecordBacktrace(uintptr_t ctxt, int optype);
/*.doc.
  Records a backtrace for possible debugging use in the future. ctxt and optype are free for the caller to use for their own purposes, but optype must be nonzero.
*/
    
#undef NORETURN

extern IMP OBRegisterInstanceMethodWithSelector(Class aClass, SEL oldSelector, SEL newSelector);
/*.doc.
Provides the same functionality as +[NSObject registerInstanceMethod:withMethodTypes:forSelector: but does it without provoking +initialize on the target class.  Returns the original implementation.
*/

extern IMP OBReplaceMethodImplementation(Class aClass, SEL oldSelector, IMP newImp);
/*.doc.
Replaces the given method implementation in place.  Returns the old implementation.
*/

IMP OBReplaceMethodImplementationFromMethod(Class aClass, SEL oldSelector, Method newMethod);
/*.doc.
Replaces the given method implementation in place.  Returns the old implementation.
*/

extern IMP OBReplaceMethodImplementationWithSelector(Class aClass, SEL oldSelector, SEL newSelector);
/*.doc.
Calls the above, but determines newImp by looking up the instance method for newSelector.  Returns the old implementation.
*/

extern IMP OBReplaceMethodImplementationWithSelectorOnClass(Class destClass, SEL oldSelector, Class sourceClass, SEL newSelector);
/*.doc.
Calls OBReplaceMethodImplementation.  Derives newImp from newSelector on sourceClass and changes method implementation for oldSelector on destClass.
*/

extern Class OBClassImplementingMethod(Class cls, SEL sel);

// This returns YES if the given pointer is a class object
static inline BOOL OBPointerIsClass(id object)
{
    if (object) {
        Class cls = object_getClass(object);
        return class_isMetaClass(cls);
    }
    return NO;
}

// This returns the class object for the given pointer.  For an instance, that means getting the class.  But for a class object, that means returning the pointer itself 

static inline Class OBClassForPointer(id object)
{
    if (!object)
	return object;

    if (OBPointerIsClass(object))
	return object;
    else
	return object->isa;
}

static inline BOOL OBClassIsSubclassOfClass(Class subClass, Class superClass)
{
    while (subClass) {
        if (subClass == superClass)
            return YES;
        else
            subClass = class_getSuperclass(subClass);
    }
    return NO;
}

extern BOOL OBIsRunningUnitTests(void);

extern NSString *OBShortObjectDescription(id anObject);

extern CFStringRef const OBBuildByCompilerVersion;
    
// This macro ensures that we call [super initialize] in our +initialize (since this behavior is necessary for some classes in Cocoa), but it keeps custom class initialization from executing more than once.
#define OBINITIALIZE \
    do { \
        static BOOL hasBeenInitialized = NO; \
        [super initialize]; \
        if (hasBeenInitialized) \
            return; \
        hasBeenInitialized = YES;\
    } while (0);


// Sometimes a value is computed but not expected to be used and we wish to avoid clang dead store warnings.  For example, when laying out a stack of views, we might keep a running total of the used height and might want to do this for the last item stacked up (in case something is added later).
#define OB_UNUSED_VALUE(v) do { \
    void *__ptr __attribute__((unused)) = &v; /* ensure it is actually an l-value */ \
    typeof(v) __unused_value __attribute__((unused)) = v; \
} while(0)

#ifdef USING_BUGGY_CPP_PRECOMP
// Versions of cpp-precomp released before April 2002 have a bug that makes us have to do this
#define NSSTRINGIFY(name) @ ## '"' ## name ## '"'
#elif defined(__GNUC__)
    #if __GNUC__ < 3 || (__GNUC__ == 3 && __GNUC_MINOR__ < 3)
        // GCC before 3.3 requires this format
        #define NSSTRINGIFY(name) @ ## #name
    #else
        // GCC 3.3 requires this format
        #define NSSTRINGIFY(name) @#name
    #endif
#endif

// An easy way to define string constants.  For example, "NSSTRINGIFY(foo)" produces @"foo" and "DEFINE_NSSTRING(foo);" produces: NSString *foo = @"foo";

#define DEFINE_NSSTRING(name) \
	NSString * const name = NSSTRINGIFY(name)

// Emits a warning indicating that an obsolete method has been called.

#define OB_WARN_OBSOLETE_METHOD \
    do { \
        static BOOL warned = NO; \
            if (!warned) { \
                warned = YES; \
                    NSLog(@"Warning: obsolete method %c[%@ %s] invoked", OBPointerIsClass(self)?'+':'-', OBClassForPointer(self), _cmd); \
            } \
            OBASSERT_NOT_REACHED("obsolete method called"); \
    } while(0)

// Apple doesn't have an NSNotFound equivalent for NSUInteger values (NSNotFound is an NSInteger).
// Note that for APIs which should match Foundation APIs, you'll need to use NSNotFound even for NSUInteger values.
#define OB_NSUInteger_NotFound (~(NSUInteger)0)

#if NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
// Returns a copy of the method signature with the NSGeometry types replaced with CG types.  The result should be free'd by the caller.
__private_extern__ const char *_OBGeometryAdjustedSignature(const char *sig);
#endif

#if defined(__cplusplus)
} // extern "C"
#endif
