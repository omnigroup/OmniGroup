// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFScheduler.h>

#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/OFDedicatedThreadScheduler.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFScheduledEvent.h>
#import <OmniFoundation/OFController.h>
#import <OmniFoundation/NSThread-OFExtensions.h>

#import <OmniFoundation/OFChildScheduler.h>
#import <OmniFoundation/OFRunLoopScheduler.h>

RCS_ID("$Id$")

@interface OFScheduler (Private)
+ (void)setDebug:(BOOL)newDebug;
- (void)invokeEvents:(NSArray *)events;
- (void)controllerWillTerminate:(OFController *)controller;
@end

@implementation OFScheduler

// #define DEBUG_ALLOCATIONS

#ifdef DEBUG_ALLOCATIONS

static int instanceCount = 0;
static NSLock *instanceCountLock;

+ (void)initialize;
{
    OBINITIALIZE;
    instanceCountLock = [[NSLock alloc] init];
}

#endif

+ (OFScheduler *)mainScheduler;
{
    // This used to return a run loop scheduler, but that seems to be buggy in DP4.
    return [OFDedicatedThreadScheduler dedicatedThreadScheduler];
}

+ (OFDedicatedThreadScheduler *)dedicatedThreadScheduler;
{
    return [OFDedicatedThreadScheduler dedicatedThreadScheduler];
}

// Init and dealloc

- init;
{
#ifdef DEBUG_ALLOCATIONS
    [instanceCountLock lock];
    instanceCount++;
    NSLog(@"[%@ init]: %d instances", [self class], instanceCount);
    [instanceCountLock unlock];
#endif

    if ([super init] == nil)
        return nil;

    OFWeakRetainConcreteImplementation_INIT;
    scheduleQueue = [[NSMutableArray alloc] init];
    scheduleLock = [[NSRecursiveLock alloc] init];

    [[OFController sharedController] addObserver:self];

    return self;
}

- (void)dealloc;
{
    OFWeakRetainConcreteImplementation_DEALLOC;
    [scheduleQueue release];
    [scheduleLock release];
#ifdef DEBUG_ALLOCATIONS
    [instanceCountLock lock];
    instanceCount--;
    NSLog(@"[%@ dealloc]: %d instances", [self class], instanceCount);
    [instanceCountLock unlock];
#endif
    [super dealloc];
}


// Public API

- (void)scheduleEvent:(OFScheduledEvent *)event;
{
    // If we've already recieved the termination notification, invoke any on-termination events immediately.
    if (terminationSignaled && [event fireOnTermination]) {
        [self invokeEvents:[NSArray arrayWithObject:event]];
        return;
    }
    
    [scheduleLock lock];
    [scheduleQueue insertObject:event inArraySortedUsingSelector:@selector(compare:)];
    if ([scheduleQueue objectAtIndex:0] == event) {
        [self scheduleEvents];
    }
    [scheduleLock unlock];
}

/*" Removes the specified event from the receiver's schedule, if present.  If the event was present (and thus was removed), returns YES.  Otherwise (if, for example, the event has fired already), NO is returned. "*/
- (BOOL)abortEvent:(OFScheduledEvent *)event;
{
    BOOL eventWasFirstInQueue;
    BOOL wasFound = NO;
    
    if (event == nil)
        return wasFound;
        
    [scheduleLock lock];
    eventWasFirstInQueue = [scheduleQueue count] != 0 && [scheduleQueue objectAtIndex:0] == event;
    if (eventWasFirstInQueue) {
        wasFound = YES;
        [scheduleQueue removeObjectAtIndex:0];
	[self scheduleEvents];
    } else {
        NSUInteger objectIndex = [scheduleQueue indexOfObjectIdenticalTo:event inArraySortedUsingSelector:@selector(compare:)];
        if (objectIndex != NSNotFound) {
            wasFound = YES;
            [scheduleQueue removeObjectAtIndex:objectIndex];
        }
    }
    [scheduleLock unlock];
    
    return wasFound;
}

- (void)abortSchedule;
{
    [scheduleLock lock];
    [self cancelScheduledEvents];
    [scheduleQueue removeAllObjects];
    [scheduleLock unlock];
}

- (OFScheduler *)subscheduler;
{
    return [[[OFChildScheduler alloc] initWithParentScheduler:self] autorelease];
}

- (NSDate *)dateOfFirstEvent;
{
    NSDate *dateOfFirstEvent;

    [scheduleLock lock];
    if ([scheduleQueue count] != 0) {
        OFScheduledEvent *firstEvent = [scheduleQueue objectAtIndex:0];
        dateOfFirstEvent = [[firstEvent date] retain];
    } else {
        dateOfFirstEvent = nil;
    }
    [scheduleLock unlock];
    return [dateOfFirstEvent autorelease];
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (scheduleQueue)
        [debugDictionary setObject:scheduleQueue forKey:@"scheduleQueue"];
    if (scheduleLock)
        [debugDictionary setObject:scheduleLock forKey:@"scheduleLock"];
    return debugDictionary;
}

// OFWeakRetain protocol

OFWeakRetainConcreteImplementation_IMPLEMENTATION

- (void)invalidateWeakRetains;
{
    [[OFController sharedController] removeObserver:self];
}

@end

