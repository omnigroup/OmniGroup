// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/OFNull.h>

#import <Foundation/NSOperation.h>
#import <Foundation/NSThread.h>
#import <dispatch/dispatch.h>
#import <OmniBase/macros.h>

RCS_ID("$Id$")

NS_ASSUME_NONNULL_BEGIN

@implementation NSObject (OFExtensions)

static BOOL implementsInstanceMethod(Class cls, SEL aSelector)
{
    // In ObjC 2.0, it isn't documented whether class_getInstanceMethod/class_getClassMethod search the superclass or not.  Radar #5063446.
    // NB:  class_getInstanceMethod() and class_getClassMethod() are now (OSX 10.10 / iOS 8.0) documented to search superclasses.
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

+ (nullable Class)classImplementingSelector:(SEL)aSelector;
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

- (BOOL)satisfiesCondition:(SEL)sel withObject:(nullable id)object;
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

    OBRecordBacktrace("Delayed block queued", OBBacktraceBuffer_Generic);
    
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
    block = [block copy];
    OBRecordBacktraceWithContext("Background block queued", OBBacktraceBuffer_Generic, block);

    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [queue addOperationWithBlock:^{
        OBRecordBacktraceWithContext("Background block invoke", OBBacktraceBuffer_Generic, block);
        block();
        [block release];
        [queue release];
    }];
}

void OFMainThreadPerformBlock(void (^block)(void))
{
    if ([NSThread isMainThread])
        block();
    else {
        block = [block copy];
        OBRecordBacktraceWithContext("Main thread block enqueued", OBBacktraceBuffer_Generic, block);
        dispatch_async(dispatch_get_main_queue(), ^{
            OBRecordBacktraceWithContext("Main thread block invoked", OBBacktraceBuffer_Generic, block);
            block();
        });
        [block release];
    }
}

void OFMainThreadPerformBlockSynchronously(void (^block)(void))
{
    if ([NSThread isMainThread]) {
        block();
    } else {
        block = [block copy];
        OBRecordBacktraceWithContext("Main thread block enqueued", OBBacktraceBuffer_Generic, block);
        dispatch_sync(dispatch_get_main_queue(), ^{
            OBRecordBacktraceWithContext("Main thread block invoked", OBBacktraceBuffer_Generic, block);
            block();
        });
        [block release];
    }
}

// Inspired by <https://github.com/n-b/CTT2>, but redone to use a timer to avoid spinning the runloop as fast as possible when polling.

BOOL OFRunLoopRunUntil(NSTimeInterval timeout, OFRunLoopRunType runType, OFRunLoopRunPredicate NS_NOESCAPE _Nullable predicate)
{
    __block BOOL done = NO;
    
    // Early out if this is already true
    if (predicate()) {
        return YES;
    }
    
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    
    // If we are polling, do so by installing an event source that will kick the runloop on a preferred polling interval (rather than running the predicate over and over as fast as possible).
    CFRunLoopTimerRef timer = NULL;
    if (runType == OFRunLoopRunTypePolling) {
        timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, 0/*first fire date*/, 0.05/*interval*/, 0/*flags*/, 0/*order*/, ^(CFRunLoopTimerRef t){}/*block*/); // NULL block crashes.
        CFRunLoopAddTimer(runLoop, timer, kCFRunLoopDefaultMode);
    }
    
    void (^beforeWaiting)(CFRunLoopObserverRef observer, CFRunLoopActivity activity) =
    ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        // If our predicate succeeded, we stopped the runloop and should not be called again.
        OBASSERT(!done);

        done = predicate();
        if (done) {
            CFRunLoopStop(runLoop);
        }
    };
    
    CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopBeforeWaiting, true, 0, beforeWaiting);
    CFRunLoopAddObserver(runLoop, observer, kCFRunLoopDefaultMode);
    
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    while (YES) {
        CFTimeInterval remainingTimeout = 0.0;
        if (timeout > 0.0) {
            CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
            remainingTimeout = (startTime + timeout) - currentTime;
        }
        
        SInt32 returnReason = CFRunLoopRunInMode(kCFRunLoopDefaultMode, remainingTimeout, false);
        OBASSERT(returnReason != kCFRunLoopRunFinished, "This should only be returned if the run loop has no sources or timers, but we added a source");
        
        if (returnReason == kCFRunLoopRunStopped) {
            if (done) {
                break;
            } else {
                // Some other source called CFRunLoopStop()?
            }
        }
        if (returnReason == kCFRunLoopRunTimedOut) {
            OBASSERT(!done); // Ran out of time
            break;
        }
        // Otherwise, we are likely running on the main queue with AppKit and lots of other sources and got kCFRunLoopRunHandledSource. CFRunLoopRunInMode() will only handle 1 or possibly two sources before returning.
    }
    
    CFRunLoopRemoveObserver(runLoop, observer, kCFRunLoopDefaultMode);
    CFRelease(observer);
    
    if (timer) {
        CFRunLoopRemoveTimer(runLoop, timer, kCFRunLoopDefaultMode);
        CFRelease(timer);
    }
    
    return done;
}

// Wrapper that hides the NSInvocation/NSMethodSignature details from Swift.

NSString * _Nullable OFInstanceMethodReturnTypeEncoding(Class cls, SEL sel)
{
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL) {
        return nil;
    }

    char *returnEncoding = method_copyReturnType(m);
    NSString *result = [NSString stringWithUTF8String:returnEncoding];
    free(returnEncoding);
    return result;
}


@interface NSMethodSignature (OFInvokeMethod) <OFInvokeMethodSignature>
@end
@implementation NSMethodSignature (OFInvokeMethod)
@end

@interface NSInvocation (OFInvokeMethod) <OFInvokeMethodInvocation>
@end
@implementation NSInvocation (OFInvokeMethod)
@end

// This intentionally does not set argumentsRetained, leaving that up to the provideArguments block.
BOOL OFInvokeMethod(id object, SEL selector, OFInvokeMethodHandler provideArguments, OFInvokeMethodHandler collectResults)
{
    NSMethodSignature *methodSignature = [object methodSignatureForSelector:selector];
    if (!methodSignature) {
        return NO;
    }

    OBRecordBacktraceWithContext(sel_getName(selector), OBBacktraceBuffer_PerformSelector, (__bridge const void *)object);

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSignature];
    [invocation setTarget:object];
    [invocation setSelector:selector];

    if (!provideArguments(methodSignature, invocation))
        return NO;

    [invocation invoke];

    return collectResults(methodSignature, invocation);
}

NS_ASSUME_NONNULL_END
