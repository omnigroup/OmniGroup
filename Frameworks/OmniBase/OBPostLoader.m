// Copyright 1997-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBPostLoader.h>

#import <OmniBase/OBUtilities.h>
#import <OmniBase/assertions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/objc.h>

#import <dlfcn.h>

RCS_ID("$Id$")

static NSRecursiveLock *lock = nil;
static NSHashTable *calledImplementations = NULL;
static BOOL isMultiThreaded = NO;
static BOOL isSendingBecomingMultiThreaded = NO;

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
extern void _objc_resolve_categories_for_class(struct objc_class *cls);
#endif

// This can produce lots of false positivies, but provides a way to start looking for some potential problem cases.
#if 0 && defined(DEBUG)
#define OB_CHECK_COPY_WITH_ZONE
#endif

@interface OBPostLoader (PrivateAPI)
+ (BOOL)_processSelector:(SEL)selectorToCall inClass:(Class)aClass initialize:(BOOL)shouldInitialize;
+ (void)_becomingMultiThreaded:(NSNotification *)note;
#ifdef OMNI_ASSERTIONS_ON
+ (void)_validateMethodSignatures;
+ (void)_checkForMethodsInDeprecatedProtocols;
#endif
#ifdef OB_CHECK_COPY_WITH_ZONE
+ (void)_checkCopyWithZoneImplementations;
#endif
@end

//#define POSTLOADER_DEBUG

@implementation OBPostLoader
/*"
OBPostLoader provides the functionality that you might expect to get from implementing a +load method.  Unfortunately, some implementations of OpenStep have bugs with their implementation of +load.  Rather than attempt to use +load, OBPostLoader provides similar functionality that actually works.  Early in your program startup, you should call +processClasses.  This will go through the ObjC runtime and invoke all of the +performPosing and +didLoad methods.  Each class may have multiple implementations of each of theses selectors -- all will be called.

OBPostLoader listens for bundle loaded notifications and will automatically reinvoke +processClasses to perform any newly loaded methods.

OBPostLoader also listens for NSBecomingMultiThreaded and will invoke every implementation of +becomingMultiThreaded.
"*/

+ (void)initialize;
{
    OBINITIALIZE;

    // We used to allocate this only when going multi-threaded, but this can happen while we are in the middle of processing a selector (that is, a +didLoad can fork a thread).  In this case we'd end up 'locking' nil when starting the +didLoad processing and then unlocking a non-nil lock that we didn't own.  We could create the lock in +_becomingMultiThreaded: _and_ lock it if we are in the middle of +processSelector:initialize:, but that's just getting too complicated.
    lock = [[NSRecursiveLock alloc] init];
    
    // Set this up before we call any method implementations
    calledImplementations = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);

    // If any other bundles get loaded, make sure that we process them too.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bundleDidLoad:) name:NSBundleDidLoadNotification object:nil];

    // Register for the multi-threadedness here so that most classes won't have to
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_becomingMultiThreaded:) name:NSWillBecomeMultiThreadedNotification object:nil];
}

/*"
Searches the ObjC runtime for particular methods and invokes them.  Each implementation will be invoked exactly once.  Currently, there is no guarantee on the order that these messages will occur.  This should be called as the first line of main().  Once this has been called at the beginning of main, it will automatically be called each time a bundle is loaded (view the NSBundle loading notification).

This method makes several passes, each time invoking a different selector.  On the first pass, +performPosing implementations are invoked, allowing modifictions to the ObjC runtime to happen early (before +initialize).  Then, +didLoad implementations are processed.
"*/
+ (void)processClasses;
{
    [self processSelector:@selector(performPosing) initialize:NO];
    [self processSelector:@selector(didLoad) initialize:YES];
    
    // Handle the case that this doesn't get called until after we've gone multi-threaded
    if ([NSThread isMultiThreaded])
        [self _becomingMultiThreaded:nil];
    
#ifdef OMNI_ASSERTIONS_ON
    [self _validateMethodSignatures];
    [self _checkForMethodsInDeprecatedProtocols];
#endif
#ifdef OB_CHECK_COPY_WITH_ZONE
    [self _checkCopyWithZoneImplementations];
#endif
}

