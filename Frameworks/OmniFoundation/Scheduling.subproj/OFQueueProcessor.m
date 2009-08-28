// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFQueueProcessor.h>

#import <OmniFoundation/NSThread-OFExtensions.h>
#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFMessageQueue.h>

#import <Foundation/NSPort.h>

RCS_ID("$Id$")

@interface OFQueueProcessor (Private)
- (BOOL)shouldProcessQueueEnd;
- (void)processQueueInThread;
@end

BOOL OFQueueProcessorDebug = NO;

@implementation OFQueueProcessor

static NSConditionLock *detachThreadLock;
static OFQueueProcessor *detachingQueueProcessor;

+ (void)initialize;
{
    OBINITIALIZE;

    detachThreadLock = [[NSConditionLock alloc] init];
    detachingQueueProcessor = nil;

    // This will trigger +[NSPort initialize], which registers for the NSBecomingMultiThreaded notification and avoids a race condition between NSThread and NSPort.
    [NSPort class];
}

- initForQueue:(OFMessageQueue *)aQueue;
{
    if (![super init])
	return nil;

    messageQueue = [aQueue retain];
    currentInvocationLock = [[NSLock alloc] init];

    return self;
}

- (void)dealloc;
{
    [messageQueue release];
    [currentInvocationLock release];
    [super dealloc];
}

- (void)processQueueUntilEmpty:(BOOL)onlyUntilEmpty;
{
    // TJW -- Bug #332 about why this time check is here by default
    [self processQueueUntilEmpty:onlyUntilEmpty forTime:(0.25)];
}

- (void)processQueueUntilEmpty:(BOOL)onlyUntilEmpty forTime:(NSTimeInterval)maximumTime;
{
    OFInvocation *retainedInvocation;
    BOOL waitForMessages = !onlyUntilEmpty;
    NSAutoreleasePool *autoreleasePool;
    NSTimeInterval startingInterval, endTime;
    
    startingInterval = [NSDate timeIntervalSinceReferenceDate];
    endTime = ( maximumTime >= 0 ) ? startingInterval + maximumTime : startingInterval;
    autoreleasePool = [[NSAutoreleasePool alloc] init];
    
    if (detachingQueueProcessor == self) {
        detachingQueueProcessor = nil;
        [detachThreadLock lock];
        [detachThreadLock unlockWithCondition:0];
    }

    if (OFQueueProcessorDebug)
        NSLog(@"%@: processQueueUntilEmpty: %d", [self shortDescription], onlyUntilEmpty);
        
    while ((retainedInvocation = [messageQueue copyNextInvocationWithBlock:waitForMessages])) {
        [currentInvocationLock lock];
        currentInvocation = retainedInvocation;
        schedulingInfo = [currentInvocation messageQueueSchedulingInfo];
        [currentInvocationLock unlock];
        
        if (OFQueueProcessorDebug) {
            NSLog(@"%@: invoking %@", [self shortDescription], [retainedInvocation shortDescription]);
        }

        NS_DURING {
            [retainedInvocation invoke];
        } NS_HANDLER {
            NSLog(@"%@: %@", [retainedInvocation shortDescription], [localException reason]);
        } NS_ENDHANDLER;

        if (OFQueueProcessorDebug) {
	    NSLog(@"%@: finished %@", [self shortDescription], [retainedInvocation shortDescription]);
        }

        [currentInvocationLock lock];
        currentInvocation = nil;
        schedulingInfo = OFMessageQueueSchedulingInfoDefault;
        [currentInvocationLock unlock];

        [retainedInvocation release];

        if (maximumTime >= 0) {
            // TJW -- Bug #332 about why this time check is here
            if (endTime < [NSDate timeIntervalSinceReferenceDate])
                break;
        }
        
        if (waitForMessages) {
            [autoreleasePool release];
            autoreleasePool = [[NSAutoreleasePool alloc] init];
        } else {
            if ([self shouldProcessQueueEnd])
                break;
        }
    }

    if (OFQueueProcessorDebug)
        NSLog(@"%@: processQueueUntilEmpty: (exiting)", [self shortDescription]);
        
    
    [autoreleasePool release];
}

- (void)processQueueUntilEmpty;
{
    [self processQueueUntilEmpty:YES];
}

- (void)processQueueForever;
{
    [self processQueueUntilEmpty:NO];
}

- (void)startProcessingQueueInNewThread;
{
    [detachThreadLock lockWhenCondition:0];
    [detachThreadLock unlockWithCondition:1];
    [NSThread detachNewThreadSelector:@selector(processQueueInThread) toTarget:self withObject:nil];
}

- (OFMessageQueueSchedulingInfo)schedulingInfo;
{
    OFMessageQueueSchedulingInfo currentSchedulingInfo;

    [currentInvocationLock lock];
    currentSchedulingInfo = schedulingInfo;
    [currentInvocationLock unlock];

    return currentSchedulingInfo;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:messageQueue forKey:@"messageQueue"];
    return debugDictionary;
}

@end

@implementation OFQueueProcessor (Private)

- (BOOL)shouldProcessQueueEnd;
{
    return NO;
}

- (void)processQueueInThread;
{
    detachingQueueProcessor = self;
    for (;;) {
        NS_DURING {
            [self processQueueForever];
        } NS_HANDLER {
            NSLog(@"%@", [localException reason]);
        } NS_ENDHANDLER;
    }
}

@end
