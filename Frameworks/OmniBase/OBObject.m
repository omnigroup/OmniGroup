// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/OBObject.h>

#import <OmniBase/OBLoadAction.h>

#import <OmniBase/rcsid.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/objc.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation OBObject
/*" OBObject is an immediate subclass of NSObject, and adds common functionality which Omni has found to be valuable in its own development. OBObject is a superclass for virtually all (if not all) of the classes in Omni's Frameworks (such as OmniFoundation, OmniAppkit, and the publically available OmniNetworking frameworks) as well as in Omni's commercial applications (including OmniWeb and OmniPDF). Also, the class header file includes a couple of other header files which are used in many to virtually all of our classes, and recommended for your use as well. This way you need not include these utility headers everywhere.

OBObject is essentially an abstract class; you are encouraged to subclass most or all of your classes from it, but it is highly unlikely that you would instantiate an OBObject itself.

The features afforded by this class are essentially debugging features. This class can help specifically with debugging allocation, deallocation, and class initialization errors, as well as provide a base for more useful readily examinable instance information via enhancements to the description methods.

"*/

#ifdef DEBUG_INITIALIZE
static NSMutableDictionary *initializedClasses;
#endif
#ifdef DEBUG_ALLOC
static BOOL OBObjectDebug = NO;
#endif

+ (void)initialize;
{
    static BOOL initialized = NO;

    [super initialize];

    if (!initialized) {
        initialized = YES;


#ifdef DEBUG_INITIALIZE
#warning OBObject initialize debugging enabled
	NSLog(@"+[OBObject initialize] debugging enabled--"
		@"should deactivate this in production code");
	initializedClasses = [[NSMutableDictionary alloc] initWithCapacity:512];
#endif


        OBInvokeRegisteredLoadActions();
    }

#ifdef DEBUG_INITIALIZE
    [initializedClasses setObject:self forKey:NSStringFromClass(self)];
#endif
}

/*" This method is overriden from the superclass implementation in order to provide some class allocation, deallocation and initialization debugging support, since these are areas of fairly common errors.

If DEBUG_INITIALIZE is defined, then this method will complain if +initialize didn't call [super +initialize]. Apple's documentation for [NSObject +initialization] implies that subclass implementations of +initialize should not call the superclass implementation. Observation, however, shows that the runtime does in fact call +initialize on classes which don't implement +initialize. Therefore, superclass implementations of +initialize are invoked multiple times anyway, and we recommend that you continue this behavior when you implement +initialize for your custom classes. To put it succinctly, despite Apple's documentation, the first thing your custom +initialize should do is call [super +initialize]. Defining DEBUG_INITIALIZE provides you with a warning if you fail to do so.

If DEBUG_ALLOC is defined, then this method can log a message whenever +allocWithZone is invoked, providing you with some feedback whenever an object is allocated. Before logging this message, this method checks the OBObjectDebug flag, which defaults to NO, to make sure that it should in fact log each allocation (since otherwise you would drown in a flood of allocation logs), so you must manually set this flag to YES (typically while you are debugging in gdb) when you are interested in this information.

If neither DEBUG_INITIALIZE nor DEBUG_ALLOC are defined, then this method is not compiled at all, thus avoiding any performance penalty.

See also: + allocWithZone (NSObject)
"*/
#if defined(DEBUG_INITIALIZE) || defined(DEBUG_ALLOC)
+ allocWithZone:(NSZone *)zone;
{
#ifdef DEBUG_INITIALIZE
    if (![initializedClasses objectForKey:NSStringFromClass(self)]) {
	NSLog(@"+[%@ initialize] didn't call [super initialize]", self);
	[initializedClasses setObject:self forKey:NSStringFromClass(self)];
    }
#endif
#ifdef DEBUG_ALLOC
#warning OBObject alloc/dealloc debugging enabled
    if (OBObjectDebug) {
	OBObject *newObject;

        newObject = [super allocWithZone:zone];
        NSLog(@"alloc: %@", NSStringFromClass(self));
        
	return newObject;
    }
#endif
    return [super allocWithZone:zone];
}
#endif

