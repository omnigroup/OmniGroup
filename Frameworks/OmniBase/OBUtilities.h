// Copyright 1997-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSString.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSDate.h>
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <CoreGraphics/CGGeometry.h>
#import <UIKit/UIGeometry.h>
#else
#import <Foundation/NSGeometry.h> // For NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
#endif

#import <OmniBase/assertions.h>
#import <OmniBase/objc.h>
#import <OmniBase/macros.h>

#if defined(__cplusplus)
extern "C" {
#endif
    
#if defined(__GNUC__)
#define NORETURN __attribute__ ((noreturn))
#else
#define NORETURN
#endif

#define OB_DEPRECATED_ATTRIBUTE __attribute__((deprecated))

// In some cases, we really need to keep an object alive. For example, we may have a window controller that will release itself in response to its window being closed.
static inline void OBStrongRetain(id object)
{
    if (object) {
        void *ptr = (OB_BRIDGE void *)object;
        CFRetain(ptr);
    }
}
    
static inline void OBStrongRelease(id object)
{
    if (object) {
        void *ptr = (OB_BRIDGE void *)object;
        CFRelease(ptr);
    }
}
    
static inline void OBAutorelease(id object)
{
    if (object) {
        void *ptr = (OB_BRIDGE void *)object;
        CFAutorelease(ptr);
    }
}
    
static inline void OBRetainAutorelease(id object)
{
    OBStrongRetain(object);
    OBAutorelease(object);
}

/*
 A best guess at what macros might indicate availability and usefulness of the GC APIs.
 
 The -fobjc-gc flag controls __OBJC_GC__ .
 The <objc/objc-auto.h> header defines OBJC_NO_GC, but only based on target macros, not on the compiler options.
 
 There doesn't seem to be a way to distinguish between -fobjc-gc and -fobjc-gc-only, but maybe that's just as well because even in the GC case we need to *pretend* to be able to use the malloc pointer until we're done with any interior pointers. 
*/

#if !defined(__OBJC_GC__) || defined(OBJC_NO_GC) || (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE)
    #define OBAllocateCollectable(size,flags) malloc(size)
    #define OBReallocateCollectable(ptr,size,flags) realloc((ptr),(size))
    
    #define OBAllocateScanned(size) malloc(size)
    #define OBFreeScanned(ptr) free(ptr)
#else
    #include <objc/objc-auto.h> /* For objc_collectingEnabled() */
    
    #define OBAllocateCollectable NSAllocateCollectable
    #define OBReallocateCollectable NSReallocateCollectable

    #define OBAllocateScanned(size) NSAllocateCollectable((size), NSScannedOption)
    #define OBFreeScanned(ptr) do{ if(!objc_collectingEnabled()) free(ptr); }while(0)
#endif

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    // There is only one bundle on iPhone/iPad.
    #define OMNI_BUNDLE [NSBundle mainBundle]
#else
    // This uses the OMNI_BUNDLE_IDENTIFIER compiler define set by the OmniGroup/Configurations/*Global*.xcconfig to look up the bundle for the calling code.
    #define OMNI_BUNDLE _OBBundleWithIdentifier(OMNI_BUNDLE_IDENTIFIER)
    static inline NSBundle *_OBBundleWithIdentifier(NSString *identifier)
    {
        OBPRECONDITION([identifier length] > 0); // Did you forget to set OMNI_BUNDLE_IDENTIFIER in your target?
        NSBundle *bundle = [NSBundle bundleWithIdentifier:identifier];
        OBPOSTCONDITION(bundle); // Did you set it to the wrong thing?
        return bundle;
    }
#endif
    
extern void _OBRequestConcreteImplementation(id self, SEL _cmd, const char *file, unsigned int line) NORETURN;
extern void _OBRejectUnusedImplementation(id self, SEL _cmd, const char *file, unsigned int line) NORETURN;
extern void _OBRejectInvalidCall(id self, SEL _cmd, const char *file, unsigned int line, NSString *format, ...)
                    NORETURN __attribute__((format(__NSString__, 5, 6)));

#define OBRequestConcreteImplementation(self, sel) _OBRequestConcreteImplementation((self), (sel), __FILE__, __LINE__)
#define OBRejectUnusedImplementation(self, sel) _OBRejectUnusedImplementation((self), (sel), __FILE__, __LINE__)
#define OBRejectInvalidCall(self, sel, format, ...) _OBRejectInvalidCall((self), (sel), __FILE__, __LINE__, (format), ## __VA_ARGS__)

// A common pattern when refactoring or updating code is to #if 0 out portions that haven't been updated and leave a marker there.  This function serves as the 'to do' marker and allows you to demand-port the remaining code after working out the general structure.
// NOTE: The formatting of the "header" argument is formulated so you can run 'strings' on your binary and find a list of all the file:line locations of these.
extern void _OBFinishPorting(const char *header, const char *function) NORETURN;
#define _OBFinishPorting_(file, line, function) _OBFinishPorting("OBFinishPorting at " file ":" #line, function)
#define _OBFinishPorting__(file, line, function) _OBFinishPorting_(file, line, function)
#define OBFinishPorting _OBFinishPorting__(__FILE__, __LINE__, __PRETTY_FUNCTION__)

// Something that needs porting, but not immediately
extern void _OBFinishPortingLater(const char *header, const char *function, const char *message);
#define _OBFinishPortingLater_(file, line, function, message) _OBFinishPortingLater("OBFinishPortingLater at " file ":" #line, function, (message))
#define _OBFinishPortingLater__(file, line, function, message) _OBFinishPortingLater_(file, line, function, (message))
#define OBFinishPortingLater(msg) do { \
    static BOOL warned = NO; \
    if (!warned) { \
        warned = YES; \
        _OBFinishPortingLater__(__FILE__, __LINE__, __PRETTY_FUNCTION__, (msg)); \
    } \
} while(0)
    
