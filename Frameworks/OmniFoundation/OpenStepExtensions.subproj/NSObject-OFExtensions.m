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

@end

void OFAfterDelayPerformBlock(NSTimeInterval delay, void (^block)(void))
{
    /*
     dispatch_get_current_queue is deprecated, or this could be a bit simpler. Instead, we schedule a block on the main dispatch queue that will then send the original block back to the original operation queue. This requires the main queue to be unblocked (which it really should be anyway). All the current callers are from the main queue, anyway. Assert this is still true so that we can make sure to test the non-main caller case if/when it happens.
     */
    OBPRECONDITION([NSThread isMainThread]);
    
    NSOperationQueue *operationQueue = [NSOperationQueue currentQueue];
    
    block = [block copy];
    
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * 1e9) /* dispatch_time() takes nanoseconds */);
    
    dispatch_after(startTime, dispatch_get_main_queue(), ^{
        [operationQueue addOperationWithBlock:block];
    });
    [block release];
}

void OFPerformInBackground(void (^block)(void))
{
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        block();
        [queue release];
    }];
}

#import <Foundation/NSThread.h>
#import <dispatch/queue.h>

void OFMainThreadPerformBlock(void (^block)(void)) {
    if ([NSThread isMainThread])
        block();
    else
        dispatch_async(dispatch_get_main_queue(), block);
}