@implementation OFScheduler (OFConvenienceMethods)

- (OFScheduledEvent *)scheduleInvocation:(OFInvocation *)anInvocation atDate:(NSDate *)date;
{
    OFScheduledEvent *event;

    event = [[[OFScheduledEvent alloc] initWithInvocation:anInvocation atDate:date] autorelease];
    [self scheduleEvent:event];
    return event;
}

- (OFScheduledEvent *)scheduleInvocation:(OFInvocation *)anInvocation afterTime:(NSTimeInterval)timeInterval;
{
    return [self scheduleInvocation:anInvocation atDate:[NSDate dateWithTimeIntervalSinceNow:timeInterval]];
}

- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject atDate:(NSDate *)date;
{
    OFInvocation *invocation;
    OFScheduledEvent *event;

    invocation = [[OFInvocation alloc] initForObject:anObject selector:selector];
    event = [self scheduleInvocation:invocation atDate:date];
    [invocation release];
    return event;
}

- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withObject:(id)anArgument atDate:(NSDate *)date;
{
    OFInvocation *invocation;
    OFScheduledEvent *event;

    invocation = [[OFInvocation alloc] initForObject:anObject selector:selector withObject:anArgument];
    event = [self scheduleInvocation:invocation atDate:date];
    [invocation release];
    return event;
}

- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withBool:(BOOL)anArgument atDate:(NSDate *)date;
{
    OFInvocation *invocation;
    OFScheduledEvent *event;

    invocation = [[OFInvocation alloc] initForObject:anObject selector:selector withBool:anArgument];
    event = [self scheduleInvocation:invocation atDate:date];
    [invocation release];
    return event;
}

- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject afterTime:(NSTimeInterval)timeInterval;
{
    return [self scheduleSelector:selector onObject:anObject atDate:[NSDate dateWithTimeIntervalSinceNow:timeInterval]];
}

- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withObject:(id)anArgument afterTime:(NSTimeInterval)timeInterval;
{
    return [self scheduleSelector:selector onObject:anObject withObject:anArgument atDate:[NSDate dateWithTimeIntervalSinceNow:timeInterval]];
}

- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withBool:(BOOL)anArgument afterTime:(NSTimeInterval)timeInterval;
{
    return [self scheduleSelector:selector onObject:anObject withBool:anArgument atDate:[NSDate dateWithTimeIntervalSinceNow:timeInterval]];
}

@end

@implementation OFScheduler (SubclassesOnly)

- (void)invokeScheduledEvents;
{
    NSMutableArray *eventsToInvokeNow = [[NSMutableArray alloc] init];
    [scheduleLock lock];
    unsigned int remainingEventCount = [scheduleQueue count];
    while (remainingEventCount--) {
        OFScheduledEvent *event = [scheduleQueue objectAtIndex:0];
        if ([[event date] timeIntervalSinceNow] > 0.0) {
            [self scheduleEvents];
            remainingEventCount = 0;
        } else {
            [eventsToInvokeNow addObject:event];
            [scheduleQueue removeObjectAtIndex:0];
        }
    }
    [scheduleLock unlock];
    [self invokeEvents:eventsToInvokeNow];
    [eventsToInvokeNow release];
}

- (void)scheduleEvents;
{
    // Subclasses must override this method
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)cancelScheduledEvents;
{
    // Subclasses must override this method
    OBRequestConcreteImplementation(self, _cmd);
}

@end

@implementation OFScheduler (Private)

+ (void)setDebug:(BOOL)newDebug;
{
    OFSchedulerDebug = newDebug;
}

- (void)invokeEvents:(NSArray *)events;
{
    unsigned int eventIndex, eventCount;

    eventCount = [events count];
    for (eventIndex = 0; eventIndex < eventCount; eventIndex++) {
        OFScheduledEvent *event;

        event = [events objectAtIndex:eventIndex];
        NS_DURING {
            OMNI_POOL_START {
                if (OFSchedulerDebug)
                    NSLog(@"%@: invoking %@", [self shortDescription], [event shortDescription]);
                [event invoke];
            } OMNI_POOL_END;
        } NS_HANDLER {
            NSLog(@"%@: exception raised in %@: %@", [self shortDescription], [event shortDescription], [localException reason]);
        } NS_ENDHANDLER;
    }
}

- (void)controllerWillTerminate:(OFController *)controller;
{
    unsigned int remainingEventCount;
    NSMutableArray *terminationEvents;
        
    terminationSignaled = YES;

    if (OFSchedulerDebug)
        NSLog(@"%@: Processing termination events", [self shortDescription]);

    terminationEvents = [[NSMutableArray alloc] init];
    [scheduleLock lock];
    remainingEventCount = [scheduleQueue count];
    while (remainingEventCount--) {
        OFScheduledEvent *event;

        event = [scheduleQueue objectAtIndex:remainingEventCount];
        if ([event fireOnTermination]) {
            [terminationEvents addObject:event];
            [scheduleQueue removeObjectAtIndex:remainingEventCount];
        }
    }
    [scheduleLock unlock];
    
    if (OFSchedulerDebug)
        NSLog(@"Invoking termination events: %@", terminationEvents);
    [self invokeEvents:terminationEvents];
    [terminationEvents release];
}

@end

BOOL OFSchedulerDebug = NO;
