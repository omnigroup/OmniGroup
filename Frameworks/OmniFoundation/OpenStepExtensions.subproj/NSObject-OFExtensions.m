// Copyright 1997-2005, 2007-2008, 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/OFNull.h>

#import <Foundation/NSOperation.h>
#import <dispatch/dispatch.h>
#import <OmniBase/macros.h>

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
    return [[self class] bundle];
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
    
    id (*imp)(id self, SEL _cmd, id target) = (typeof(imp))c->impl;
    imp(c->receiver, c->sel, target);
}

static void OFPerformWithObjectAndStore(const void *arg, void *context)
{
    id target = (id)arg;
    struct reversedApplyContext *c = context;
    
    id (*imp)(id self, SEL _cmd, id target) = (typeof(imp))c->impl;
    id result = imp(c->receiver, c->sel, target);
    
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
	if (key && ![key isNull])
	    [returnDictionary setObject:value forKey:key];
    }
    
    return returnDictionary;
}

- (void)afterDelay:(NSTimeInterval)delay performBlock:(void (^)(void))block;
{
    /*
     dispatch_get_current_queue is deprecated, or this could be a bit simpler. Instead, we do the scheduling on the main queue and then send that back to the original queue. This requires the main queue to be unblocked (which it really should be anyway). All the current callers are from the main queue, anyway. Assert this is still true so that we can make sure to test the non-main caller case if/when it happens.
     */
    OBPRECONDITION([NSThread isMainThread]);
    
    NSOperationQueue *operationQueue = [NSOperationQueue currentQueue];
    
    block = [[block copy] autorelease];
        
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                     0/* handle -- not applicable */,
                                                     0/* mask -- not applicable */,
                                                     dispatch_get_main_queue());
    
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * 1e9) /* dispatch_time() takes nanoseconds */);
    dispatch_source_set_timer(timer, startTime, 0/*interval*/, 0/*leeway*/);
    
    dispatch_source_set_event_handler(timer, ^{
        [operationQueue addOperationWithBlock:block];
        dispatch_source_cancel(timer);
#if !OB_ARC
        dispatch_release(timer);
#endif
    });

    // Fire it up.
    dispatch_resume(timer);
}

@end
