// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIRotationLock.h>

#import <OmniFoundation/OFWeakReference.h>
#import <OmniFoundation/OFBacktrace.h>
#import <mach-o/dyld.h>
#import <mach-o/arch.h>

RCS_ID("$Id$");

@interface OUIRotationLock ()
@property (nonatomic, readonly) NSString *backtrace;
@end


@implementation OUIRotationLock
{
    BOOL _locked;
    NSString *_numericBacktraceString;
}

static dispatch_queue_t LockQueue;
static NSMutableArray *ActiveLockReferences = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    LockQueue = dispatch_queue_create("com.omnigroup.OmniUI.OUIRotationLock", DISPATCH_QUEUE_SERIAL);
    ActiveLockReferences = [NSMutableArray new];
}


+ (NSArray *)activeLocks;
{
    NSMutableArray *locks = [NSMutableArray array];
    
    dispatch_sync(LockQueue, ^{
        for (OFWeakReference *ref in ActiveLockReferences) {
            OUIRotationLock *lock = ref.object;
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

+ (instancetype)rotationLock;
{
    return [[self alloc] _initRotationLock];
}

// Don't want existing callers of this to build up. Always use the +rotationLock method.
- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

- (void)dealloc;
{
    if (_locked) {
        if (_numericBacktraceString) {
            NSLog(@"%@ not unlocked:\n%@", NSStringFromClass([self class]), OFCopySymbolicBacktraceForNumericBacktrace(_numericBacktraceString));
            _dumpImageInfo();
        }
        
        OBASSERT_NOT_REACHED("Should have been unlocked");
        
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
        });
    }
}

- (void)unlock;
{
    OBPRECONDITION([NSThread isMainThread], "UIKit isn't guaranteed to be thread safe");
    OBPRECONDITION(_locked);
    
    if (!_locked)
        return;
    
    _locked = NO;
    
    // No need for sync and can capture here
    dispatch_async(LockQueue, ^{
        NSUInteger lockIndex = [ActiveLockReferences indexOfObjectPassingTest:^BOOL(OFWeakReference *ref, NSUInteger idx, BOOL *stop) {
            return [ref referencesObject:(__bridge void *)self];
        }];
        if (lockIndex != NSNotFound) {
            [ActiveLockReferences removeObjectAtIndex:lockIndex];
        }
    });
}

#pragma mark - Private
- (id)_initRotationLock;
{
    OBPRECONDITION([NSThread isMainThread], "UIKit isn't guaranteed to be thread safe");
    
    if (!(self = [super init]))
        return nil;
    
    _locked = YES;
    
    _numericBacktraceString = OFCopyNumericBacktraceString(0);
    
    dispatch_async(LockQueue, ^{
        OFWeakReference *ref = [[OFWeakReference alloc] initWithObject:self];
        [ActiveLockReferences addObject:ref];
    });
    
    return self;
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

- (NSString *)backtrace;
{
    if (_numericBacktraceString)
        return OFCopySymbolicBacktraceForNumericBacktrace(_numericBacktraceString);
    return @"Unknown";
}

@end