/*"
This method does the work of looping over the runtime searching for implementations of selectorToCall and invoking them when they haven't already been invoked.
"*/
+ (void)processSelector:(SEL)selectorToCall initialize:(BOOL)shouldInitialize;
{
    BOOL didInvokeSomething = YES;

    [lock lock];

    // We will collect the necessary information from the runtime before calling any method implementations.  This is necessary since any once of the implementations that we call could actually modify the ObjC runtime.  It could add classes or methods.

    while (didInvokeSomething) {
        int classCount = 0, newClassCount;
        Class *classes = NULL;

        // Start out claiming to have invoked nothing.  If this doesn't get reset to YES below, we're done.
        didInvokeSomething = NO;

        // Get the class list
        newClassCount = objc_getClassList(NULL, 0);
        while (classCount < newClassCount) {
            classCount = newClassCount;
            classes = realloc(classes, sizeof(Class) * classCount);
            newClassCount = objc_getClassList(classes, classCount);
        }

        // Now, use the class list; if NULL, there are no classes
        if (classes != NULL) {
            int classIndex;
            
            // Loop over the gathered classes and process the requested implementations
            for (classIndex = 0; classIndex < classCount; classIndex++) {
                Class aClass = classes[classIndex];

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
                // TJW: After some investiation, I tracked down the ObjC runtime bug that Steve was running up against in OmniOutliner when he needed to add this (I also hit it in OmniGraffle when trying to get rid of this line).  The bug is essentially that categories don't get registered when you pose before +initialize.  Logged as Radar #3319132.
                _objc_resolve_categories_for_class(aClass);
#endif
                
                if ([self _processSelector:selectorToCall inClass:aClass initialize:shouldInitialize])
                    didInvokeSomething = YES;
            }
        }

        // Free the class list
        free(classes);
    }

    [lock unlock];
}

+ (void) bundleDidLoad: (NSNotification *) notification;
{
    [self processClasses];
}

/*"
This can be used instead of +[NSThread isMultiThreaded].  The difference is that this method doesn't return YES until after going multi-threaded, whereas the NSThread version starts returning YES before the NSWillBecomeMultiThreadedNotification is sent.
"*/
+ (BOOL)isMultiThreaded;
{
    return isMultiThreaded;
}

@end



@implementation OBPostLoader (PrivateAPI)

+ (BOOL)_processSelector:(SEL) selectorToCall inClass:(Class)aClass initialize:(BOOL)shouldInitialize;
{
    Class metaClass = object_getClass(aClass); // we are looking at class methods

    unsigned int impSize = 256;
    unsigned int impIndex, impCount = 0;
    IMP *imps = NSZoneMalloc(NULL, sizeof(IMP) * impSize);
    

#if defined(POSTLOADER_DEBUG)
    //fprintf(stderr, "Checking for implementations of +[%s %s]\n", class_getName(aClass), sel_getName(selectorToCall));
#endif
    // Gather all the method implementations of interest on this class before invoking any of them.  This is necessary since they might modify the ObjC runtime.
    unsigned int methodIndex, methodCount;
    Method *methodList = class_copyMethodList(metaClass, &methodCount);
    for (methodIndex = 0; methodIndex < methodCount; methodIndex++) {
        Method m = methodList[methodIndex];
        
        if (method_getName(m) == selectorToCall) {
            IMP imp = method_getImplementation(m);
            
            // Store this implementation if it hasn't already been called
            if (!NSHashGet(calledImplementations, imp)) {
                if (impCount >= impSize) {
                    impSize *= 2;
                    imps = NSZoneRealloc(NULL, imps, sizeof(IMP) * impSize);
                }
                
                imps[impCount] = imp;
                impCount++;
                NSHashInsertKnownAbsent(calledImplementations, imp);
                
#if defined(POSTLOADER_DEBUG)
                fprintf(stderr, "Recording +[%s %s] (%p)\n", class_getName(aClass), sel_getName(selectorToCall), (void *)imp);
#endif
            }
        }
    }
    if (methodList)
        free(methodList);
    
    if (impCount) {
        if (shouldInitialize) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#if defined(POSTLOADER_DEBUG)
            fprintf(stderr, "Initializing %s\n", class_getName(aClass));
#endif
            // try to make sure +initialize gets called
            if (class_getClassMethod(aClass, @selector(class)))
                [aClass class];
            else if (class_getClassMethod(aClass, @selector(initialize)))
                // Avoid a compiler warning
                objc_msgSend(aClass, @selector(initialize));
            [pool release];
        }

        for (impIndex = 0; impIndex < impCount; impIndex++) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#if defined(POSTLOADER_DEBUG)
            fprintf(stderr, "Calling (%p) ... ", (void *)imps[impIndex]);
#endif
            // We now call this within an exception handler because twice now we've released versions of OmniWeb where something would raise within +didLoad on certain configurations (not configurations we had available for testing) and weren't getting caught, resulting in an application that won't launch on those configurations.  We could insist that everyone do their own exception handling in +didLoad, but if we're going to potentially crash because a +didLoad failed I'd rather crash later than now.  (Especially since the exceptions in question were perfectly harmless.)
            @try {
                // We discovered that we'll crash if we use aClass after it has posed as another class.  So, we go look up the imposter class that resulted from the +poseAs: and use it instead.
                Class imposterClass = objc_getClass(class_getName(metaClass));
                if (imposterClass != Nil)
                    aClass = imposterClass;
                
                imps[impIndex](aClass, selectorToCall);
            } @catch (NSException *exc) {
                fprintf(stderr, "Exception raised by +[%s %s]: %s\n", class_getName(aClass), sel_getName(selectorToCall), [[exc reason] UTF8String]);
            }
#if defined(POSTLOADER_DEBUG)
            fprintf(stderr, "done\n");
#endif
            [pool release];
        }
    }

    NSZoneFree(NULL, imps);

    return impCount != 0;
}


