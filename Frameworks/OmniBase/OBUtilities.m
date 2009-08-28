// Copyright 1997-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBUtilities.h>

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import <OmniBase/assertions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

static BOOL _OBRegisterMethod(IMP imp, Class cls, const char *types, SEL name)
{
    return class_addMethod(cls, name, imp, types);
}

IMP OBRegisterInstanceMethodWithSelector(Class aClass, SEL oldSelector, SEL newSelector)
{
    Method thisMethod;
    IMP oldImp = NULL;

    if ((thisMethod = class_getInstanceMethod(aClass, oldSelector))) {
        oldImp = method_getImplementation(thisMethod);
        _OBRegisterMethod(oldImp, aClass, method_getTypeEncoding(thisMethod), newSelector);
    }

    return oldImp;
}

IMP OBReplaceMethodImplementation(Class aClass, SEL oldSelector, IMP newImp)
{
    Method localMethod, superMethod;
    IMP oldImp = NULL;
    extern void _objc_flush_caches(Class);

    if ((localMethod = class_getInstanceMethod(aClass, oldSelector))) {
	oldImp = method_getImplementation(localMethod);
        Class superCls = class_getSuperclass(aClass);
	superMethod = superCls ? class_getInstanceMethod(superCls, oldSelector) : NULL;

	if (superMethod == localMethod) {
	    // We are inheriting this method from the superclass.  We do *not* want to clobber the superclass's Method as that would replace the implementation on a greater scope than the caller wanted.  In this case, install a new method at this class and return the superclass's implementation as the old implementation (which it is).
	    _OBRegisterMethod(newImp, aClass, method_getTypeEncoding(localMethod), oldSelector);
	} else {
	    // Replace the method in place
#ifdef OMNI_ASSERTIONS_ON
            IMP previous = 
#endif
            method_setImplementation(localMethod, newImp);
            OBASSERT(oldImp == previous); // method_setImplementation is supposed to return the old implementation, but we already grabbed it.
	}
    }
    
    return oldImp;
}

#if NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
static void _NSToCG(char *p)
{
    // Eat the '_'
    // strcpy(p, p+1); valgrind complains about this
    memmove(p, p+1, strlen(p+1) + 1); // include the NUL
    
    p[0] = 'C';
    p[1] = 'G';
}

const char *_OBGeometryAdjustedSignature(const char *sig)
{
    // Convert _NS{Point,Size,Rect} to CG{Point,Size,Rect}
    char *adj = strdup(sig);
    char *p;
    
    while ((p = strstr(adj, "_NSPoint=")))
        _NSToCG(p);
    while ((p = strstr(adj, "_NSSize=")))
        _NSToCG(p);
    while ((p = strstr(adj, "_NSRect=")))
        _NSToCG(p);
    
    return adj;
}
#endif

IMP OBReplaceMethodImplementationFromMethod(Class aClass, SEL oldSelector, Method newMethod)
{
    OBASSERT(newMethod != NULL);
    
    Method localMethod, superMethod;
    IMP oldImp = NULL;
    IMP newImp = method_getImplementation(newMethod);
    extern void _objc_flush_caches(Class);
    
    if ((localMethod = class_getInstanceMethod(aClass, oldSelector))) {
#ifdef OMNI_ASSERTIONS_ON
        {
            const char *oldSignature = method_getTypeEncoding(localMethod);
            const char *newSignature = method_getTypeEncoding(newMethod);
            BOOL freeSignatures = NO;
            
#if NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
            // Cocoa is built w/o this under 10.5, it seems. If we turn it on and then do method replacement, we'll get spurious warnings about type mismatches due to the struct name embedded in the type encoding.
            oldSignature = _OBGeometryAdjustedSignature(oldSignature);
            newSignature = _OBGeometryAdjustedSignature(newSignature);
            freeSignatures = YES;
#endif
            if (strcmp(oldSignature, newSignature) != 0) {
                NSLog(@"WARNING: OBReplaceMethodImplementation: Replacing %@ (signature: %s) with %@ (signature: %s)",
                      NSStringFromSelector(oldSelector), oldSignature,
                      NSStringFromSelector(method_getName(newMethod)), newSignature);
                OBASSERT_NOT_REACHED("Fix type signature mismatch");
            }
            
            if (freeSignatures) {
                free((char *)oldSignature);
                free((char *)newSignature);
            }
                
        }
#endif
	oldImp = method_getImplementation(localMethod);
        Class superCls = class_getSuperclass(aClass);
	superMethod = superCls ? class_getInstanceMethod(superCls, oldSelector) : NULL;
        
	if (superMethod == localMethod) {
	    // We are inheriting this method from the superclass.  We do *not* want to clobber the superclass's Method as that would replace the implementation on a greater scope than the caller wanted.  In this case, install a new method at this class and return the superclass's implementation as the old implementation (which it is).
	    _OBRegisterMethod(newImp, aClass, method_getTypeEncoding(localMethod), oldSelector);
	} else {
	    // Replace the method in place
#ifdef OMNI_ASSERTIONS_ON
            IMP previous = 
#endif
            method_setImplementation(localMethod, newImp);
            OBASSERT(oldImp == previous); // method_setImplementation is supposed to return the old implementation, but we already grabbed it.
	}
	
#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
	// Flush the method cache
	_objc_flush_caches(aClass);
#endif
    }
    
    return oldImp;
}