extern BOOL OBIsBeingDebugged(void);
extern void _OBStopInDebugger(const char *file, unsigned int line, const char *function, const char *message);
#define OBStopInDebugger(message) _OBStopInDebugger(__FILE__, __LINE__, __PRETTY_FUNCTION__, (message))
#define OBStepThroughAndVerify() _OBStopInDebugger(__FILE__, __LINE__, __PRETTY_FUNCTION__, "Step through and verify.")
    
extern NSString * const OBAbstractImplementation;
extern NSString * const OBUnusedImplementation;

#if defined(DEBUG)
#define OB_DEBUG_LOG_CALLER() do { NSArray *syms = [NSThread callStackSymbols]; if ([syms count] > 1) NSLog(@"caller: %@", [syms objectAtIndex:1U]); } while (0)
#else
#define OB_DEBUG_LOG_CALLER()
#endif
    
enum OBBacktraceBufferType {
    OBBacktraceBuffer_Unused = 0,      /* Indicates an unused slot */
    OBBacktraceBuffer_Allocated = 1,   /* Allocated but not filled slot */
    
    /* Remaining integers represent different reasons for recording a backtrace */
    OBBacktraceBuffer_OBAssertionFailure = 2,
    OBBacktraceBuffer_NSAssertionFailure = 3,
    OBBacktraceBuffer_NSException = 4,
};
void OBRecordBacktrace(const char *ctxt, unsigned int optype);
/*.doc.
  Records a backtrace for possible debugging use in the future. ctxt and optype are free for the caller to use for their own purposes, but optype must be greater than one.
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

extern IMP OBReplaceClassMethodImplementationWithSelector(Class aClass, SEL oldSelector, SEL newSelector);
/*.doc.
Calls OBReplaceMethodImplementationWithSelector with aClass's metaclass as the class argument. aClass must not itself be a metaclass.
*/

extern IMP OBReplaceClassMethodImplementationFromMethod(Class aClass, SEL oldSelector, Method newMethod);
/*.doc.
Calls OBReplaceMethodImplementationFromMethod with aClass's metaclass as the class argument. aClass must not itself be a metaclass.
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
	return object_getClass(object);
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

extern NSString *OBShortObjectDescription(id anObject);
extern NSString *OBShortObjectDescriptionWith(id anObject, NSString *extra);
extern NSString *OBFormatObjectDescription(id anObject, NSString *fmt, ...)
    __attribute__((format(__NSString__, 2, 3)));


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
// Using overloadable functions here lets us handle object types (since we can't cast those to void * w/o __bridge and we can't cast non object types to void * _with_ __bridge).
static inline void __attribute__((overloadable)) _OBUnusedValue(id v) {
    __strong id *__ptr __attribute__((unused)) = &v; /* ensure it is actually an l-value */ \
    typeof(v) __unused_value __attribute__((unused)) = v;
}
#define OB_UNUSED_VALUE_FOR_TYPE(T) \
static inline void __attribute__((overloadable)) _OBUnusedValue(T v) { \
    void *__ptr __attribute__((unused)) = (void *)&v; /* ensure it is actually an l-value */ \
    typeof(v) __unused_value __attribute__((unused)) = v; \
}
OB_UNUSED_VALUE_FOR_TYPE(int8_t)
OB_UNUSED_VALUE_FOR_TYPE(int16_t)
OB_UNUSED_VALUE_FOR_TYPE(int32_t)
OB_UNUSED_VALUE_FOR_TYPE(int64_t)
OB_UNUSED_VALUE_FOR_TYPE(uint8_t)
OB_UNUSED_VALUE_FOR_TYPE(uint16_t)
OB_UNUSED_VALUE_FOR_TYPE(uint32_t)
OB_UNUSED_VALUE_FOR_TYPE(uint64_t)
OB_UNUSED_VALUE_FOR_TYPE(NSUInteger)
OB_UNUSED_VALUE_FOR_TYPE(NSInteger)
OB_UNUSED_VALUE_FOR_TYPE(float)
OB_UNUSED_VALUE_FOR_TYPE(double)
OB_UNUSED_VALUE_FOR_TYPE(void *)
OB_UNUSED_VALUE_FOR_TYPE(const void *)
OB_UNUSED_VALUE_FOR_TYPE(CGPoint)
OB_UNUSED_VALUE_FOR_TYPE(CGSize)
OB_UNUSED_VALUE_FOR_TYPE(CGRect)
    
