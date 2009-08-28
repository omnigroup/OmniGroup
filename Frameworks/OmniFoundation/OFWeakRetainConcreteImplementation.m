// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFWeakRetainConcreteImplementation.h>

#import <objc/objc-class.h>

RCS_ID("$Id$")

void _OFWeakRetainRelease(OFWeakRetainIvars *ivars, NSObject <OFWeakRetain> *self)
{
    NSException *raisedException = nil;
    BOOL shouldInvalidate;
    OFSimpleLockType *lock;

    OBPRECONDITION(ivars->inited);
    lock = &ivars->lock;
    OFSimpleLock(lock);
    NS_DURING {
        NSUInteger retainCount = [self retainCount];
        BOOL hasWeakRetains = ivars->count != OF_WEAK_RETAIN_INVALID_COUNT && ivars->count != 0;
        shouldInvalidate = hasWeakRetains && retainCount - 1 == ivars->count;
#ifdef DEBUG_WEAK_RETAIN
        NSLog(@"-[%@ release] (retainCount=%d, count=%d, shouldInvalidate=%@)", OBShortObjectDescription(self), retainCount, ivars->count, shouldInvalidate ? @"YES" : @"NO");
#endif
        if (shouldInvalidate) {
            // Defer our release until after we've invalidated the weak retains, and make sure nobody else gets it into their heads to also call -invalidateWeakRetains
            ivars->count = OF_WEAK_RETAIN_INVALID_COUNT;
        } else {
            if (retainCount == 1) {
                // This final release will deallocate the object, which means our lock is going away:  we need to unlock it first
                OFSimpleUnlock(lock);
                lock = NULL;
                [self _releaseFromWeakRetainHelper];
            } else {
                // Release within the lock so that if we switch threads we won't have two threads doing releases after both decided they didn't need to invalidate the object.
                [self _releaseFromWeakRetainHelper];
            }
        }
    } NS_HANDLER {
        raisedException = localException;
        shouldInvalidate = NO; // This won't be used because we'll raise first, but assigning a value to it here makes the compiler happy
    } NS_ENDHANDLER;
    if (lock != NULL)
        OFSimpleUnlock(lock);

    if (raisedException != nil)
        [raisedException raise];

    if (shouldInvalidate) {
        [self invalidateWeakRetains];
        [self _releaseFromWeakRetainHelper]; // OK, the object can go away now
    }
}

@implementation NSObject (OFWeakRetain)

- (id)weakRetain;
{
    [self retain];
    [(id <OFWeakRetain>)self incrementWeakRetainCount];
    return self;
}

- (void)weakRelease;
{
    [(id <OFWeakRetain>)self decrementWeakRetainCount];
    [self release];
}

- (id)weakAutorelease;
{
    [(id <OFWeakRetain>)self decrementWeakRetainCount];
    return [self autorelease];
}

static NSMutableSet *warnedClasses = nil;

- (void)incrementWeakRetainCount;
    // Not thread-safe, but this is debugging code
{
    if (warnedClasses == nil)
        warnedClasses = [[NSMutableSet alloc] init];

    if (![warnedClasses containsObject:isa]) {
        [warnedClasses addObject:isa];
        NSLog(@"%@ does not implement the OFWeakRetain protocol", NSStringFromClass(isa));
    }
}

- (void)decrementWeakRetainCount;
{
}

+ (void)incrementWeakRetainCount;
{
}

+ (void)decrementWeakRetainCount;
{
}

@end