+ (void)_becomingMultiThreaded:(NSNotification *)note;
{
    if (isSendingBecomingMultiThreaded)
        return;

    isSendingBecomingMultiThreaded = YES;

    @try {
        [self processSelector:@selector(becomingMultiThreaded) initialize:NO];
    } @catch (NSException *exc) {
        NSLog(@"Ignoring exception raised while sending -becomingMultiThreaded.  %@", exc);
    }

    isMultiThreaded = YES;
    isSendingBecomingMultiThreaded = NO;
}

#ifdef OMNI_ASSERTIONS_ON

static unsigned MethodSignatureConflictCount = 0;
static unsigned SuppressedConflictCount = 0;
static unsigned MethodMultipleImplementationCount = 0;

static char *_copyNormalizeMethodSignature(const char *sig)
{
    // Radar 6328901: No #defines for ObjC runtime method type encodings 'V' and 'O'
    if (sig[0] == 'V' && sig[1] == 'v') {
        // oneway void; don't care to check the 'oneway' bit
        sig++;
    }
    
    // Easy calling convention; don't care how fast this code is since it is OMNI_ASSERTIONS_ON
    char *copy = strdup(sig);
    
    char *src = copy, *dst = copy, c;
    do {
        c = *src;
	
	// Strip out any 'bycopy' markers (no #define for this either)
        if (c == 'O' && src[1] == '@') {  // O@ means 'bycopy'; just want to copy the '@'.  Can't strip every 'O' since it might be part of a struct name (but only objects can be bycopy).
            *dst = '@';
	    dst += 1;
	    src += 2;
	    continue;
        }
	
	// Strip out 'inout' markers 'N' (no #define for this either)
	if (c == 'N' && src[1] == '^') {
            *dst = '^';
	    dst += 1;
	    src += 2;
	    continue;
	}
	
	// Default, just copy it.
	*dst = c;
	dst++;
        src++;
    } while (c);
    
    //if (strcmp(sig, copy)) NSLog(@"Normalized '%s' to '%s'", sig, copy);
    
    return copy;
}

