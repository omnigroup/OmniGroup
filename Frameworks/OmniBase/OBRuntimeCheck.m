// Copyright 1997-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBRuntimeCheck.h>

#import <OmniBase/OBUtilities.h>
#import <OmniBase/rcsid.h>
#import <OmniBase/macros.h>
#import <OmniBase/assertions.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
// Define the signature for these methos for -Wselector
@interface NSObject (OBPostLoaderMethods)
+ (void)didLoad;
+ (void)performPosing;
+ (void)becomingMultiThreaded;
@end
#else
#import <OmniBase/OBPostLoader.h>
#endif

#import <dlfcn.h>

RCS_ID("$Id$");

// This can produce lots of false positivies, but provides a way to start looking for some potential problem cases.
#if 0 && defined(OMNI_ASSERTIONS_ON)
#define OB_CHECK_COPY_WITH_ZONE
#endif

#ifdef OMNI_ASSERTIONS_ON

// Do this once here to make sure the hack works. This can also serve as a template for copying to make your own deperecation protocol.
OBDEPRECATED_METHOD(-deprecatedInstanceMethod);
OBDEPRECATED_METHOD(+deprecatedClassMethod);

// Avoid unknown selector warnings from -Wundeclared-selector.  The selectors we are checking are often in other frameworks.
#define FIND_SEL(x) sel_getUid(#x)

static BOOL OBReportWarningsInSystemLibraries = NO;
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
        
        // Under 32-bit, if we define NS_BUILD_32_LIKE_64, NS{U,}Integer gets set to long-based types instead of int.  But these are the same on 32-bit and we don't care so much.  Normalize long/unsigned long to int/unsigned int.
        // Radar 6982665: -[NSObject(NSObject) hash] has wrong method signature in CoreFoundation (actually, most of the NSObject subclasses do too).
#if !defined(__LP64__) || !__LP64__
        // This isn't currently avoiding this transform while in the midst of a struct/union name.
        if (c == _C_LNG)
            c = _C_INT;
        else if (c == _C_ULNG)
            c = _C_UINT;
#endif            
	
	// Default, just copy it.
	*dst = c;
	dst++;
        src++;
    } while (c);
    
    //if (strcmp(sig, copy)) NSLog(@"Normalized '%s' to '%s'", sig, copy);
    
    return copy;
}

static BOOL _signaturesMatch(const char *sig1, const char *sig2, const char *option1, const char *option2)
{
    return ((strcmp(sig1, option1) == 0) && (strcmp(sig2, option2) == 0)) || ((strcmp(sig1, option2) == 0) && (strcmp(sig2, option1) == 0));
}

static BOOL _methodSignaturesCompatible(Class cls, SEL sel, const char *sig1, const char *sig2)
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
#if __LP64__
        // Radar 6964439: -[NSProtocol hash] returns a 32-bit value in 64-bit ABI
        if (sel == @selector(hash) && cls == objc_getClass("Protocol") &&
            _signaturesMatch(sig1, sig2, "I16@0:8", "Q16@0:8"))
            return YES;