#define OB_UNUSED_VALUE(v) _OBUnusedValue(v)

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

// Iterators over C arrays and literals. Useful for iterating over collections known at compile-time, like when (un)registering KVO keypaths. Syntax is similar to a regular for(.. in ..) statement; the first argument is a variable name that is visible within the scope of the block controlled by the OB_FOR_ALL or OB_FOR_IN statement. The subsequent arguments vary.

// Helper macro that drives iteration of the variable named by OB_FOR_var_name over the array named by OB_FOR_array_name.
#define OB_FOR_exprs(OB_FOR_var_name, OB_FOR_array_name) \
        *OB_FOR_IN_end = &OB_FOR_array_name[sizeof(OB_FOR_array_name)/sizeof(OB_FOR_array_name[0])], /* Points one past the end of the array */ \
        *OB_FOR_IN_curr = &OB_FOR_array_name[0], \
        OB_FOR_var_name = OB_FOR_array_name[0]; \
    OB_FOR_IN_curr < OB_FOR_IN_end ? (OB_FOR_var_name = *OB_FOR_IN_curr, 1) : 0; /* Avoid dereferencing pointer one past the end of the array, even if we never use it */ \
    OB_FOR_IN_curr++
    
// OB_FOR_ALL takes a variable number of arguments (at least two) and iterates over all of them.
// Ex:
//     OB_FOR_ALL(i, 1, 2, 3)
//       printf("%d", i);
#define OB_FOR_ALL(var, one, ...) for(typeof(one) OB_FOR_ALL_array[] = { one, __VA_ARGS__ }, OB_FOR_exprs(var, OB_FOR_ALL_array))
    
// OB_FOR_IN takes a single array variable as an argument and iterates over its members.
// Ex:
//     int nums[] = {1, 2, 3};
//     OB_FOR_IN(i, nums)
//       printf("%d", i);
#define OB_FOR_IN(var, array) for (typeof(array[0]) OB_FOR_exprs(var, array))

// Emits a warning indicating that an obsolete method has been called.

#define OB_WARN_OBSOLETE_METHOD \
    do { \
        static BOOL warned = NO; \
            if (!warned) { \
                warned = YES; \
                    NSLog(@"Warning: obsolete method %c[%@ %@] invoked", OBPointerIsClass(self)?'+':'-', OBClassForPointer(self), NSStringFromSelector(_cmd)); \
            } \
            OBASSERT_NOT_REACHED("obsolete method called"); \
    } while(0)

// Apple doesn't have an NSNotFound equivalent for NSUInteger values (NSNotFound is an NSInteger).
// Note that for APIs which should match Foundation APIs, you'll need to use NSNotFound even for NSUInteger values.
#define OB_NSUInteger_NotFound (~(NSUInteger)0)

#if NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
// Returns a copy of the method signature with the NSGeometry types replaced with CG types.  The result should be free'd by the caller.
__attribute__((visibility("hidden"))) const char *_OBGeometryAdjustedSignature(const char *sig);
#endif

// Inttypes-style format macros for Apple-defined types
#if __LP64__ || (TARGET_OS_EMBEDDED && !TARGET_OS_IPHONE) || TARGET_OS_WIN32 || NS_BUILD_32_LIKE_64
// On these platforms NSInteger=long and NSUInteger=unsigned long
#define PRI_NSInteger_LENGTH_MODIFIER "l"
#else
// On these platforms NSInteger=int and NSUInteger=unsigned int
#define PRI_NSInteger_LENGTH_MODIFIER ""
#endif

#define PRIdNS PRI_NSInteger_LENGTH_MODIFIER "d"
#define PRIiNS PRI_NSInteger_LENGTH_MODIFIER "i"
#define PRIoNS PRI_NSInteger_LENGTH_MODIFIER "o"
#define PRIuNS PRI_NSInteger_LENGTH_MODIFIER "u"
#define PRIxNS PRI_NSInteger_LENGTH_MODIFIER "x"
#define PRIXNS PRI_NSInteger_LENGTH_MODIFIER "X"

// OSStatus is SInt32, which is int on 64-bit and long on 32-bit. Similar problems hit CFStringEncoding and UnicodeScalarValue
// note this is unaffected by NS_BUILD_32_LIKE_64, etc.
#if __LP64__
    // On these platforms, UInt32 and SInt32 are (unsigned) int, and therefore so is OSStatus
    #define PRI_OSStatus "d"
    #define PRI_CFStringEncoding "u"
    #define PRI_UnicodeScalarValue "u"
#else
    // On these platforms, UInt32 and SInt32 are (unsigned) long, and therefore so is OSStatus
    #define PRI_OSStatus "ld"
    #define PRI_CFStringEncoding "lu"
    #define PRI_UnicodeScalarValue "lu"
#endif

// ptrdiff_t
#define PRI_ptrdiff "td"

/* CFIndex is always a signed long as far as I know */
#define PRIdCFIndex "ld"
    
#if defined(__cplusplus)
} // extern "C"
#endif