static BOOL _methodSignaturesCompatible(SEL sel, const char *sig1, const char *sig2)
{
    /* In the vast majority of cases (99.7% of the time in my test with Dazzle) the two pointers passed to this routine are actually the same pointer. */
    if (sig1 == sig2)
        return YES;

    /* In > 90% of the *remaining* cases, the signatures are identical even without normalization. */
    if (strcmp(sig1, sig2) == 0)
        return YES;
    
    char *norm1 = _copyNormalizeMethodSignature(sig1);
    char *norm2 = _copyNormalizeMethodSignature(sig2);

    BOOL compatible = (strcmp(norm1, norm2) == 0);

    free(norm1);
    free(norm2);

    if (!compatible) {
        // A couple cases in QuartzCore where somehow one version has the offset info and the other doesn't.
        if (((strcmp(sig1, "v@:d") == 0) || (strcmp(sig2, "v@:d") == 0)) &&
            ((strcmp(sig1, "v16@0:4d8") == 0) || (strcmp(sig2, "v16@0:4d8") == 0)))
            return YES;
        if (((strcmp(sig1, "v@:@") == 0) || (strcmp(sig2, "v@:@") == 0)) &&
            ((strcmp(sig1, "v12@0:4@8") == 0) || (strcmp(sig2, "v12@0:4@8") == 0)))
            return YES;
        
        // Radar 6529241: Incorrect dragging source method declarations in AppKit.
        // NSControl and NSTableView have mismatching signatures for these methods (32/64 bit issue).
        if (sel == @selector(draggingSourceOperationMaskForLocal:) &&
            ((strcmp(sig1, "I12@0:4c8") == 0 && strcmp(sig2, "L12@0:4c8") == 0) ||
             (strcmp(sig1, "L12@0:4c8") == 0 && strcmp(sig2, "I12@0:4c8") == 0)))
            return YES;
        
        if (sel == @selector(draggedImage:endedAt:operation:) &&
            ((strcmp(sig1, "v24@0:4@8{CGPoint=ff}12I20") == 0 && strcmp(sig2, "v24@0:4@8{CGPoint=ff}12L20") == 0) ||
             (strcmp(sig1, "v24@0:4@8{CGPoint=ff}12L20") == 0 && strcmp(sig2, "v24@0:4@8{CGPoint=ff}12I20") == 0)))
            return YES;
        
    }
    return compatible;
}

static NSString *describeMethod(Method m, BOOL *nonSystem)
{
    Dl_info dli;
    IMP i = method_getImplementation(m);
    if (!dladdr(i, &dli)) { dli.dli_fname = NULL; dli.dli_sname = NULL; dli.dli_saddr = NULL; }
    
    NSMutableString *buf = [NSMutableString stringWithFormat:@"imp %s at %p",
                            dli.dli_sname? dli.dli_sname : "(unknown)",
                            i];
    
    if (i != dli.dli_saddr)
        [buf appendFormat:@"/%p", dli.dli_saddr];
    
    if (dli.dli_fname) {
        [buf appendString:@" in "];
        NSString *path = [NSString stringWithCString:dli.dli_fname encoding:NSUTF8StringEncoding];
        NSArray *parts = [path componentsSeparatedByString:@"/"];
        NSUInteger c = [parts count];
        if (c > 3 && [[parts objectAtIndex:c-3] isEqual:@"Versions"] && [[parts objectAtIndex:c-4] isEqual:[[parts objectAtIndex:c-1] stringByAppendingString:@".framework"]]) {
            [buf appendString:[parts objectAtIndex:c-4]];
        } else if (c > 1) {
            [buf appendString:[parts objectAtIndex:c-1]];
        } else {
            [buf appendString:path];
        }
        
        if (![path hasPrefix:@"/System/"] && ![path hasPrefix:@"/usr/lib/"])
            *nonSystem = YES;
    }
    
    return buf;
}

struct sorted_sel_info {
    Method meth;
    const char *mname;
};

static int compare_by_sel(const void *a, const void *b)
{
    return strcmp( ((struct sorted_sel_info *)a)->mname, ((struct sorted_sel_info *)b)->mname );
}

static void  __attribute__((unused)) _checkSignaturesWithinClass(Class cls, Method *methods, unsigned int methodCount)
{
    // Any given selector should only be implemented once on a given class.
    struct sorted_sel_info *sorted;
    sorted = malloc(methodCount * sizeof(*sorted));
    
    unsigned int checkedMethodCount = 0;
    
    for(unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex ++) {
        SEL msel = method_getName(methods[methodIndex]);
        /* There are some methods that we expect to be multiply defined */
        if (class_isMetaClass(cls) && (sel_isEqual(msel, @selector(didLoad)) || sel_isEqual(msel, @selector(performPosing)) || sel_isEqual(msel, @selector(becomingMultiThreaded))))
            continue;
        sorted[checkedMethodCount++] = (struct sorted_sel_info){
            .meth = methods[methodIndex],
            .mname = sel_getName(msel)
        };
    }
    
    qsort(sorted, checkedMethodCount, sizeof(*sorted), compare_by_sel);
    for(unsigned int methodIndex = 1; methodIndex < checkedMethodCount; methodIndex ++) {
        if (!strcmp(sorted[methodIndex-1].mname, sorted[methodIndex].mname)) {
            BOOL nonSystem = NO;
            NSString *a = describeMethod(sorted[methodIndex-1].meth, &nonSystem);
            NSString *b = describeMethod(sorted[methodIndex].meth, &nonSystem);
            if (nonSystem) {
                NSLog(@"Class %s has more than one implementation of %s:\n\t%@\n\t%@",
                      class_getName(cls), sorted[methodIndex-1].mname, a, b);
                MethodMultipleImplementationCount++;
            } else {
                SuppressedConflictCount ++;
            }
        }
    }
    
    free(sorted);
}

