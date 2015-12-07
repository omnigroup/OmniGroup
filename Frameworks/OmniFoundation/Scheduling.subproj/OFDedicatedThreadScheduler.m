// Copyright 1999-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDedicatedThreadScheduler.h>

#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/OFObject-Queue.h>

#import "OFScheduler-Subclass.h"

RCS_ID("$Id$")

enum {
    SCHEDULE_STABLE_CONDITION,
    SCHEDULE_CHANGED_CONDITION,
};

enum {
    MAIN_THREAD_IDLE,
    MAIN_THREAD_BUSY,
};

@implementation OFDedicatedThreadScheduler

static OFDedicatedThreadScheduler *dedicatedThreadSchedulerIfCreated(Class self, BOOL ifCreated)
{
    static OFDedicatedThreadScheduler *dedicatedThreadScheduler = nil;
    
    if (ifCreated)
        return dedicatedThreadScheduler;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dedicatedThreadScheduler = [[self alloc] init];
        [dedicatedThreadScheduler runScheduleForeverInNewThread];
    });
    
    return dedicatedThreadScheduler;
}

+ (OFDedicatedThreadScheduler *)dedicatedThreadScheduler;
{
    return dedicatedThreadSchedulerIfCreated(self, NO);
}

+ (OFDedicatedThreadScheduler *)dedicatedThreadSchedulerIfCreated;
{
    return dedicatedThreadSchedulerIfCreated(self, YES);
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    scheduleConditionLock = [[NSConditionLock alloc] initWithCondition:SCHEDULE_STABLE_CONDITION];
    mainThreadSynchronizationLock = [[NSConditionLock alloc] initWithCondition:MAIN_THREAD_IDLE];
    wakeDate = nil;
    wakeDateLock = [[NSLock alloc] init];
    flags.invokesEventsInMainThread = YES;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_systemClockChanged:) name:NSSystemClockDidChangeNotification object:nil];

    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSSystemClockDidChangeNotification object:nil];

    [scheduleConditionLock release];
    [mainThreadSynchronizationLock release];
    [wakeDate release];
    [wakeDateLock release];
    [super dealloc];
}

// API

- (void)setInvokesEventsInMainThread:(BOOL)shouldInvokeEventsInMainThread;
{
    flags.invokesEventsInMainThread = shouldInvokeEventsInMainThread;
}

- (void)runScheduleForeverInNewThread;
{
    [NSThread detachNewThreadSelector:@selector(runScheduleForeverInCurrentThread) toTarget:self withObject:nil];
}

- (void)runScheduleForeverInCurrentThread;
{
    @autoreleasepool {
        [self runScheduleInCurrentThreadUntilEmpty:NO];
        NSLog(@"Did I not say 'Forever'?"); // Nobody lives forever. On the other hand, tomorrow never dies. Never say never again, though. GOOOOOLDFINGER!
    }
}

// OFScheduler subclass

- (void)scheduleEvents;
{
    [self notifyDedicatedThreadIfFirstEventIsSoonerThanWakeDate];
}

- (void)cancelScheduledEvents;
{
    // No need to wake our dedicated thread, that'll just make it consume CPU sooner than it was already planning to do (when it was going to wake up to process the event).
}

#pragma mark - NSObject (OBExtensions)

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;
    NSDate *date;
    
    debugDictionary = [super debugDictionary];
    if (scheduleConditionLock)
        [debugDictionary setObject:scheduleConditionLock forKey:@"scheduleConditionLock"];
    if ((date = [self wakeDate]))
        [debugDictionary setObject:date forKey:@"wakeDate"];

    return debugDictionary;
}

#pragma mark - Private

- (void)_systemClockChanged:(NSNotification *)note;
{
    [self scheduleEvents];
}

- (void)notifyDedicatedThreadIfFirstEventIsSoonerThanWakeDate;
{
    NSDate *dateOfFirstEvent = [self dateOfFirstEvent];
    NSDate *currentWakeDate = [self wakeDate];

    // The first part of this condition is fairly straightforward:  if the first scheduled event is before the current wake date, we notify the dedicated thread that it needs to wake sooner.

    // The last condition is a little more subtle:  when the user changes the system clock, it can skip right past something which was originally scheduled to fire hours in the "future", since sleep times appear to be relative rather than absolute.  This can block new events which are supposed to fire in fractions of a second, so we test here to see if the currentWakeDate is already in the past (and if so we notify the dedicated thread that it needs to wake sooner).  A better solution would be to track system clock changes and guarantee that -notifyDedicatedThreadThatItNeedsToWakeSooner will get called whenever the system clock jumps forward.
    if (dateOfFirstEvent != nil && (currentWakeDate == nil || [dateOfFirstEvent isBeforeDate:currentWakeDate] || [currentWakeDate timeIntervalSinceNow] < 0.0)) {
        [self notifyDedicatedThreadThatItNeedsToWakeSooner];
    }
}

- (void)notifyDedicatedThreadThatItNeedsToWakeSooner;
{
    // Set the scheduleConditionLock to the 'changed' state if it isn't already
    if ([scheduleConditionLock tryLockWhenCondition:SCHEDULE_STABLE_CONDITION]) {
        // Schedule was in 'stable' state, set it to 'changed' state
        [scheduleConditionLock unlockWithCondition:SCHEDULE_CHANGED_CONDITION];
    }
}

