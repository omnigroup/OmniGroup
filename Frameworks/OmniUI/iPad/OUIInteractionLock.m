// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInteractionLock.h>

#import <OmniFoundation/OFWeakReference.h>
#import <OmniFoundation/OFBacktrace.h>
#import <mach-o/dyld.h>
#import <mach-o/arch.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_INTERACTION_LOCK(format, ...) NSLog(@"INTERACTION LOCK: In %@." format, NSStringFromSelector(_cmd), ## __VA_ARGS__)
#else
#define DEBUG_INTERACTION_LOCK(format, ...)
#endif

NS_ASSUME_NONNULL_BEGIN

static const NSTimeInterval kOUIInteractionLockStaleInterval = 10;

@interface OUIInteractionLock ()
@property(nonatomic,readonly) NSTimeInterval creationTimeInterval;
@property(nonatomic,readonly) NSString *backtrace;
@end

@implementation OUIInteractionLock
{
    BOOL _locked;
    NSString *_numericBacktraceString;
}

// TODO: Add a timer when the first lock is made that will log backtraces for any remaining locks after a few seconds

// Maintain a list of locks that are still locked. We store these as weak references so that +activeLocks isn't racing with the code in -dealloc that tries to remove the lock from the list (otherwise we could use a non-retaining CFMutableArrayRef).
static dispatch_queue_t LockQueue;
static NSMutableArray * _Nullable ActiveLockReferences = nil;
static NSTimer * _Nullable ActiveLockWarningTimer = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    LockQueue = dispatch_queue_create("com.omnigroup.OmniUI.OUIInteractionLock", DISPATCH_QUEUE_SERIAL);
    ActiveLockReferences = [NSMutableArray new];
}

+ (NSArray *)activeLocks;
{
    NSMutableArray *locks = [NSMutableArray array];
    
    dispatch_sync(LockQueue, ^{
        for (OFWeakReference *ref in ActiveLockReferences) {
            OUIInteractionLock *lock = ref.object;
            if (lock)
                [locks addObject:lock];
        }
    });
    
    return locks;
}

+ (BOOL)hasActiveLocks;
{
    __block BOOL hasActiveLocks = NO;
    
    dispatch_sync(LockQueue, ^{
        hasActiveLocks = (ActiveLockReferences.count != 0);
    });
    
    return hasActiveLocks;
}

+ (instancetype)applicationLock;
{
    OUIInteractionLock *instance = [[self alloc] _initApplicationLock];
    DEBUG_INTERACTION_LOCK(@"created %@", instance);
    return instance;
}

// Don't want existing callers of this to build up. Always use the +applicationLock method for now so that it is easy to later add a +viewLock for tracking disabling interaction on views instead of the whole app.
- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

static void _dumpImageInfo(void)
{
    // stderr seems to get dropped on the ground on the device, so us NSLog
    uint32_t imageCount = _dyld_image_count();
    
    NSMutableString *report = [NSMutableString new];
    [report appendFormat:@"\nBinary Images (%s):\n", NXGetLocalArchInfo()->name];
    
    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const struct mach_header *mh = _dyld_get_image_header(imageIndex);
        const char *name = _dyld_get_image_name(imageIndex);
        
        [report appendFormat:@"%p %s\n", mh, name];
    }
    NSLog(@"%@", report);
}
    
