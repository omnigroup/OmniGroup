// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSObject-OFExtensions.h>

RCS_ID("$Id$")

@implementation NSObject (OFExtensions)

static BOOL implementsInstanceMethod(Class cls, SEL aSelector)
{
    // In ObjC 2.0, it isn't documented whether class_getInstanceMethod/class_getClassMethod search the superclass or not.  Radar #5063446.
    // class_copyMethodList is documented to NOT look at the superclass, so we'll use that, even though it requires memory allocation/deallocation.
    
    unsigned int methodIndex;
    Method *methods = class_copyMethodList(cls, &methodIndex);
    if (!methods)
        return NO;
    
    BOOL result = NO;
    while (methodIndex--) {
        Method m = methods[methodIndex];
        if (sel_isEqual(method_getName(m), aSelector)) {
            result = YES;
            break;
        }
    }
    
    free(methods);
    return result;
}

+ (Class)classImplementingSelector:(SEL)aSelector;
{
    Class aClass = self;

    while (aClass) {
        if (implementsInstanceMethod(aClass, aSelector))
            return aClass;
        aClass = class_getSuperclass(aClass);
    }

    return Nil;
}

+ (NSBundle *)bundle;
{
    return [NSBundle bundleForClass:self];
}

- (NSBundle *)bundle;
{
    return [isa bundle];
}

struct reversedApplyContext {
    NSObject *receiver;
    SEL sel;
    IMP impl;
    NSMutableArray *storage;
};

static void OFPerformWithObject(const void *arg, void *context)
{
    id target = (id)arg;
    struct reversedApplyContext *c = context;
    
    (c->impl)(c->receiver, c->sel, target);
}

static void OFPerformWithObjectAndStore(const void *arg, void *context)
{
    id target = (id)arg;
    struct reversedApplyContext *c = context;
    
    id result = (c->impl)(c->receiver, c->sel, target);
    
    [c->storage addObject:result];
}

static struct reversedApplyContext OFMakeApplyContext(NSObject *rcvr, SEL sel)
{
    Class receiverClass = object_getClass(rcvr);
    
    IMP impl = class_getMethodImplementation(receiverClass, sel);
    
    return (struct reversedApplyContext){ .receiver = rcvr, .sel = sel, .impl = impl, .storage = nil };
}

- (void)performSelector:(SEL)sel withEachObjectInArray:(NSArray *)array
{
    if (!array)
        return;
    CFIndex count = CFArrayGetCount((CFArrayRef)array);
    if (count == 0)
        return;
    struct reversedApplyContext ctxt = OFMakeApplyContext(self, sel);
    CFArrayApplyFunction((CFArrayRef)array, CFRangeMake(0, count), OFPerformWithObject, &ctxt);
}

- (NSArray *)arrayByPerformingSelector:(SEL)sel withEachObjectInArray:(NSArray *)array;
{
    if (!array)
        return nil;
    CFIndex count = CFArrayGetCount((CFArrayRef)array);
    if (count == 0)
        return [NSArray array];
    struct reversedApplyContext ctxt = OFMakeApplyContext(self, sel);
    ctxt.storage = [[NSMutableArray alloc] initWithCapacity:count];
    [ctxt.storage autorelease]; // In case one of the perform: calls raises an exception
    CFArrayApplyFunction((CFArrayRef)array, CFRangeMake(0, count), OFPerformWithObjectAndStore, &ctxt);
    return ctxt.storage;
}

- (void)performSelector:(SEL)sel withEachObjectInSet:(NSSet *)set
{
    if (!set)
        return;
    struct reversedApplyContext ctxt = OFMakeApplyContext(self, sel);
    CFSetApplyFunction((CFSetRef)set, OFPerformWithObject, &ctxt);
}

typedef char   (*byteImp_t)(id self, SEL _cmd, id arg);
typedef short  (*shortImp_t)(id self, SEL _cmd, id arg);
typedef int    (*intImp_t)(id self, SEL _cmd, id arg);
typedef long   (*longImp_t)(id self, SEL _cmd, id arg);
typedef void  *(*ptrImp_t)(id self, SEL _cmd, id arg);
typedef float  (*fltImp_t)(id self, SEL _cmd, id arg);
typedef double (*dblImp_t)(id self, SEL _cmd, id arg);

- (BOOL)satisfiesCondition:(SEL)sel withObject:(id)object;
{
    NSMethodSignature *signature = [self methodSignatureForSelector:sel];
    Method method = class_getInstanceMethod([self class], sel);
    
    BOOL selectorResult;
    switch ([signature methodReturnType][0]) {
        case _C_CHR:
        case _C_UCHR:
        case _C_BOOL:
        {
            byteImp_t byteImp = (typeof(byteImp))method_getImplementation(method);
            selectorResult = byteImp(self, sel, object) != 0;
            break;
        }
        case _C_SHT:
        case _C_USHT:
        {
            shortImp_t shortImp = (typeof(shortImp))method_getImplementation(method);
            selectorResult = shortImp(self, sel, object) != 0;
            break;
        }
        case _C_ID:
        case _C_PTR:
        case _C_CHARPTR:
        {
            ptrImp_t ptrImp = (typeof(ptrImp))method_getImplementation(method);
            selectorResult = ptrImp(self, sel, object) != 0;
            break;
        }
        case _C_INT:
        case _C_UINT:
        {
            intImp_t intImp = (typeof(intImp))method_getImplementation(method);
            selectorResult = intImp(self, sel, object) != 0;
            break;
        }
        case _C_LNG:
        case _C_ULNG:
        {
            longImp_t longImp = (typeof(longImp))method_getImplementation(method);
            selectorResult = longImp(self, sel, object) != 0;
            break;
        }
        case _C_FLT:
        {
            fltImp_t floatImp = (typeof(floatImp))method_getImplementation(method);
            selectorResult = floatImp(self, sel, object) != 0;
            break;
        }
        case _C_DBL:
        {
            dblImp_t doubleImp = (typeof(doubleImp))method_getImplementation(method);
            selectorResult = doubleImp(self, sel, object) != 0;
            break;
        }
        default:
            selectorResult = NO;
            OBASSERT(false);
            ;
    }
    
    return selectorResult;
}

- (NSMutableDictionary *)dictionaryWithNonNilValuesForKeys:(NSArray *)keys;
{
    NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionary];
    for (id key in keys) {
	id value = [self valueForKey:key];
	if (key && key != [NSNull null])
	    [returnDictionary setObject:value forKey:key];
    }
    
    return returnDictionary;
}

@end