#endif
        
        // A couple cases in QuartzCore where somehow one version has the offset info and the other doesn't.
        if (_signaturesMatch(sig1, sig2, "v@:d", "v16@0:4d8"))
            return YES;
        if (_signaturesMatch(sig1, sig2, "v@:d", "v12@0:4@8"))
            return YES;
        
        // Radar 6529241: Incorrect dragging source method declarations in AppKit.
        // NSControl and NSTableView have mismatching signatures for these methods (32/64 bit issue).
        if (sel == FIND_SEL(draggingSourceOperationMaskForLocal:) &&
            _signaturesMatch(sig1, sig2, "I12@0:4c8", "L12@0:4c8"))
            return YES;
        
        if (sel == FIND_SEL(draggedImage:endedAt:operation:) &&
            _signaturesMatch(sig1, sig2, "v24@0:4@8{CGPoint=ff}12I20", "v24@0:4@8{CGPoint=ff}12L20"))
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
    
    if (i != (IMP)dli.dli_saddr)
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
        
        if (![path hasPrefix:@"/System/"] && // System or locally installed vendor framework
            ![path hasPrefix:@"/Library/"] &&
            ![path hasPrefix:@"/usr/lib/"] &&
            ([path rangeOfString:@"/Developer/Platforms/"].location == NSNotFound) && // iPhone simulator
            ![path hasSuffix:@"FBAccess"] && // Special case for FrontBase framework
            ![path hasSuffix:@"Growl"]) // Special case for Growl framework
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
        
        /* There are some methods that we expect to be multiply defined. On iOS, however, we don't expect them to be defined at all (OBPostLoader not built there) */
        if (class_isMetaClass(cls) && (sel_isEqual(msel, @selector(didLoad)) || sel_isEqual(msel, @selector(performPosing)) || sel_isEqual(msel, @selector(becomingMultiThreaded)))) {
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
            NSLog(@"Class \"%@\" defines OBPostLoader related selector %@ on iOS, but OBPostLoader is not supported on iOS.", NSStringFromClass(cls), NSStringFromSelector(msel));
#endif
            continue;
        }
        
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
            if (nonSystem || OBReportWarningsInSystemLibraries) {
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

static void _checkForCommonClassMethodNameTypos(Class metaClass, Class class, Method *methods, unsigned int methodCount)
{
    const char * const affectingPrefix = "keyPathsForValuesAffecting";

    if (methods) {
        for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex ++) {
            SEL sel = method_getName(methods[methodIndex]);
            const char *selName = sel_getName(sel);
            size_t selNameLength = strlen(selName);

            // Someone was asleep at the wheel and we have +automaticallyNotifiesObserversForKey: but +automaticallyNotifiesObserversOf<Key> (note "For" -> "Of").
            if (sel != @selector(automaticallyNotifiesObserversForKey:)) {
                const char * const badPrefix = "automaticallyNotifiesObserversFor";
                if (strncmp(selName, badPrefix, strlen(badPrefix)) == 0) {
                    NSLog(@"Class %s implements +%s, but this is likely a typo where \"For\" should be replaced by \"Of\".", class_getName(metaClass), selName);
                    OBAssertFailed(); // stop in the debugger if we have a breakpoint
                }
            }
            
            if (selNameLength > strlen(affectingPrefix) &&
                strncmp(selName, affectingPrefix, strlen(affectingPrefix)) == 0 &&
                method_getNumberOfArguments(methods[methodIndex]) == 2 /* arg count includes self and _cmd */) {
                    
                // Verify that we only have keyPathsForValuesAffectingFoo if we also have Foo.
                char *namebuf = malloc(selNameLength + 5);
                strcpy(namebuf, selName + strlen(affectingPrefix));
                namebuf[0] = tolower(namebuf[0]);
                
                /* This test can produce false positives on valid code. We can extend it as we run into the exceptions.
                   Some things it doesn't know about:
                     direct ivar access
                     indexed accessors
                     valueForUndefinedKey:
                */
                
                objc_property_t propInfo = class_getProperty(metaClass, namebuf);
                if (propInfo != NULL) {
                    /* good, there's a property */
                    /* the docs don't say whether you need to actually use the @property syntax for this function to work --- for most of our KVObservables, class_getProperty() returns nil */
                    // NSLog(@"property(%s) -> \"%s\"", namebuf, property_getAttributes(propInfo));
                } else {
                    SEL seln;
                    
                    /* Look for -foo */
                    if (!((seln = sel_getUid(namebuf)) && class_respondsToSelector(class, seln))) {
                        
                        /* OK, look for -_foo */
                        memmove(namebuf+1, namebuf, strlen(namebuf)+1);
                        namebuf[0] = '_';
                        if (!((seln = sel_getUid(namebuf)) && class_getInstanceMethod(class, seln))) {
                            
                            /* Maybe it's a boolean -isFoo ? */
                            memcpy(namebuf, "is", 2);
                            strcpy(namebuf+2, selName + strlen(affectingPrefix));
                            if (!((seln = sel_getUid(namebuf)) && class_getInstanceMethod(class, seln))) {
                                
                                /* Well, how about -getFoo ? */
                                memcpy(namebuf, "get", 3);
                                strcpy(namebuf+3, selName + strlen(affectingPrefix));
                                if (!((seln = sel_getUid(namebuf)) && class_getInstanceMethod(class, seln))) {
                                    
                                    seln = NULL;
                                    /* No luck */
                                    namebuf[3] = tolower(namebuf[3]);
                                    NSLog(@"Class %s implements +%s, but instances do not respond to -%s, -_%s, -is%s, or -get%s", class_getName(metaClass), selName, namebuf+3, namebuf+3, selName + strlen(affectingPrefix), selName + strlen(affectingPrefix));
                                    OBAssertFailed(); // stop in the debugger if we have a breakpoint
                                }
                            }
                        }
                    }
                    
                    // NSLog(@" No @property %s, but found -%@", namebuf, NSStringFromSelector(seln));
                    (void)seln;
                }
                
                free(namebuf);
            }
        }
    }
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
            
            if (!_methodSignaturesCompatible(cls, sel, types, superTypes)) {
                BOOL nonSystem = NO;
                NSString *methodInfo = describeMethod(method, &nonSystem);
                NSString *superMethodInfo = describeMethod(superMethod, &nonSystem);
                if (nonSystem || OBReportWarningsInSystemLibraries) {
                    char *normalizedSig = _copyNormalizeMethodSignature(types);
                    char *normalizedSigSuper = _copyNormalizeMethodSignature(superTypes);
                    NSLog(@"Method %s has conflicting type signatures between class and its superclass:\n\tsignature %s for class %s has %@\n\tsignature %s for class %s has %@",
                          sel_getName(sel),
                          normalizedSig, class_getName(cls), methodInfo,
                          normalizedSigSuper, class_getName(superClass), superMethodInfo);
                    free(normalizedSig);
                    free(normalizedSigSuper);
                    MethodSignatureConflictCount++;
                } else {
                    SuppressedConflictCount++;
                }
            }
            
            if (freeSignatures) {
                free((void *)types);
                free((void *)superTypes);
            }
        }
    }
}

