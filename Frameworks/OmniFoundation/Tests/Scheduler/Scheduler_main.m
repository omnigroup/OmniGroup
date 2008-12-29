// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$");

static void Test(void);

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    Test();

    [pool release];
    return 0;
}

@interface SimpleLog : NSObject
- (void)logDate:(NSDate *)date;
@end

static OFScheduler *scheduler = nil;
static SimpleLog *simpleLog;
static NSDate *startDate;
static NSLock *scheduledEventDatesLock;
static NSMutableArray *scheduledEventDates;

static void Setup(BOOL invokeInMainThread, BOOL useSubscheduler)
{
    OFDedicatedThreadScheduler *dedicatedThreadScheduler;

    if (scheduler != nil)
        return; // Already set up (but what if parameters changed?)

    dedicatedThreadScheduler = [OFScheduler dedicatedThreadScheduler];
    [dedicatedThreadScheduler setInvokesEventsInMainThread:invokeInMainThread];
    if (useSubscheduler) {
        scheduler = [[dedicatedThreadScheduler subscheduler] retain];
    } else {
        scheduler = [dedicatedThreadScheduler retain];
    }
    simpleLog = [[SimpleLog alloc] init];
    scheduledEventDatesLock = [[NSLock alloc] init];
    scheduledEventDates = [[NSMutableArray alloc] init];
}

static void DisplayScheduledEventDates(void)
{
    unsigned int eventIndex, eventCount;

    [scheduledEventDatesLock lock];
    eventCount = [scheduledEventDates count];
    for (eventIndex = 0; eventIndex < eventCount; eventIndex++) {
        NSDate *eventDate;

        eventDate = [scheduledEventDates objectAtIndex:eventIndex];
        NSLog(@"Scheduled event at %0.1f seconds", [eventDate timeIntervalSinceDate:startDate]);
    }
    [scheduledEventDatesLock unlock];
}

static void AddScheduledEventDate(NSDate *eventDate)
{
    [scheduledEventDatesLock lock];
    [scheduledEventDates addObject:eventDate];
    [scheduledEventDatesLock unlock];
}

static void RemoveScheduledEventDate(NSDate *eventDate)
{
    unsigned int eventIndex;

    [scheduledEventDatesLock lock];
    eventIndex = [scheduledEventDates indexOfObjectIdenticalTo:eventDate];
    OBASSERT(eventIndex != NSNotFound);
    [scheduledEventDates removeObjectAtIndex:eventIndex];
    [scheduledEventDatesLock unlock];
}

static void ScheduleEventForDate(NSDate *date)
{
    NSLog(@"(%0.1f) Adding event at %0.1f seconds", [[NSDate date] timeIntervalSinceDate:startDate], [date timeIntervalSinceDate:startDate]);
    AddScheduledEventDate(date);
    [scheduler scheduleSelector:@selector(logDate:) onObject:simpleLog withObject:date atDate:date];
}

static void ScheduleEventForTimeInterval(NSTimeInterval timeInterval)
{
    NSDate *eventDate;

    eventDate = [[NSDate alloc] initWithTimeInterval:timeInterval sinceDate:startDate];
    ScheduleEventForDate(eventDate);
    [eventDate release];
}

static void WaitForTimeInterval(NSTimeInterval timeInterval)
{
    NSDate *waitDate;

    NSLog(@"(%0.1f) Waiting to %0.1f seconds", [[NSDate date] timeIntervalSinceDate:startDate], timeInterval);
    waitDate = [startDate addTimeInterval:timeInterval];
    [[NSRunLoop currentRunLoop] runUntilDate:waitDate];
    NSLog(@"(%0.1f) Waited to %0.1f seconds", [[NSDate date] timeIntervalSinceDate:startDate], timeInterval);
}

static void BlockUntilTimeInterval(NSTimeInterval timeInterval)
{
    NSDate *waitDate;

    NSLog(@"(%0.1f) Blocking to %0.1f seconds", [[NSDate date] timeIntervalSinceDate:startDate], timeInterval);
    waitDate = [startDate addTimeInterval:timeInterval];
    [waitDate sleepUntilDate];
    NSLog(@"(%0.1f) Blocked to %0.1f seconds", [[NSDate date] timeIntervalSinceDate:startDate], timeInterval);
}

static void Test(void)
{
    Setup(YES, NO);

    startDate = [NSDate date];

    ScheduleEventForTimeInterval(5.0);
    ScheduleEventForTimeInterval(1.0);
    ScheduleEventForTimeInterval(1.0);
    ScheduleEventForTimeInterval(2.0);
    ScheduleEventForTimeInterval(3.0);
    ScheduleEventForTimeInterval(4.0);
    ScheduleEventForTimeInterval(6.0);
    ScheduleEventForTimeInterval(7.0);
    ScheduleEventForTimeInterval(8.3); // This will be aborted
    ScheduleEventForTimeInterval(9.3); // This will be aborted
    ScheduleEventForTimeInterval(10.3); // This will be aborted
    ScheduleEventForTimeInterval(12.3); // This will be aborted
    WaitForTimeInterval(3.1); // Wait a few seconds so we can try inserting some events
    ScheduleEventForTimeInterval(3.5);
    ScheduleEventForTimeInterval(7.5);
    ScheduleEventForTimeInterval(2.5); // This is in the past
    WaitForTimeInterval(6.0);
    ScheduleEventForTimeInterval(6.25);
    ScheduleEventForTimeInterval(6.5);
    ScheduleEventForTimeInterval(6.75);
    BlockUntilTimeInterval(7.25); // Pretend we got too busy to service events
    WaitForTimeInterval(8.0); // Process those backlogged events
    NSLog(@"(%0.1f) Aborting schedule", [[NSDate date] timeIntervalSinceDate:startDate]);
    [scheduler abortSchedule];
    WaitForTimeInterval(10.0); // Wait to make sure aborted events cleared
    ScheduleEventForTimeInterval(11.5);
    ScheduleEventForTimeInterval(12.0);
    ScheduleEventForTimeInterval(11.0);
    ScheduleEventForTimeInterval(12.5);
    WaitForTimeInterval(13.0); // Wait for events to clear naturally
    WaitForTimeInterval(14.0); // Idle time
    ScheduleEventForTimeInterval(14.5); // Schedule one last event
    WaitForTimeInterval(15.0); // Wait for end of all scheduled events
    NSLog(@"(%0.1f) Done", [[NSDate date] timeIntervalSinceDate:startDate]);
    DisplayScheduledEventDates(); // Should list the aborted events (*.3) and nothing else
}

static void Test2(void)
{
    Setup(YES, YES);
    while (YES) {
        startDate = [NSDate date];
        ScheduleEventForTimeInterval(-1.0);
        [[startDate addTimeInterval:0.5] sleepUntilDate];
        NSLog(@"runLoop = %@", [NSRunLoop currentRunLoop]);
        WaitForTimeInterval(1.0);
    }
}

@implementation SimpleLog

- (void)logDate:(NSDate *)date;
{
    NSLog(@"(%0.1f) %@ Processing event scheduled for %0.1f seconds", [[NSDate date] timeIntervalSinceDate:startDate], [NSThread isMainThread] ? @"[MainThread]" : @"[SchedulerThread]", [date timeIntervalSinceDate:startDate]);
    RemoveScheduledEventDate(date);
}

@end