- (void)dealloc NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");
{
    DEBUG_INTERACTION_LOCK(@"self: %@", self);
    if (_locked) {
        if (_numericBacktraceString) {
            NSLog(@"OUIInteractionLock not unlocked:\n%@", OFCopySymbolicBacktraceForNumericBacktrace(_numericBacktraceString));
            _dumpImageInfo();
        }
        
        OBASSERT_NOT_REACHED("Should have been unlocked. bug:///142479 (Frameworks-iOS Engineering: -[OUIInteractionLock dealloc] assertion failure opening iCloud Drive document when document already open with split-screen sharing)");

        // sync since our pointer is about to be available for reuse
        void *ptr = (__bridge void *)self; // don't capture self in the block since we are deallocating.
        dispatch_sync(LockQueue, ^{
            NSUInteger lockIndex = [ActiveLockReferences indexOfObjectPassingTest:^BOOL(OFWeakReference *ref, NSUInteger idx, BOOL *stop) {
                return [ref referencesDeallocatingObjectPointer:ptr];
            }];

            if (lockIndex == NSNotFound) {
                OBASSERT_NOT_REACHED("self not found in ActiveLockReferences.");
                return;
            }

#ifdef OMNI_ASSERTIONS_ON
            OFWeakReference *ref = ActiveLockReferences[lockIndex];
            OBASSERT(ref != nil);
            OBASSERT(ref.object == nil); // We are in -dealloc, so it's weak reference to us should be gone.
#endif

            [ActiveLockReferences removeObjectAtIndex:lockIndex];
            if ([ActiveLockReferences count] == 0) {
                // NSRunLoop is not thread-safe; don't assume we are on the main thread here. We can clear it here though.
                NSTimer *timer = ActiveLockWarningTimer;
                ActiveLockWarningTimer = nil;
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [timer invalidate];
                }];
            }
        });
        
        // In case this was passed around from queue to queue and then dropped on the ground, don't assume -dealloc is on the main queue.
        // Also, don't resurrect ourselves, so no call to -unlock.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }];
    }
}

- (void)unlock NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions");
{
    DEBUG_INTERACTION_LOCK(@"self: %@", self);
    OBPRECONDITION([NSThread isMainThread], "UIKit isn't guaranteed to be thread safe");
    
    if (!_locked)
        return;
    
    _locked = NO;
    [[UIApplication sharedApplication] endIgnoringInteractionEvents];
    
    // No need for sync and can capture here
    dispatch_async(LockQueue, ^{
        NSUInteger lockIndex = [ActiveLockReferences indexOfObjectPassingTest:^BOOL(OFWeakReference *ref, NSUInteger idx, BOOL *stop) {
            return [ref referencesObject:(__bridge void *)self];
        }];
        [ActiveLockReferences removeObjectAtIndex:lockIndex];
        if ([ActiveLockReferences count] == 0) {
            NSTimer *timer = ActiveLockWarningTimer;
            ActiveLockWarningTimer = nil;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [timer invalidate];
            }];
        }
    });
}

#pragma mark - Private

- (NSString *)backtrace;
{
    if (_numericBacktraceString)
        return OFCopySymbolicBacktraceForNumericBacktrace(_numericBacktraceString);
    return @"Unknown";
}

- (id)_initApplicationLock NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");
{
    OBPRECONDITION([NSThread isMainThread], "UIKit isn't guaranteed to be thread safe");

    if (!(self = [super init]))
        return nil;
    
    _creationTimeInterval = [NSDate timeIntervalSinceReferenceDate];
    _locked = YES;
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    _numericBacktraceString = OFCopyNumericBacktraceString(0);
    
    dispatch_async(LockQueue, ^{
        if ([ActiveLockReferences count] == 0) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                // Have to do this on the main queue so it the runloop it is scheduled in doesn't go away
                ActiveLockWarningTimer = [NSTimer scheduledTimerWithTimeInterval:kOUIInteractionLockStaleInterval target:[self class] selector:@selector(_activeLockTimerFired:) userInfo:nil repeats:YES];
            }];
        }
        OFWeakReference *ref = [[OFWeakReference alloc] initWithObject:self];
        [ActiveLockReferences addObject:ref];
    });
    
    return self;
}

+ (void)_activeLockTimerFired:(NSTimer *)timer NS_EXTENSION_UNAVAILABLE_IOS("Interaction lock is not available in extensions.");
{
    OBPRECONDITION([NSThread isMainThread]);
    
    for (OUIInteractionLock *lock in [self activeLocks]) {
        if ([NSDate timeIntervalSinceReferenceDate] - lock.creationTimeInterval > kOUIInteractionLockStaleInterval) {
            NSLog(@"Unlocking stale interaction lock %@:\n%@", [lock shortDescription], lock.backtrace);
            _dumpImageInfo();
            [lock unlock];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