/*" This method is overriden from the superclass implementation in order to provide some class allocation and deallocation debugging support, since these are areas of fairly common errors.

If DEBUG_ALLOC is defined, then this method can log a message whenever -dealloc is invoked. Before logging this message, this method checks the OBObjectDebug flag, which defaults to NO, to make sure that it should in fact log each allocation (since otherwise you would drown in a flood of deallocation logs), so you must manually set this flag to YES (typically while you are debugging in gdb) when you are interested in this information.

This method calls NSDeallocateObject(self) rather than calling the superclass implementation of -dealloc, to avoid the performance overhead of an extra method invocation (especially important if DEBUG_ALLOC is not defined). If Apple ever for some reason extend the implementation of [NSObject -dealloc] to do anything more than call NSDeallocateObject(self), this implementation will need to change to call the superclass implementation (or duplicate it's additional functionality).

If DEBUG_ALLOC is not defined, then this method is not compiled at all, thus avoiding any performance penalty.

See also: - dealloc (NSObject)
"*/

#ifdef DEBUG_ALLOC
- (void)dealloc;
{
    if (OBObjectDebug)
	NSLog(@"dealloc: %@", OBShortObjectDescription(self));
    NSDeallocateObject(self);
}
#endif

@end

@implementation NSObject (OBDebuggingExtensions)

/*"
 Returns a mutable dictionary describing the contents of the object. Subclasses should override this method, call the superclass implementation, and then add their contents to the returned dictionary. This is used for debugging purposes. It is highly recommended that you subclass this method in order to add information about your custom subclass (if appropriate), as this has no performance or memory requirement issues (it is never called unless you specifically call it, presumably from withing a gdb debugging session).
 
 See also: - shortDescription (NSObject)
 "*/
- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[self shortDescription] forKey:@"__self__"];
    return dict;
}

/*"
 Returns -description but can be customized to return some small amount of extra information about the instance itself (though not its contents).

 See also: - description (NSObject)
 "*/
- (NSString *)shortDescription;
{
    return [self description];
}

#ifdef DEBUG
- (NSString *)ivars;
{
    NSMutableString *result = [NSMutableString string];
    
    Class cls = [self class];
    while (cls) {
        
        [result appendFormat:@"%@:\n", NSStringFromClass(cls)];
        
        unsigned ivarCount;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        if (ivars) {
            for (unsigned ivarIndex = 0; ivarIndex < ivarCount; ivarIndex++) {
                Ivar ivar = ivars[ivarIndex];
                ptrdiff_t ivarOffset = ivar_getOffset(ivar);
                const void *ivarAddress = (OB_BRIDGE void *)self + ivarOffset;
                [result appendFormat:@"\t%s %s at offset %"PRI_ptrdiff" (%p)\n", ivar_getName(ivar), ivar_getTypeEncoding(ivar), ivarOffset, ivarAddress];
            }
            free(ivars);
        }
        
        cls = class_getSuperclass(cls);
    }
    
    return result;
}

- (NSString *)methods;
{
    return [object_getClass(self) instanceMethods];
}

static NSString *methodsWithPrefix(Class cls, char prefix)
{
    NSMutableString *result = [NSMutableString string];
    
    while (cls) {
        [result appendFormat:@"%@:\n", NSStringFromClass(cls)];
        
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (methods) {
            for (unsigned int methodIndex = 0; methodIndex < methodCount; methodIndex++) {
                Method m = methods[methodIndex];
                [result appendFormat:@"\t%c%s %s\n", prefix, sel_getName(method_getName(m)), method_getTypeEncoding(m)];
            }
            free(methods);
        }
        
        cls = class_getSuperclass(cls);
    }
    
    return result;
}

+ (NSString *)instanceMethods;
{
    return methodsWithPrefix(self, '-');
}
+ (NSString *)classMethods;
{
    return methodsWithPrefix(object_getClass(self), '+');
}

- (void)expectDeallocationSoon;
{
    
}

+ (NSString *)protocols;
{
    NSMutableString *result = [NSMutableString string];

    Class cls = self;
    while (cls) {
        [result appendFormat:@"%@:\n", NSStringFromClass(cls)];
        
        unsigned int protocolCount = 0;
        Protocol * __unsafe_unretained * protocols = class_copyProtocolList(cls, &protocolCount);
        if (protocols) {
            for (unsigned int protocolIndex = 0; protocolIndex < protocolCount; protocolIndex++) {
                __unsafe_unretained Protocol *p = protocols[protocolIndex];
                [result appendFormat:@"\t%s\n", protocol_getName(p)];
            }
            free(protocols);
        }

        cls = class_getSuperclass(cls);
    }
    
    return result;
}

