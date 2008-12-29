// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class NSDate, NSRecursiveLock, NSMutableArray;
@class OFDedicatedThreadScheduler, OFInvocation, OFScheduledEvent;

#import <Foundation/NSDate.h> // For NSTimeInterval
#import <OmniFoundation/OFWeakRetainConcreteImplementation.h>

@interface OFScheduler : OFObject <OFWeakRetain>
{
    NSMutableArray *scheduleQueue;
    NSRecursiveLock *scheduleLock;
    BOOL terminationSignaled;
    OFWeakRetainConcreteImplementation_IVARS;
}

+ (OFScheduler *)mainScheduler;
+ (OFDedicatedThreadScheduler *)dedicatedThreadScheduler;

- (void)scheduleEvent:(OFScheduledEvent *)event;
- (BOOL)abortEvent:(OFScheduledEvent *)anEvent;
- (void)abortSchedule;
- (OFScheduler *)subscheduler;
- (NSDate *)dateOfFirstEvent;

OFWeakRetainConcreteImplementation_INTERFACE

@end

@interface OFScheduler (OFConvenienceMethods)
- (OFScheduledEvent *)scheduleInvocation:(OFInvocation *)anInvocation atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleInvocation:(OFInvocation *)anInvocation afterTime:(NSTimeInterval)time;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withObject:(id)anArgument atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withBool:(BOOL)anArgument atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject afterTime:(NSTimeInterval)time;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withObject:(id)anArgument afterTime:(NSTimeInterval)time;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withBool:(BOOL)anArgument afterTime:(NSTimeInterval)time;
@end

@interface OFScheduler (SubclassesOnly)
- (void)invokeScheduledEvents;
    // Subclasses call this method to invoke all events scheduled to happen up to the current time
- (void)scheduleEvents;
    // Subclasses override this method to schedule their events
- (void)cancelScheduledEvents;
    // Subclasses override this method to cancel their previously scheduled events.
@end

extern BOOL OFSchedulerDebug;