static void _checkMethodInClassVsMethodInProtocol(Class cls, Protocol *protocol, Method m, BOOL isRequiredMethod, BOOL isInstanceMethod)
{
    SEL sel = method_getName(m);
    
    // Skip a couple Apple selectors that are known to be bad. Radar 6333710.
    if (sel == FIND_SEL(invokeServiceIn:msg:pb:userData:error:) ||
	sel == FIND_SEL(invokeServiceIn:msg:pb:userData:menu:remoteServices:))
	return;
    
    // 7251769 -numberOfRowsInTableView: returning int instead of NSInteger
    if (strcmp(class_getName(cls), "SCTSearchManager") == 0 &&
        sel == FIND_SEL(numberOfRowsInTableView:))
        return;
    
    struct objc_method_description desc = protocol_getMethodDescription(protocol, sel, isRequiredMethod, isInstanceMethod);
    if (desc.name == NULL)
        // No such method in the protocol
        return;
    
    const char *types = method_getTypeEncoding(m);
    if (!_methodSignaturesCompatible(cls, sel, types, desc.types)) {
        BOOL nonSystem = NO;
        NSString *methodInfo = describeMethod(m, &nonSystem);
        
        if (nonSystem || OBReportWarningsInSystemLibraries) {
            char *normalizedSig = _copyNormalizeMethodSignature(types);
            char *normalizedSigProtocol = _copyNormalizeMethodSignature(desc.types);
            
            NSLog(@"Method %s has conflicting type signatures between class and its adopted protocol:\n\tsignature %s for class %s has %@\n\tsignature %s for protocol %s",
                  sel_getName(sel),
                  normalizedSig, class_getName(cls), methodInfo,
                  normalizedSigProtocol, protocol_getName(protocol));
            
            free(normalizedSig);
            free(normalizedSigProtocol);
        
            MethodSignatureConflictCount++;
        } else {
            SuppressedConflictCount++;
        }
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
        Protocol * const *protocols = protocol_copyProtocolList(protocol, &protocolIndex);
        if (protocols) {
            while (protocolIndex--)
                _checkSignaturesVsProtocol(cls, protocols[protocolIndex]);
            free((void *)protocols);
        }
    }
    
    // Check each of our methods vs. those in the protocol.  Methods in the protocol are split up by instance vs. class and required vs. optional.  Handle the instance/class split here.
    _checkMethodInClassVsMethodsInProtocol(cls, protocol, YES/*isInstanceClass*/);
    _checkMethodInClassVsMethodsInProtocol(object_getClass(cls), protocol, NO/*isInstanceClass*/);
}

static void _checkSignaturesVsProtocols(Class cls)
{
    unsigned int protocolIndex = 0;
    Protocol * const *protocols = class_copyProtocolList(cls, &protocolIndex);
    if (protocols) {
        while (protocolIndex--)
            _checkSignaturesVsProtocol(cls, protocols[protocolIndex]);
        free((void *)protocols);
    }
}