static Class *_OBCopyClassList(int *outClassCount)
{
    __unsafe_unretained Class *classes = NULL;
    int classCount = 0;
    int returnedClassCount;

    while (YES) {
        returnedClassCount = objc_getClassList(classes, classCount);
        if (returnedClassCount == classCount)
            break;
        classCount = returnedClassCount;
        classes = (__unsafe_unretained Class *)reallocf(classes, sizeof(*classes) * classCount);
    }

    *outClassCount = classCount;
    return classes;
}

// Returns all the direct and indirect subclasses of the receiver.
+ (NSArray *)subclasses;
{
    int classCount = 0;
    __unsafe_unretained Class *classes = _OBCopyClassList(&classCount);

    NSMutableArray *results = [NSMutableArray array];
    
    for (int classIndex = 0; classIndex < classCount; classIndex++) {
        // Can't assume the classes are subclasses of NSObject, so calling NSObject methods won't work.
        Class cls = classes[classIndex];
        if (cls == self)
            continue;
        
        Class ancestor = cls;
        while (ancestor) {
            if (ancestor == self) {
                [results addObject:cls];
                break;
            }
            ancestor = class_getSuperclass(ancestor);
        }
    }
    
    if (classes)
        free(classes);
    
    return results;
}

static void _appendSubclassesTree(NSMutableString *result, NSUInteger depth, Class cls, NSDictionary<NSValue *, NSArray *> *classToSubclasses)
{
    for (NSUInteger indent = 0; indent < depth; indent++) {
        [result appendString:@"  "];
    }
    [result appendString:NSStringFromClass(cls)];
    [result appendString:@"\n"];

    NSArray *subclasses = [classToSubclasses[[NSValue valueWithPointer:(__bridge const void *)cls]] sortedArrayUsingComparator:^NSComparisonResult(Class cls1, Class cls2) {
        return strcmp(class_getName(cls1), class_getName(cls2));
    }];
    for (Class subCls in subclasses) {
        _appendSubclassesTree(result, depth + 1, subCls, classToSubclasses);
    }
}

+ (NSString *)subclassesTree;
{
    int classCount = 0;
    __unsafe_unretained Class *classes = _OBCopyClassList(&classCount);

    NSMutableDictionary <NSValue *, NSMutableArray *> *classToSubclasses = [NSMutableDictionary dictionary];

    for (int classIndex = 0; classIndex < classCount; classIndex++) {
        Class cls = classes[classIndex];
        Class superCls = class_getSuperclass(cls);

        if (superCls == nil) {
            continue;
        }

        NSMutableArray *subclasses = classToSubclasses[[NSValue valueWithPointer:(__bridge const void *)superCls]];
        if (subclasses == nil) {
            subclasses = [NSMutableArray array];
            classToSubclasses[[NSValue valueWithPointer:(__bridge const void *)superCls]] = subclasses;
        }

        [subclasses addObject:cls];
    }

    NSMutableString *result = [NSMutableString string];
    _appendSubclassesTree(result, 0, self, classToSubclasses);

    if (classes)
        free(classes);

    return result;
}

#endif

@end

// These are defined on other NSObject subclasses; extend OBObject to have them using our -debugDictionary and -shortDescription
@implementation OBObject (OBDebugging)

static const unsigned int MaxDebugDepth = 3;

/*"
Normally, calls [self debugDictionary], asks that dictionary to perform descriptionWithLocale:indent:, and returns the result. To minimize the chance of the resulting description being extremely large (and therefore more confusing than useful), if level is greater than 2 this method simply returns [self shortDescription].

See also: - debugDictionary
"*/
- (NSString *)descriptionWithLocale:(nullable NSDictionary *)locale indent:(NSUInteger)level
{
    if (level < MaxDebugDepth)
        return [[self debugDictionary] descriptionWithLocale:locale indent:level];
    return [self shortDescription];
}

/*" Returns [self descriptionWithLocale:nil indent:0]. This often provides more meaningful information than the default implementation of description, and is (normally) automatically used by the debugger, gdb, when asked to print an object.

 See also: - description (NSObject), - shortDescription
"*/
- (NSString *)description;
{
    return [self descriptionWithLocale:nil indent:0];
}

/*"
 Returns [super description].  Without this, the NSObject -shortDescription would call our -description which could eventually recurse to -shortDescription.
 
 See also: - description (NSObject)
 "*/
- (NSString *)shortDescription;
{
    return [super description];
}

@end

CFStringRef OBNSObjectCopyShortDescription(const void *value)
{
    return CFBridgingRetain([(OB_BRIDGE id)value shortDescription]);
}

NS_ASSUME_NONNULL_END