static void _checkSignaturesVsSuperclass(Class cls, Method *methods, unsigned int methodCount)
{
    // Any method that is implemented by a class and its superclass should have the same signature.  ObjC doesn't encode static type declarations in method signatures, so we can't check for covariance.
    Class superClass = class_getSuperclass(cls);
    if (!superClass)
        return;
    
    // Get our method list and check each one vs. the superclass
    if (methods) {
        unsigned int methodIndex = methodCount;
        while (methodIndex--) {
            Method method = methods[methodIndex];
            SEL sel = method_getName(method);
	    
            Method superMethod = class_getInstanceMethod(superClass, sel); // This could be a class method if cls is itself the metaclass, here "instance" just means "the class we passed in"
            if (!superMethod)
                continue;
            
            const char *types = method_getTypeEncoding(method);
            const char *superTypes = method_getTypeEncoding(superMethod);
            BOOL freeSignatures = NO;

#if NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
            // Cocoa is built w/o this under 10.5, it seems. If we turn it on and then do method replacement, we'll get spurious warnings about type mismatches due to the struct name embedded in the type encoding.
            types = _OBGeometryAdjustedSignature(types);
            superTypes = _OBGeometryAdjustedSignature(superTypes);
            freeSignatures = YES;
#endif
            
            if (!_methodSignaturesCompatible(sel, types, superTypes)) {
                BOOL nonSystem = NO;
                NSString *methodInfo = describeMethod(method, &nonSystem);
                NSString *superMethodInfo = describeMethod(superMethod, &nonSystem);
                if (nonSystem) {
                    const char *normalizedSig = _copyNormalizeMethodSignature(types);
                    const char *normalizedSigSuper = _copyNormalizeMethodSignature(superTypes);
                    NSLog(@"Method %s has conflicting type signatures between class and its superclass:\n\tsignature %s for class %s has %@\n\tsignature %s for class %s has %@",
                          sel_getName(sel),
                          normalizedSig, class_getName(cls), methodInfo,
                          normalizedSigSuper, class_getName(superClass), superMethodInfo);
                    free((void *)normalizedSig);
                    free((void *)normalizedSigSuper);
                    MethodSignatureConflictCount++;
                } else {
                    SuppressedConflictCount++;
                }
            }

            if (freeSignatures) {
                free((char *)types);
                free((char *)superTypes);
            }
        }
    }
}

static void _checkMethodInClassVsMethodInProtocol(Class cls, Protocol *protocol, Method m, BOOL isRequiredMethod, BOOL isInstanceMethod)
{
    SEL sel = method_getName(m);

    // Skip a couple Apple selectors that are known to be bad. Radar 6333710.
    if (sel == @selector(invokeServiceIn:msg:pb:userData:error:) ||
	sel == @selector(invokeServiceIn:msg:pb:userData:menu:remoteServices:))
	return;
    
    struct objc_method_description desc = protocol_getMethodDescription(protocol, sel, isRequiredMethod, isInstanceMethod);
    if (desc.name == NULL)
        // No such method in the protocol
        return;
    
    const char *types = method_getTypeEncoding(m);
    if (!_methodSignaturesCompatible(sel, types, desc.types)) {
        NSLog(@"Method %s has type signatures conflicting with adopted protocol\n\tnormalized %s original %s(%s)\n\tnormalized %s original %s(%s)!",
	      sel_getName(sel),
	      _copyNormalizeMethodSignature(types), types, class_getName(cls),
	      _copyNormalizeMethodSignature(desc.types), desc.types, protocol_getName(protocol));
        MethodSignatureConflictCount++;
    }
}

static void _checkMethodInClassVsMethodsInProtocol(Class cls, Protocol *protocol, BOOL isInstanceClass)
{
    unsigned int methodIndex = 0;
    Method *methods = class_copyMethodList(cls, &methodIndex);
    if (!methods)
        return;
    
    while (methodIndex--) {
        Method method = methods[methodIndex];

        // Handle the required/optional split in the protocol method organization.
        _checkMethodInClassVsMethodInProtocol(cls, protocol, method, YES/*required*/, isInstanceClass);
        _checkMethodInClassVsMethodInProtocol(cls, protocol, method, NO/*required*/, isInstanceClass);
    }
    
    free(methods);
}