IMP OBReplaceMethodImplementationWithSelector(Class aClass, SEL oldSelector, SEL newSelector)
{
    return OBReplaceMethodImplementationFromMethod(aClass, oldSelector, class_getInstanceMethod(aClass, newSelector));
}

IMP OBReplaceMethodImplementationWithSelectorOnClass(Class destClass, SEL oldSelector, Class sourceClass, SEL newSelector)
{
    return OBReplaceMethodImplementationFromMethod(destClass, oldSelector, class_getInstanceMethod(sourceClass, newSelector));
}

// Returns the class in the inheritance chain of 'cls' that actually implements the given selector, or Nil if it isn't implemented
Class OBClassImplementingMethod(Class cls, SEL sel)
{
    Method method = class_getInstanceMethod(cls, sel);
    if (!method)
	return Nil;

    // *Some* class must implement it
    Class superClass;
    while ((superClass = class_getSuperclass(cls))) {
	Method superMethod = class_getInstanceMethod(superClass, sel);
	if (superMethod != method)
	    return cls;
	cls = superClass;
    }
    
    return cls;
}

BOOL OBIsRunningUnitTests(void)
{
    static BOOL checked = NO;
    static BOOL runningUnitTests = NO;
    
    if (!checked) {
        checked = YES;
        runningUnitTests = NSClassFromString(@"SenTestCase") != Nil;
    }
    
    return runningUnitTests;
}

/*"
 This method returns the original description for anObject, as implemented on NSObject. This allows you to get the original description even if the normal description methods have been overridden.
 
 See also: - description (NSObject), - description (OBObject), - shortDescription (OBObject)
 "*/
NSString *OBShortObjectDescription(id anObject)
{
    if (!anObject)
        return nil;
    
    static IMP nsObjectDescription = NULL;
    if (!nsObjectDescription) {
        Method descriptionMethod = class_getInstanceMethod([NSObject class], @selector(description));
        nsObjectDescription = method_getImplementation(descriptionMethod);
        OBASSERT(nsObjectDescription);
    }
    
    return nsObjectDescription(anObject, @selector(description));
}

CFStringRef const OBBuildByCompilerVersion = CFSTR("OBBuildByCompilerVersion: " __VERSION__);

void _OBRequestConcreteImplementation(id self, SEL _cmd, const char *file, unsigned int line)
{
    OBASSERT_NOT_REACHED("Concrete implementation needed");

    NSString *reason = [NSString stringWithFormat:@"%@ needs a concrete implementation of %c%s at %s:%d", [self class], OBPointerIsClass(self) ? '+' : '-', sel_getName(_cmd), file, line];
    NSLog(@"%@", reason);
    
    [[NSException exceptionWithName:OBAbstractImplementation reason:reason userInfo:nil] raise];
    
    exit(1);  // notreached, but needed to pacify the compiler
}

void _OBRejectUnusedImplementation(id self, SEL _cmd, const char *file, unsigned int line)
{
    OBASSERT_NOT_REACHED("Subclass rejects unused implementation");

    NSString *reason = [NSString stringWithFormat:@"%c[%@ %s] should not be invoked (%s:%d)", OBPointerIsClass(self) ? '+' : '-', OBClassForPointer(self), sel_getName(_cmd), file, line];
    NSLog(@"%@", reason);

    [[NSException exceptionWithName:OBUnusedImplementation reason:reason userInfo:nil] raise];

    exit(1);  // notreached, but needed to pacify the compiler
}

void _OBRejectInvalidCall(id self, SEL _cmd, const char *file, unsigned int line, NSString *format, ...)
{
    const char *className = class_getName(OBClassForPointer(self));
    const char *methodName = sel_getName(_cmd);
    
    va_list argv;
    va_start(argv, format);
    NSString *complaint = [[NSString alloc] initWithFormat:format arguments:argv];
    va_end(argv);
    
#ifdef DEBUG
    fprintf(stderr, "Invalid call on:\n%s:%d\n", file, line);
#endif
    
    NSString *reasonString = [NSString stringWithFormat:@"%c[%s %s] (%s:%d) %@", OBPointerIsClass(self) ? '+' : '-', className, methodName, file, line, complaint];
    NSLog(@"%@", reasonString);

    [complaint release];
    [[NSException exceptionWithName:NSInvalidArgumentException reason:reasonString userInfo:nil] raise];
    exit(1);  // notreached, but needed to pacify the compiler
}

DEFINE_NSSTRING(OBAbstractImplementation);
DEFINE_NSSTRING(OBUnusedImplementation);