// Validate type signatures across inheritance and protocol conformance. For this to work in the most cases, delegates need to be implemented as conforming to protocols, possibly with @optional methods.  We can't check a class vs. everything it might conform to (for example -length returns signed in some protcols and unsigned int others).
static void _validateMethodSignatures(void)
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
        classes = (Class *)realloc(classes, sizeof(Class) * classCount);
        newClassCount = objc_getClassList(classes, classCount);
    }
    
    for (classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        
#define CLASSNAME_HAS_PREFIX(className, prefix) (strncmp(className, prefix, strlen(prefix)) == 0)

        /* Some classes (that aren't our problem) asplode when they try to dynamically create getters/setters. */
        const char *clsName = class_getName(cls);
        if (CLASSNAME_HAS_PREFIX(clsName, "NS") ||
            CLASSNAME_HAS_PREFIX(clsName, "_NS") ||
            CLASSNAME_HAS_PREFIX(clsName, "__NS") ||
            CLASSNAME_HAS_PREFIX(clsName, "__CF") ||
            CLASSNAME_HAS_PREFIX(clsName, "CA") ||
            CLASSNAME_HAS_PREFIX(clsName, "_CN") ||
            CLASSNAME_HAS_PREFIX(clsName, "VGL") ||
            strcmp(clsName, "DRDevice") == 0) {
            /* In particular, _NS[View]Animator chokes in this case. But we don't really need to check any _NS classes. */
            continue;
        }

#undef CLASSNAME_HAS_PREFIX

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
        _checkForCommonClassMethodNameTypos(metaClass, cls, methods, methodIndex);
        free(methods);
        
        _checkSignaturesVsProtocols(cls); // checks instance and class and methods, so don't call with the metaclass
    }
    
    // TODO: Check that protocols done conform to other protocols and then change the signature.  Less important since most cases will actually involve a class conforming.
    
    // We should find zero conflicts!
    OBASSERT(MethodSignatureConflictCount == 0);
    OBASSERT(MethodMultipleImplementationCount == 0);
    
    if (SuppressedConflictCount && getenv("OB_SUPPRESS_SUPPRESSED_CONFLICT_COUNT") == NULL)
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

static CFMutableSetRef DeprecatedInstanceSelectors = NULL;
static CFMutableSetRef DeprecatedClassSelectors = NULL;

// name should be either "+foo:bar:" or "-foo:bar:".
void OBRuntimeCheckRegisterDeprecatedMethodWithName(const char *name)
{
    OBPRECONDITION(name[0] == '+' || name[0] == '-');
    
    if (!DeprecatedInstanceSelectors) {
        CFSetCallBacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        DeprecatedInstanceSelectors = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
        DeprecatedClassSelectors = CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    }
    
    BOOL isClassMethod = (name[0] == '+');
    SEL sel = sel_getUid(&name[1]);
    OBASSERT(sel);
    
    if (isClassMethod)
        CFSetAddValue(DeprecatedClassSelectors, sel);
    else
        CFSetAddValue(DeprecatedInstanceSelectors, sel);
}
    
static void _checkForMethodsInDeprecatedProtocols(void)
{
    // Reset this to zero to avoid double-counting errors if we get called again due to bundle loading.
    DeprecatedMethodImplementationCount = 0;
    
    // Check that the macro actually worked and that (at least some of) the __attribute__((constructor)) invocations have run.
    OBASSERT(DeprecatedClassSelectors && CFSetGetCount(DeprecatedClassSelectors) > 0);
    OBASSERT(DeprecatedInstanceSelectors && CFSetGetCount(DeprecatedInstanceSelectors) > 0);
        
    // Check that classes don't implement any of the deprecated methods.
    int classIndex, classCount = 0, newClassCount;
    Class *classes = NULL;
    
    newClassCount = objc_getClassList(NULL, 0);
    while (classCount < newClassCount) {
        classCount = newClassCount;
        classes = (Class *)realloc(classes, sizeof(Class) * classCount);
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
        
        _checkForDeprecatedMethodsInClass(cls, DeprecatedInstanceSelectors, NO/*isClassMethod*/);
        _checkForDeprecatedMethodsInClass(object_getClass(cls), DeprecatedClassSelectors, YES/*isClassMethod*/);
    }
    
    free(classes);
    
    OBASSERT(DeprecatedMethodImplementationCount == 0);
}

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

static void _checkCopyWithZoneImplementations(void)
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
#endif // defined(OB_CHECK_COPY_WITH_ZONE)

void OBPerformRuntimeChecks(void)
{
    NSString *executableName = [[[NSBundle mainBundle] executablePath] lastPathComponent];
    BOOL shouldCheck = ![@"ibtool" isEqualToString:executableName] && ![@"Interface Builder" isEqualToString:executableName] && ![@"IBCocoaSimulator" isEqualToString:executableName];
    if (shouldCheck) {
        _validateMethodSignatures();
        _checkForMethodsInDeprecatedProtocols();
#ifdef OB_CHECK_COPY_WITH_ZONE
        _checkCopyWithZoneImplementations();
#endif
    }
}

static void OBPerformRuntimeChecksOnLoad(void) __attribute__((constructor));
static void OBPerformRuntimeChecksOnLoad(void)
{
    OBReportWarningsInSystemLibraries = (getenv("OBReportWarningsInSystemLibraries") != NULL);
    
    if (getenv("OBPerformRuntimeChecksOnLoad")) {
        @autoreleasepool {
            OBPerformRuntimeChecks();
        }
    }
}

#endif

