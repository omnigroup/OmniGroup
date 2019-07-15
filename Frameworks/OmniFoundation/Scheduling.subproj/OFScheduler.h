// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFController.h>

@class NSDate, NSRecursiveLock, NSMutableArray;
@class OFDedicatedThreadScheduler, OFInvocation, OFScheduledEvent;

#import <Foundation/NSDate.h> // For NSTimeInterval

@interface OFScheduler : NSObject <OFControllerStatusObserver>
{
    NSMutableArray *scheduleQueue;
    NSRecursiveLock *scheduleLock;
    BOOL terminationSignaled;
}

+ (OFScheduler *)mainScheduler;
+ (OFScheduler *)mainSchedulerIfCreated;
+ (OFDedicatedThreadScheduler *)dedicatedThreadScheduler;

- (void)scheduleEvents;
- (void)scheduleEvent:(OFScheduledEvent *)event;
- (BOOL)abortEvent:(OFScheduledEvent *)anEvent;
- (void)abortSchedule;
- (OFScheduler *)subscheduler;
- (NSDate *)dateOfFirstEvent;

// Convenience Methods
- (OFScheduledEvent *)scheduleInvocation:(OFInvocation *)anInvocation atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleInvocation:(OFInvocation *)anInvocation afterTime:(NSTimeInterval)time;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withObject:(id)anArgument atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withBool:(BOOL)anArgument atDate:(NSDate *)date;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject afterTime:(NSTimeInterval)time;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withObject:(id)anArgument afterTime:(NSTimeInterval)time;
- (OFScheduledEvent *)scheduleSelector:(SEL)selector onObject:(id)anObject withBool:(BOOL)anArgument afterTime:(NSTimeInterval)time;

// OFControllerStatusObserver methods implemented
- (void)controllerWillTerminate:(OFController *)controller NS_REQUIRES_SUPER;

@end