static void _checkSignaturesVsProtocol(Class cls, Protocol *protocol)
{
    // Recursively check protocol conformed to by the original protocol.
    {
        unsigned int protocolIndex = 0;
        Protocol **protocols = protocol_copyProtocolList(protocol, &protocolIndex);
        if (protocols) {
            while (protocolIndex--)
                _checkSignaturesVsProtocol(cls, protocols[protocolIndex]);
            free(protocols);
        }
    }

    // Check each of our methods vs. those in the protocol.  Methods in the protocol are split up by instance vs. class and required vs. optional.  Handle the instance/class split here.
    _checkMethodInClassVsMethodsInProtocol(cls, protocol, YES/*isInstanceClass*/);
    _checkMethodInClassVsMethodsInProtocol(object_getClass(cls), protocol, NO/*isInstanceClass*/);
}

static void _checkSignaturesVsProtocols(Class cls)
{
    unsigned int protocolIndex = 0;
    Protocol **protocols = class_copyProtocolList(cls, &protocolIndex);
    if (protocols) {
        while (protocolIndex--)
            _checkSignaturesVsProtocol(cls, protocols[protocolIndex]);
        free(protocols);
    }
}

// Validate type signatures across inheritance and protocol conformance. For this to work in the most cases, delegates need to be implemented as conforming to protocols, possibly with @optional methods.  We can't check a class vs. everything it might conform to (for example -length returns signed in some protcols and unsigned int others).
+ (void)_validateMethodSignatures;
{
    // Reset this to zero to avoid double-counting errors if we get called again due to bundle loading.
    MethodSignatureConflictCount = 0;
    MethodMultipleImplementationCount = 0;
    SuppressedConflictCount = 0;
    
    int classIndex, classCount = 0, newClassCount;
    Class *classes = NULL;
    
    newClassCount = objc_getClassList(NULL, 0);
    while (classCount < newClassCount) {
        classCount = newClassCount;
        classes = realloc(classes, sizeof(Class) * classCount);
        newClassCount = objc_getClassList(classes, classCount);
    }
    
    for (classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        
        unsigned int methodIndex = 0;
        Method *methods = class_copyMethodList(cls, &methodIndex);
        _checkSignaturesVsSuperclass(cls, methods, methodIndex); // instance methods
        // _checkSignaturesWithinClass(cls, methods, methodIndex); 
        free(methods);
        
        methodIndex = 0;
        Class metaClass = object_getClass(cls);
        methods = class_copyMethodList(metaClass, &methodIndex);
        _checkSignaturesVsSuperclass(metaClass, methods, methodIndex); // ... and class methods
        // _checkSignaturesWithinClass(metaClass, methods, methodIndex); 
        free(methods);
        
        _checkSignaturesVsProtocols(cls); // checks instance and class and methods, so don't call with the metaclass
    }

    // TODO: Check that protocols done conform to other protocols and then change the signature.  Less important since most cases will actually involve a class conforming.
    
    // We should find zero conflicts!
    OBASSERT(MethodSignatureConflictCount == 0);
    OBASSERT(MethodMultipleImplementationCount == 0);
    
    if (SuppressedConflictCount)
        NSLog(@"Warning: Suppressed %u messages about problems in system frameworks", SuppressedConflictCount);
    
    free(classes);
}

/*
 When we change the methods in a datasource or delegate and there are multiple apps using that protocol (and the methods are @optional) we'd not normally get a warning.  On a case-by-case basis we've added OBASSERTs in the  -setDelegate:/-setDataSource: methods before, but that doesn't work for extra optional data source methods (like those added to NSTableView in OmniAppKit) and requires more code in general.  Instead, let the developer write something like:
 
 @protocol AnythingContainingTheWordDeprecated
 ... signatures _without_ the @optional specifier ...
 @end
 
 Here, we'll check every class and and make sure that nobody implements the dead methods (hopefully there aren't naming conflicts if the methods were well named in the first place!)
 
 */

static unsigned int DeprecatedMethodImplementationCount = 0;

