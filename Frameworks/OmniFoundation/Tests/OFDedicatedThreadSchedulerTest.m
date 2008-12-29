// Copyright 2000-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFDedicatedThreadScheduler.h>

#import <OmniFoundation/NSDate-OFExtensions.h>

RCS_ID("$Id$")

@interface TestObject : NSObject
{
    unsigned int fireCount;
    NSTimeInterval lastFireDate;
    NSLock *fireLock;
}

- (void)scheduleFireMessages;
- (void)fire;

@end


@implementation TestObject

- init;
{
    if ([super init] == nil)
        return nil;
    lastFireDate = [NSDate timeIntervalSinceReferenceDate];
    fireLock = [[NSLock alloc] init];
    return self;
}

- (void)scheduleFireMessages;
{
    while (YES) {
        OMNI_POOL_START {
            OFScheduler *scheduler;
            unsigned int count;

            scheduler = [[[[[OFScheduler dedicatedThreadScheduler] subscheduler] subscheduler] subscheduler] subscheduler];
            [fireLock lock];
            fireCount = 0;
            [fireLock unlock];
            NSLog(@"GO");
            for (count = 0; count < 5000; count++) {
                NSAutoreleasePool *pool;
                
                pool = [[NSAutoreleasePool alloc] init];
                [scheduler scheduleSelector:@selector(fire) onObject:self withObject:nil afterTime:0.1];
                [pool release];
            }

            NSLog(@"Wait...");
            [[NSDate dateWithTimeIntervalSinceNow:0.1] sleepUntilDate];

            NSLog(@"STOP");
            [scheduler abortSchedule];
        } OMNI_POOL_END;
        OMNI_POOL_START {
            [fireLock lock];
            NSLog(@"Valid count = %d, last fired %f seconds ago", fireCount, [NSDate timeIntervalSinceReferenceDate] - lastFireDate);
            fireCount = 100000;
            [fireLock unlock];

            NSLog(@"Wait...");
            [[NSDate dateWithTimeIntervalSinceNow:5.0] sleepUntilDate];

            [fireLock lock];
            NSLog(@"Straggler count = %d, last fired %f seconds ago", fireCount - 100000, [NSDate timeIntervalSinceReferenceDate] - lastFireDate);
            fireCount = 0;
            [fireLock unlock];
        } OMNI_POOL_END;
    }
}

- (void)fire;
{
    NSLog(@"fire %d", fireCount);
    [fireLock lock];
    fireCount++;
    lastFireDate = [NSDate timeIntervalSinceReferenceDate];
    [fireLock unlock];
}

@end


int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool;
    TestObject *target;
    
    pool = [[NSAutoreleasePool alloc] init];
    [OBPostLoader processClasses];
    target = [[TestObject alloc] init];
    [NSThread detachNewThreadSelector:@selector(scheduleFireMessages) toTarget:target withObject:nil];
    [pool release];

    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantFuture]];
    return 0;
}
