// Copyright 1997-2005, 2007, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSThread-OFExtensions.h>

#import <OmniBase/system.h>

#ifdef __MACH__
#import <mach/mach_init.h>
#import <mach/mach_error.h>
#endif

#import <OmniFoundation/OFMessageQueue.h>

RCS_ID("$Id$")

@implementation NSThread (OFExtensions)

static NSConditionLock *mainThreadInterlock;
static NSLock *threadsWaitingLock;
static unsigned int threadsWaiting;
static unsigned int recursionCount;
static NSThread *substituteMainThread;

enum {
    THREADS_WAITING, NO_THREADS_WAITING
};

+ (void)didLoad;
{
    if (mainThreadInterlock == nil) {
        mainThreadInterlock = [[NSConditionLock alloc] init];
        [mainThreadInterlock lock];
        threadsWaitingLock = [[NSLock alloc] init];
        threadsWaiting = 0;
        recursionCount = 0;
    }
}

+ (BOOL)mainThreadOpsOK;
{
    return ([self isMainThread] || ([self currentThread] == substituteMainThread));
}
    
+ (void)lockMainThread;
{
    if ([self isMainThread])
        return;

    if ([self currentThread] == substituteMainThread) {
        recursionCount++;
        return;
    }

    [threadsWaitingLock lock];
    threadsWaiting++;
    [threadsWaitingLock unlock];
    [[OFMessageQueue mainQueue] queueSelectorOnce:@selector(yieldMainThreadLock) forObject:[self mainThread]];
    [mainThreadInterlock lock];
    OBASSERT(substituteMainThread == nil);
    substituteMainThread = [self currentThread];
    recursionCount = 1;
}

+ (void)unlockMainThread;
{
    if ([self isMainThread])
        return;

    OBASSERT(substituteMainThread == [self currentThread]);
    
    if (--recursionCount)
        return;
    
    substituteMainThread = nil;

    [threadsWaitingLock lock];
    if (--threadsWaiting > 0)
        [mainThreadInterlock unlockWithCondition:THREADS_WAITING];
    else
        [mainThreadInterlock unlockWithCondition:NO_THREADS_WAITING];
    [threadsWaitingLock unlock];
}

- (void)yield;
{
    if (![self yieldMainThreadLock])
        sched_yield();
}

- (BOOL)yieldMainThreadLock;
{
    if (![self isMainThread])
        return NO;

    BOOL noThreadsWaiting;

    [threadsWaitingLock lock];
    noThreadsWaiting = (threadsWaiting == 0);
    [threadsWaitingLock unlock];
    if (noThreadsWaiting)
        return NO;

    [mainThreadInterlock unlockWithCondition:THREADS_WAITING];
    [mainThreadInterlock lockWhenCondition:NO_THREADS_WAITING];

    return YES;
}

@end