static void _checkForDeprecatedMethodsInClass(Class cls, CFSetRef deprecatedSelectors, BOOL isClassMethod)
{
    // Can't iterate the set and then do class_getInstanceMethod().  This will provoke +initialize on classes, some of which may be deprecated.
    unsigned int methodIndex = 0;
    Method *methods = class_copyMethodList(cls, &methodIndex);
    if (methods == NULL)
        return;
    
    while (methodIndex--) {
        SEL sel = method_getName(methods[methodIndex]);
        if (CFSetContainsValue(deprecatedSelectors, sel)) {
            NSLog(@"%s implements the deprecated method %c%s.", class_getName(cls), isClassMethod ? '+' : '-', sel_getName(sel));
            DeprecatedMethodImplementationCount++;
        }
    }
    free(methods);
}

+ (void)_checkForMethodsInDeprecatedProtocols;
{
    // Reset this to zero to avoid double-counting errors if we get called again due to bundle loading.
    DeprecatedMethodImplementationCount = 0;
    
    // Build an index of all the deprecated instance and class methods.
    CFSetCallBacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    CFMutableSetRef deprecatedInstanceSelectors = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    CFMutableSetRef deprecatedClassSelectors = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    
    BOOL oneDeprecatedProtocolFound = NO;
    unsigned int protocolIndex = 0;
    Protocol **protocols = objc_copyProtocolList(&protocolIndex);
    if (protocols) {
        while (protocolIndex--) {
            Protocol *protocol = protocols[protocolIndex];
            if (strstr(protocol_getName(protocol), "Deprecated") == NULL)
                continue;
            
            //NSLog(@"Indexing deprecation protocol '%s'...", protocol_getName(protocol));
            oneDeprecatedProtocolFound = YES;
            
            unsigned int descIndex;
            struct objc_method_description *descs;
            
            // All the deprecated methods should in the required segment of the protocol.
            descs = protocol_copyMethodDescriptionList(protocol, NO/*isRequired*/, YES/*isInstaceMethod*/, &descIndex);
            OBASSERT(descs == NULL);
            descs = protocol_copyMethodDescriptionList(protocol, NO/*isRequired*/, NO/*isInstaceMethod*/, &descIndex);
            OBASSERT(descs == NULL);
            
            descIndex = 0;
            if ((descs = protocol_copyMethodDescriptionList(protocol, YES/*isRequired*/, YES/*isInstanceMethod*/, &descIndex))) {
                while (descIndex--)
                    CFSetAddValue(deprecatedInstanceSelectors, descs[descIndex].name);
                free(descs);
            }

            descIndex = 0;
            if ((descs = protocol_copyMethodDescriptionList(protocol, YES/*isRequired*/, NO/*isInstanceMethod*/, &descIndex))) {
                while (descIndex--)
                    CFSetAddValue(deprecatedClassSelectors, descs[descIndex].name);
                free(descs);
            }
        }
        free(protocols);
    }
    
    // Make sure the OBDEPRECATED_METHODS macro is forcing the otherwise unused protocols to be emitted
    OBASSERT(oneDeprecatedProtocolFound);

    // Check that classes don't implement any of the deprecated methods.
    int classIndex, classCount = 0, newClassCount;
    Class *classes = NULL;
    
    newClassCount = objc_getClassList(NULL, 0);
    while (classCount < newClassCount) {
        classCount = newClassCount;
        classes = realloc(classes, sizeof(Class) * classCount);
        newClassCount = objc_getClassList(classes, classCount);
    }
    
    for (classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
	
	// Several Cocoa classes have problems.  Radar 6333766.
	const char *name = class_getName(cls);
	if (strcmp(name, "ISDComplainer") == 0 ||
	    strcmp(name, "ILMediaObjectsViewController") == 0 ||
	    strcmp(name, "ABBackupManager") == 0 ||
	    strcmp(name, "ABPeopleController") == 0 ||
	    strcmp(name, "ABAddressBook") == 0 ||
            strcmp(name, "ABPhoneFormatsPreferencesModule") == 0 ||
            strcmp(name, "GFNodeManagerView") == 0 ||
            strcmp(name, "QCPatchActor") == 0)
	    continue;

        _checkForDeprecatedMethodsInClass(cls, deprecatedInstanceSelectors, NO/*isClassMethod*/);
        _checkForDeprecatedMethodsInClass(object_getClass(cls), deprecatedClassSelectors, YES/*isClassMethod*/);
    }
    
    free(classes);
    CFRelease(deprecatedInstanceSelectors);
    CFRelease(deprecatedClassSelectors);
    
    OBASSERT(DeprecatedMethodImplementationCount == 0);
}

#endif

