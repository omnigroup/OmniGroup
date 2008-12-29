// Copyright 1999-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFRunLoopScheduler.h>

#import <OmniFoundation/NSThread-OFExtensions.h>
#import <OmniFoundation/OFObject-Queue.h>

#import <Foundation/NSTimer.h>

RCS_ID("$Id$")

@interface OFRunLoopScheduler (Private)
- (void)mainThreadResetAlarmToFirstEntry;
@end

@implementation OFRunLoopScheduler

static NSLock *runLoopSchedulerLock;
static OFRunLoopScheduler *runLoopScheduler = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    runLoopSchedulerLock = [[NSLock alloc] init];
}

+ (OFRunLoopScheduler *)runLoopScheduler;
{
    if (runLoopScheduler)
        return runLoopScheduler;

    [runLoopSchedulerLock lock];
    if (runLoopScheduler == nil)
        runLoopScheduler = [[self alloc] init];
    [runLoopSchedulerLock unlock];
    return runLoopScheduler;
}

// Init and dealloc

- init;
{
    if (![super init])
        return nil;
    alarmTimer = nil;
    return self;
}

- (void)dealloc;
{
    [self cancelScheduledEvents];
    [super dealloc];
}

// OFScheduler subclass

- (void)scheduleEvents;
{
    [self mainThreadPerformSelector:
        @selector(mainThreadResetAlarmToFirstEntry)];
}

- (void)cancelScheduledEvents;
{
    [scheduleLock lock];
    if (alarmTimer != nil) {
        if (OFSchedulerDebug)
            NSLog(@"%@: invalidating alarm timer %@", [self shortDescription], alarmTimer);
        [alarmTimer invalidate];
        [alarmTimer release];
        alarmTimer = nil;
    }
    [scheduleLock unlock];
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (alarmTimer)
        [debugDictionary setObject:alarmTimer forKey:@"alarmTimer"];
    return debugDictionary;
}

@end

@implementation OFRunLoopScheduler (Private)

- (void)mainThreadResetAlarmToFirstEntry;
{
    NSDate *eventDate;
    double period;

    OBPRECONDITION([NSThread isMainThread]);
    [scheduleLock lock];

    [self cancelScheduledEvents];
    eventDate = [self dateOfFirstEvent];
    if (eventDate != nil) {
        period = [eventDate timeIntervalSinceNow];  // This may be <0, as NSTimer just substitutes >0

        alarmTimer = [[NSTimer timerWithTimeInterval:period target:self selector:@selector(invokeScheduledEvents) userInfo:nil repeats:NO] retain];
        [[NSRunLoop currentRunLoop] addTimer:alarmTimer forMode:NSDefaultRunLoopMode];

        if (OFSchedulerDebug)
            NSLog(@"%@: waiting until %@ (%@)", [self shortDescription], eventDate, alarmTimer);
    }
    
    [scheduleLock unlock];
}

@end
