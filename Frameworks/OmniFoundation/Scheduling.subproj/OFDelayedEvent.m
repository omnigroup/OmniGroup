// Copyright 1997-2005, 2007, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDelayedEvent.h>

#import <Availability.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFScheduler.h>
#import <OmniFoundation/OFScheduledEvent.h>
#import <OmniFoundation/NSDate-OFExtensions.h>

RCS_ID("$Id$")

@implementation OFDelayedEvent

- initWithInvocation:(OFInvocation *)anInvocation delayInterval:(NSTimeInterval)aDelayInterval scheduler:(OFScheduler *)aScheduler fireOnTermination:(BOOL)shouldFireOnTermination;
{
    if (!(self = [super init]))
        return nil;
    
    lock = [[NSLock alloc] init];
    invocation = [anInvocation retain];
    delayInterval = aDelayInterval;
    if (!aScheduler)
        aScheduler = [OFScheduler mainScheduler];
    scheduler = [aScheduler retain];
    fireOnTermination = shouldFireOnTermination;
    
    return self;
}

- initWithInvocation:(OFInvocation *)anInvocation delayInterval:(NSTimeInterval)aDelayInterval;
{
    return [self initWithInvocation:anInvocation delayInterval:aDelayInterval scheduler:nil fireOnTermination:NO];
}


- initForObject:(id)anObject selector:(SEL)aSelector withObject:(id)aWithObject delayInterval:(NSTimeInterval)aDelayInterval scheduler:(OFScheduler *)aScheduler fireOnTermination:(BOOL)shouldFireOnTermination;
{
    OFInvocation *anInvocation;
    OFDelayedEvent *returnValue;
    
    anInvocation = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:aWithObject];
    returnValue = [self initWithInvocation:anInvocation delayInterval:aDelayInterval scheduler:aScheduler fireOnTermination:shouldFireOnTermination];
    [anInvocation release];
    
    return returnValue;
}

- initForObject:(id)anObject selector:(SEL)aSelector withObject:(id)aWithObject delayInterval:(NSTimeInterval)aDelayInterval;
{
    return [self initForObject:anObject selector:aSelector withObject:aWithObject delayInterval:aDelayInterval scheduler:nil fireOnTermination:NO];
}

- (void) dealloc;
{
    [lock release];
    [invocation release];
    if (scheduledEvent) {
        [scheduler abortEvent: scheduledEvent];
        [scheduledEvent release];
    }
    [scheduler release];
    [super dealloc];
}

- (OFInvocation *)invocation;
{
    return invocation;
}

- (NSTimeInterval)delayInterval;
{
    return delayInterval;
}

- (NSDate *)pendingDate;
{
    return [[scheduledEvent date] dateByAddingTimeInterval:-delayInterval];
}

- (NSDate *)fireDate;
{
    return [scheduledEvent date];
}

- (OFScheduler *)scheduler;
{
    return scheduler;
}

- (BOOL) fireOnTermination;
{
    return fireOnTermination;
}

- (BOOL) isPending;
{
    // Don't need to lock for this
    return scheduledEvent != nil;
}

- (BOOL) invokeIfPending;
{
    BOOL invokeCalled = NO;
    
    [lock lock];
    
    @try {
        if (scheduledEvent) {
            // Check the return of -abortEvent: to avoid the race condition between the event
            // getting invoked in a dedicated thread scheduler and our invocation here.
            // If it already got invoked, -abortEvent: will return NO.
            if ([scheduler abortEvent: scheduledEvent]) {
                invokeCalled = YES;
                [scheduledEvent invoke];
            }
        }
    } @catch (NSException *exc) {
        NSLog(@"Ignored exception raised during -[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), exc);
    }
    // Forget the event regardless of whether it raised or not
    [scheduledEvent release];
    scheduledEvent = nil;
    
    [lock unlock];
    
    return invokeCalled;
}

- (BOOL) cancelIfPending;
{
    BOOL wasCancelled = NO;
    
    [lock lock];
    
    if (scheduledEvent) {
        wasCancelled = YES;
        [scheduler abortEvent: scheduledEvent];
        [scheduledEvent release];
        scheduledEvent = nil;
    }
    
    [lock unlock];
    
    return wasCancelled;
}

- (void) invokeLater;
{
    [lock lock];
    
    // Get rid of the old event, if any
    if (scheduledEvent) {
        // As above, this event might get invoked anyway by another thread.  This isn't really a concern here, though,
        // since that's within the semantics of the object.
        [scheduler abortEvent: scheduledEvent];
        [scheduledEvent release];
        scheduledEvent = nil;
    }
    
    // Generate a new event for sometime later
    scheduledEvent = [[OFScheduledEvent alloc] initWithInvocation: invocation
                      atDate: [NSDate dateWithTimeIntervalSinceNow: delayInterval]
                      fireOnTermination: fireOnTermination];
    [scheduler scheduleEvent: scheduledEvent];
    
    [lock unlock];
}

@end