#if defined(OB_CHECK_COPY_WITH_ZONE)
// Look through all classes and find those that respond to -copyWithZone:. If the class has object-typed ivars and does not itself implement -copyWithZone:, log a warnings.  This will generate false positives in some cases, but it is a useful check to help make sure that NSCell subclasses are doing the right thing, for example.

static BOOL _classIsKindOfClassNamed(Class cls, const char *superclassName)
{
    Class superclass = objc_getClass(superclassName);
    if (!superclass)
        return NO;
    return OBClassIsSubclassOfClass(cls, superclass);
}

static void _checkCopyWithZoneImplementationForClass(Class cls, SEL copySel)
{
    Class impCls = OBClassImplementingMethod(cls, copySel);
    if (!impCls || impCls == cls)
        // No implementation at all or the implementation is on this class -- we assume it is OK
        return;
    
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    if (!ivars)
        // No ivars in this class, so no problem
        return;
    
    // Yucky hacks. There is no great way for objects to declare that they are immutable and implement -copyWithZone: to return [self retain] (and can no longer have mutable properties).  Special case some classes in the Omni frameworks that we know do this.  Also, NSTextAttachment, which doesn't declare NSCopying, but implements it to return [self retain], even though attachmets are mutable.
    if (copySel == @selector(copyWithZone:) &&
        (_classIsKindOfClassNamed(cls, "NSTextAttachment") ||
         _classIsKindOfClassNamed(cls, "ODOProperty") ||
         _classIsKindOfClassNamed(cls, "ContentOptionDescription") ||
         _classIsKindOfClassNamed(cls, "OSStyleAttribute")))
        return;
    
    // We'll assume that if there are any object-typed ivars ('@' _anywhere_ in the signature -- might be an object-containing struct in bizarro cases) that it should be retained unless it has 'nonretained' in the name (an Omni convention).  Clearly there will be false positives, but this is just a filter to show places to check.    
    for (unsigned int ivarIndex = 0; ivarIndex < ivarCount; ivarIndex++) {
        Ivar ivar = ivars[ivarIndex];
        const char *type = ivar_getTypeEncoding(ivar);
        if (strchr(type, '@') == NULL)
            continue;
        const char *name = ivar_getName(ivar);
        if (strstr(name, "nonretained") == NULL) {
            NSLog(@"  ### Found retained object ivar %s in class %s", name, class_getName(cls));
        }
    }
    
    free(ivars);
}

+ (void)_checkCopyWithZoneImplementations;
{
    // Get the class list
    int classIndex, classCount = 0, newClassCount;
    Class *classes = NULL;
    newClassCount = objc_getClassList(NULL, 0);
    while (classCount < newClassCount) {
        classCount = newClassCount;
        classes = realloc(classes, sizeof(Class) * classCount);
        newClassCount = objc_getClassList(classes, classCount);
    }
    
    for (classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        // Some classes (that aren't our problem) don't asplode if they try to dynamically create setters when asked about 'copyWithZone:'.
        const char *clsName = class_getName(cls);
        if (strcmp(clsName, "_NSWindowAnimator") == 0 ||
            strcmp(clsName, "_NSViewAnimator") == 0)
            continue;
        
        // Also, skip class prefix ranges that are 'owned' by Apple and produce lots of (hopefully) false positives.
        if (strstr(clsName, "CI") == clsName ||
            strstr(clsName, "QF") == clsName ||
            strstr(clsName, "NS") == clsName ||
            strstr(clsName, "_NS") == clsName ||
            strstr(clsName, "AB") == clsName ||
            strstr(clsName, "WebCore") == clsName ||
            strstr(clsName, "WebElement") == clsName ||
            strstr(clsName, "IK") == clsName ||
            strstr(clsName, "QL") == clsName ||
            strstr(clsName, "HI") == clsName ||
            strstr(clsName, "CA") == clsName ||
            strstr(clsName, "DS") == clsName ||
            strstr(clsName, "__NS") == clsName ||
            strstr(clsName, "DOM") == clsName ||
            strstr(clsName, "GF") == clsName ||
            strstr(clsName, "SF") == clsName ||
            strstr(clsName, "ISD") == clsName ||
            strstr(clsName, "%NS") == clsName || // Cocoa class that got pose-as'd
            strstr(clsName, "QC") == clsName)
            continue;
        
        _checkCopyWithZoneImplementationForClass(cls, @selector(copyWithZone:));
        _checkCopyWithZoneImplementationForClass(cls, @selector(mutableCopyWithZone:));
    }
    
    free(classes);
}
#endif

@end