- (void)mainThreadInvokeScheduledEvents;
{
    [mainThreadSynchronizationLock lockWhenCondition:MAIN_THREAD_BUSY];
    @try {
        [self invokeScheduledEvents];
    } @finally {
        [mainThreadSynchronizationLock unlockWithCondition:MAIN_THREAD_IDLE];
    }
}

#define MINIMUM_SLEEP_INTERVAL (1.0 / 120.0)

- (void)runScheduleInCurrentThreadUntilEmpty:(BOOL)onlyUntilEmpty;
{
    BOOL continueRunning = YES;

    OBRetainAutorelease(self);

    while (continueRunning) {
        @autoreleasepool {
            // Reset the scheduleConditionLock to the 'stable' state if it isn't already
            if ([scheduleConditionLock tryLockWhenCondition:SCHEDULE_CHANGED_CONDITION]) {
                [scheduleConditionLock unlockWithCondition:SCHEDULE_STABLE_CONDITION];
            }
            NSDate *dateOfFirstEvent = [self dateOfFirstEvent];
            if (dateOfFirstEvent == nil) {
                if (!onlyUntilEmpty)
                    dateOfFirstEvent = [NSDate distantFuture];
            } else {
                if ([dateOfFirstEvent timeIntervalSinceNow] < MINIMUM_SLEEP_INTERVAL)
                    dateOfFirstEvent = [NSDate dateWithTimeIntervalSinceNow:MINIMUM_SLEEP_INTERVAL];
            }

            [self setWakeDate:dateOfFirstEvent];

            if (dateOfFirstEvent != nil) {
                if (OFSchedulerDebug)
                    NSLog(@"%@: Sleeping %5.3f seconds until %@", [self shortDescription], [dateOfFirstEvent timeIntervalSinceNow], [dateOfFirstEvent description]);

                if ([scheduleConditionLock lockWhenCondition:SCHEDULE_CHANGED_CONDITION beforeDate:dateOfFirstEvent]) {
                    if (OFSchedulerDebug)
                        NSLog(@"%@: Schedule changed", [self shortDescription]);

                    // Schedule changed, get the updated date of first event
                    dateOfFirstEvent = [self dateOfFirstEvent];
                    [scheduleConditionLock unlockWithCondition:SCHEDULE_STABLE_CONDITION];

                    if (dateOfFirstEvent != nil && [dateOfFirstEvent timeIntervalSinceNow] <= 0.0) {
                        // The first event is ready to be invoked
                        [self synchronouslyInvokeScheduledEvents];
                    }
                } else {
                    NSTimeInterval firstEventInterval = [dateOfFirstEvent timeIntervalSinceNow];
		    // One might expect that the following assertion (now commented out) would always be valid:  after all, we just called -lockWhenCondition:beforeDate: and we didn't lock, so that means we reached our timeout--shouldn't that date actually be in the past?  But in fact, what we've found is that this asserts quite frequently (starting with 10.2 or so), so I'm disabling the assertion and we'll just test for the problem with the following while loop.
                    // OBASSERT(firstEventInterval <= 1e-3);
                    while (firstEventInterval > 0.0) {
			// We woke up too early:  since our first scheduled event is in the future, -synchronouslyInvokeScheduledEvents won't find any events, and we'll end up back at the top of the loop, not really sleeping, and thus chewing CPU constantly until the event actually does fire.  Let's try an alternate means of sleeping:  -[NSDate(OFExtensions) sleepUntilDate] (which calls +[NSThread sleepUntilDate:]).
                        if (OFSchedulerDebug)
                            NSLog(@"%@: Woke up %5.3f (%g) seconds too early, sleeping until %@", [self shortDescription], firstEventInterval, firstEventInterval, dateOfFirstEvent);
                        if (firstEventInterval < 1.0) {
                            // We're quite close to the first event's date, let's try sleeping until that precise date.
                            [dateOfFirstEvent sleepUntilDate];
                            firstEventInterval = [dateOfFirstEvent timeIntervalSinceNow];
                        } else {
			    // We woke up more than a second early.  Let's sleep for just one second, because someone might schedule another event between now and when our current event is scheduled to fire.  (Of course, this does mean that we won't look at any newly scheduled events for the next second.)
                            [[NSDate dateWithTimeIntervalSinceNow:1.0] sleepUntilDate];
                            break;
                        }
                    }
                    [self synchronouslyInvokeScheduledEvents];
                }

            } else {
                continueRunning = NO;
            }
        }
    }
    // -run never exits unless an exception is raised
}

- (void)synchronouslyInvokeScheduledEvents;
{
    // Synchronously invoke the events, whichever the thread
    if (flags.invokesEventsInMainThread) {
        [mainThreadSynchronizationLock lock];
        [mainThreadSynchronizationLock unlockWithCondition:MAIN_THREAD_BUSY];
        [self mainThreadPerformSelector:@selector(mainThreadInvokeScheduledEvents)];
        [mainThreadSynchronizationLock lockWhenCondition:MAIN_THREAD_IDLE];
        [mainThreadSynchronizationLock unlock];
    } else {
        [self invokeScheduledEvents];
    }
}

- (NSDate *)wakeDate;
{
    NSDate *savedWakeDate;

    [wakeDateLock lock];
    savedWakeDate = [wakeDate retain];
    [wakeDateLock unlock];
    return [savedWakeDate autorelease];
}

- (void)setWakeDate:(NSDate *)newWakeDate;
{
    [wakeDateLock lock];
    [wakeDate release];
    wakeDate = [newWakeDate retain];
    [wakeDateLock unlock];
}

@end
