// Copyright 1997-2010, 2012-2013 Omni Development, Inc. All rights reserved.
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
#import <OmniBase/macros.h>


#include <sys/types.h>
#include <unistd.h>
#include <sys/sysctl.h>

RCS_ID("$Id$")

static BOOL _OBRegisterMethod(IMP imp, Class cls, const char *types, SEL name)
{
    return class_addMethod(cls, name, imp, types);
}

IMP OBRegisterInstanceMethodWithSelector(Class aClass, SEL oldSelector, SEL newSelector)
{
    Method newMethod = class_getInstanceMethod(aClass, newSelector);
    if (!newMethod) {
        OBASSERT_NOT_REACHED("No method for given new selector");
        return NULL;
    }
    
    return OBReplaceMethodImplementationFromMethod(aClass, oldSelector, newMethod);
}

IMP OBReplaceMethodImplementation(Class aClass, SEL oldSelector, IMP newImp)
{
    Method localMethod, superMethod;
    IMP oldImp = NULL;

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

IMP OBReplaceClassMethodImplementationWithSelector(Class aClass, SEL oldSelector, SEL newSelector)
{
    OBPRECONDITION(!class_isMetaClass(aClass));
    return OBReplaceMethodImplementationWithSelector(object_getClass(aClass), oldSelector, newSelector);
}

IMP OBReplaceClassMethodImplementationFromMethod(Class aClass, SEL oldSelector, Method newMethod)
{
    OBPRECONDITION(!class_isMetaClass(aClass));
    return OBReplaceMethodImplementationFromMethod(object_getClass(aClass), oldSelector, newMethod);
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

/*"
 This method returns a basic description for anObject, like implemented on NSObject. This allows you to get the basic description even if the normal description methods have been overridden.
 
 See also: - description (NSObject), - description (OBObject), - shortDescription (OBObject)
 "*/
NSString *OBShortObjectDescription(id anObject)
{
    if (!anObject)
        return nil;

    return [NSString stringWithFormat:@"<%@:%p>", NSStringFromClass([anObject class]), anObject];
}

NSString *OBShortObjectDescriptionWith(id anObject, NSString *extra)
{
    if (!anObject)
        return nil;
    
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([anObject class]), anObject, extra];
}

NSString *OBFormatObjectDescription(id anObject, NSString *fmt, ...)
{
    NSString *suffix, *result;
    va_list varg;
    
    if (!anObject)
        return nil;
    
    va_start(varg, fmt);
    suffix = [[NSString alloc] initWithFormat:fmt arguments:varg];
    va_end(varg);
    result = [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([anObject class]), anObject, suffix];
    OB_RELEASE(suffix);
    
    return result;
}

CFStringRef const OBBuildByCompilerVersion = CFSTR("OBBuildByCompilerVersion: " __VERSION__);

void _OBRequestConcreteImplementation(id self, SEL _cmd, const char *file, unsigned int line)
{
    NSString *reason = [NSString stringWithFormat:@"%@ needs a concrete implementation of %c%s at %s:%d", [self class], OBPointerIsClass(self) ? '+' : '-', sel_getName(_cmd), file, line];
    NSLog(@"%@", reason);
    
    OBASSERT_NOT_REACHED("Concrete implementation needed");
    
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

    [[NSException exceptionWithName:NSInvalidArgumentException reason:reasonString userInfo:nil] raise];
    exit(1);  // not reached, but needed to pacify the compiler
}

void _OBFinishPorting(const char *header, const char *function)
{
    NSLog(@"%s in %s", header, function);
    abort();
}

void _OBFinishPortingLater(const char *header, const char *function, const char *message)
{
#ifdef DEBUG
    NSLog(@"%s in %s -- %s", header, function, message);
#else
    NSLog(@"%s in %s", header, function);
#endif
}

BOOL OBIsBeingDebugged(void)
{
    struct kinfo_proc info = {};
    size_t size = sizeof(info);
    int mib[4] = {
        CTL_KERN,
        KERN_PROC,
        KERN_PROC_PID,
        getpid()
    };

    int rc = sysctl(mib, sizeof(mib) / sizeof(*mib), &info, &size, NULL, 0);
    OBASSERT(rc == 0);
    
    // We're being debugged if the P_TRACED flag is set.
    return (rc == 0 && (info.kp_proc.p_flag & P_TRACED) != 0);
}

void _OBStopInDebugger(const char *file, unsigned int line, const char *function, const char *message)
{
    NSLog(@"OBStopInDebugger at %s:%d in %s -- %s", file, line, function, message);
    
    BOOL isBeingDebugged = OBIsBeingDebugged();
    OBASSERT(isBeingDebugged);
    if (isBeingDebugged) {
        kill(getpid(), SIGTRAP);
    }
}

DEFINE_NSSTRING(OBAbstractImplementation);
DEFINE_NSSTRING(OBUnusedImplementation);

