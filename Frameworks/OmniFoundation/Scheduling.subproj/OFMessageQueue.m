// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFMessageQueue.h>

#import <OmniFoundation/OFInvocation.h>
#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>
#import <OmniFoundation/OFQueueProcessor.h>
#import <OmniFoundation/OFRunLoopQueueProcessor.h>
#import <Foundation/NSOperation.h>

RCS_ID("$Id$")

OB_REQUIRE_ARC

typedef enum {
    QUEUE_HAS_NO_SCHEDULABLE_INVOCATIONS, QUEUE_HAS_INVOCATIONS,
} OFMessageQueueState;

@implementation OFMessageQueue
{
    NSMutableArray *queue;
    NSMutableSet *queueSet;
    NSConditionLock *queueLock;
    
    __weak NSObject <OFMessageQueueDelegate> *_weak_delegate;
    
    NSLock *queueProcessorsLock;
    unsigned int idleProcessors;
    NSUInteger uncreatedProcessors;
    NSMutableArray *queueProcessors;
    
    struct {
        unsigned int schedulesBasedOnPriority;
    } flags;
}

static BOOL OFMessageQueueDebug = NO;

+ (OFMessageQueue *)mainQueue;
{
    static dispatch_once_t onceToken;
    static OFMessageQueue *mainQueue = nil;
    
    dispatch_once(&onceToken, ^{
        mainQueue = [[OFMessageQueue alloc] init];
        [mainQueue setSchedulesBasedOnPriority:NO];

        // If we are going to be queueing messages to the main queue, it needs a processor.
        // NOTE: This will call back to +mainQueue to pass the result to the queue processor's -initForQueue:. This is OK and needed in the case that the first call to +mainQueue is from a background thread.
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [OFRunLoopQueueProcessor mainThreadProcessor];
        }];
    });

    return mainQueue;
}

// Init and dealloc

- init;
{
    if (!(self = [super init]))
        return nil;

    queue = [[NSMutableArray alloc] init];
    queueLock = [[NSConditionLock alloc] initWithCondition:QUEUE_HAS_NO_SCHEDULABLE_INVOCATIONS];

    idleProcessors = 0;
    queueProcessorsLock = [[NSLock alloc] init];
    uncreatedProcessors = 0;
    queueProcessors = [[NSMutableArray alloc] init];
    flags.schedulesBasedOnPriority = YES;

    return self;
}

//

- (void)setDelegate:(id <OFMessageQueueDelegate>)aDelegate;
{
    OBPRECONDITION(aDelegate == nil || [(id)aDelegate conformsToProtocol:@protocol(OFMessageQueueDelegate)]);
    [queueLock lock];
    _weak_delegate = aDelegate;
    [queueLock unlock];
}

- (void)startBackgroundProcessors:(NSUInteger)processorCount;
{
    [queueProcessorsLock lock];
    uncreatedProcessors += processorCount;
    [queueProcessorsLock unlock];

    // Now, go ahead and start some (or all) of those processors to handle messages already queued
    [queueLock lock];
    [self _createProcessorsForQueueSize:[queue count]];
    [queueLock unlock];
}

- (void)setSchedulesBasedOnPriority:(BOOL)shouldScheduleBasedOnPriority;
{
    flags.schedulesBasedOnPriority = shouldScheduleBasedOnPriority;
}

//

- (BOOL)hasInvocations;
{
    BOOL hasInvocations;

    [queueLock lock];
    hasInvocations = [queue count] > 0;
    [queueLock unlock];
    return hasInvocations;
}

- (OFInvocation *)copyNextInvocation;
{
    return [self copyNextInvocationWithBlock:YES];
}

- (OFInvocation *)copyNextInvocationWithBlock:(BOOL)shouldBlock;
{
    NSUInteger invocationCount;
    OFInvocation *nextRetainedInvocation = nil;

    [queueLock lock];
    if ([queue count])
        [queueLock unlockWithCondition:QUEUE_HAS_INVOCATIONS];
    else
        [queueLock unlockWithCondition:QUEUE_HAS_NO_SCHEDULABLE_INVOCATIONS];
           
    do {
        NSUInteger invocationIndex;
        NSUInteger queueProcessorIndex, queueProcessorCount;

        if (shouldBlock) {
            [queueProcessorsLock lock];
            idleProcessors++;
            [queueProcessorsLock unlock];
            [queueLock lockWhenCondition:QUEUE_HAS_INVOCATIONS];
            [queueProcessorsLock lock];
            idleProcessors--;
            [queueProcessorsLock unlock];
        } else {
            [queueLock lock];
        }

        invocationCount = [queue count];
        if (invocationCount == 0) {
            OBASSERT(!shouldBlock);
            [queueLock unlock];
            return nil;
        }

        [queueProcessorsLock lock];

        queueProcessorCount = [queueProcessors count];
        OFMessageQueueSchedulingInfo currentGroupSchedulingInfo = OFMessageQueueSchedulingInfoDefault;
        unsigned int currentGroupThreadCount = 0;

        for (invocationIndex = 0; invocationIndex < invocationCount; invocationIndex++) {
            BOOL useCurrentInvocation;

            // get first invocation in queue
            OFInvocation *nextInvocation = [queue objectAtIndex:invocationIndex];
            OFMessageQueueSchedulingInfo schedulingInfo = [nextInvocation messageQueueSchedulingInfo];
            if (schedulingInfo.group == NULL || queueProcessorCount == 0) {  // Null group is special, and can use as many threads as it wants
                useCurrentInvocation = YES;
#ifdef DEBUG_kc0
                if (flags.schedulesBasedOnPriority) {
                    NSLog(@"-[%@ %@] invocation has no group: %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), [nextInvocation shortDescription]);
                }
                OBASSERT(!flags.schedulesBasedOnPriority); // If a message queue schedules based on priority, its invocations really should have priorities!
#endif
            } else {  // Check to see if this group already has used up all its allotted threads
                if (schedulingInfo.group != currentGroupSchedulingInfo.group) {
                    OBASSERT(schedulingInfo.maximumSimultaneousThreadsInGroup > 0);
                    currentGroupThreadCount = 0;
                    if (schedulingInfo.maximumSimultaneousThreadsInGroup >= queueProcessorCount) {
                        // This group is allowed as many threads as we have processors, so we don't need to bother counting the actual threads being spent on this group
                    } else {
                        for (queueProcessorIndex = 0; queueProcessorIndex < queueProcessorCount; queueProcessorIndex++) {
                            if (currentGroupThreadCount >= schedulingInfo.maximumSimultaneousThreadsInGroup)
                                break;
    
                            // Get group of object queue processer is working on
                            OFMessageQueueSchedulingInfo processorSchedulingInfo = [[queueProcessors objectAtIndex:queueProcessorIndex] schedulingInfo];
    
                            if (processorSchedulingInfo.group == schedulingInfo.group)
                                currentGroupThreadCount++;
                        }
                    }

                    currentGroupSchedulingInfo = schedulingInfo;
                }
                useCurrentInvocation = currentGroupThreadCount < currentGroupSchedulingInfo.maximumSimultaneousThreadsInGroup;
#ifdef DEBUG_kc0
                NSLog(@"useCurrentInvocation=%d group=%d groupThreadCount=%d maximumSimultaneousThreadsInGroup=%d", useCurrentInvocation, currentGroupSchedulingInfo.group, groupThreadCount, currentGroupSchedulingInfo.maximumSimultaneousThreadsInGroup, [nextInvocation shortDescription]);
#endif
            }

            if (useCurrentInvocation) {
                nextRetainedInvocation = nextInvocation;
                OBASSERT([queue objectAtIndex:invocationIndex] == nextInvocation);
                [queue removeObjectAtIndex:invocationIndex];
                if (queueSet)
                    [queueSet removeObject:nextInvocation];
                break;
            }
        }

        [queueProcessorsLock unlock];

        if (nextRetainedInvocation == nil || invocationCount == 1) {
            OBASSERT([queue count] == 0 || nextRetainedInvocation == nil);
            [queueLock unlockWithCondition:QUEUE_HAS_NO_SCHEDULABLE_INVOCATIONS];
        } else { // nextRetainedInvocation != nil && invocationCount != 1
            OBASSERT([queue count] != 0);
            [queueLock unlockWithCondition:QUEUE_HAS_INVOCATIONS];
        }

    } while (nextRetainedInvocation == nil);
    
    if (OFMessageQueueDebug)
        NSLog(@"[%@ nextRetainedInvocation] = %@, group = %p, priority = %d, maxThreads = %d", [self shortDescription], [nextRetainedInvocation shortDescription], [nextRetainedInvocation messageQueueSchedulingInfo].group, [nextRetainedInvocation messageQueueSchedulingInfo].priority, [nextRetainedInvocation messageQueueSchedulingInfo].maximumSimultaneousThreadsInGroup);
    return nextRetainedInvocation;
}

- (void)addQueueEntry:(OFInvocation *)aQueueEntry;
{
    OBPRECONDITION(aQueueEntry);
    if (!aQueueEntry)
        return;
    
#ifdef OW_DISALLOW_MULTI_THREADING
    if (self != [OFMessageQueue mainQueue]) {
	[[OFMessageQueue mainQueue] addQueueEntry: aQueueEntry];
	return;
    }
#endif

    if (OFMessageQueueDebug)
	NSLog(@"[%@ addQueueEntry:%@]", [self shortDescription], [aQueueEntry shortDescription]);

    // Log a backtrace buffer for the enqueue site of the delayed invocation (we also log one when it is invoked, so we can match up which one crashed and where it came from).
    OBRecordBacktraceWithSelectorAndContext(aQueueEntry.selector, (__bridge void *)aQueueEntry);

    [queueLock lock];

    NSUInteger queueCount = [queue count];
    BOOL wasEmpty = (queueCount == 0);
    id <OFMessageQueueDelegate> strongDelegate = _weak_delegate;
    
    NSUInteger entryIndex = queueCount;
    if (flags.schedulesBasedOnPriority) {
        // Figure out priority
        unsigned int priority = [aQueueEntry messageQueueSchedulingInfo].priority;
        OBASSERT(priority != 0);

        // Find spot at end of other entries with same priority
        while (entryIndex--) {
            OFInvocation *otherEntry;

            otherEntry = [queue objectAtIndex:entryIndex];
            if ([otherEntry messageQueueSchedulingInfo].priority <= priority)
                break;
        }
        entryIndex++;
    }

    // Insert object at entryIndex
    [queue insertObject:aQueueEntry atIndex:entryIndex];
    queueCount++;
    if (queueSet)
        [queueSet addObject:aQueueEntry];

    // Create new processor if needed and we can
    [self _createProcessorsForQueueSize:queueCount];

    [queueLock unlockWithCondition:QUEUE_HAS_INVOCATIONS];

    if (wasEmpty)
        [strongDelegate queueHasInvocations:self];
}

- (void)addQueueEntryOnce:(OFInvocation *)aQueueEntry;
{
    BOOL alreadyContainsObject;

    [queueLock lock];
    if (!queueSet)
	queueSet = [[NSMutableSet alloc] initWithArray:queue];
    alreadyContainsObject = [queueSet member:aQueueEntry] != nil;
    [queueLock unlock];
    if (!alreadyContainsObject)
	[self addQueueEntry:aQueueEntry];
}

- (void)queueInvocation:(NSInvocation *)anInvocation forObject:(id <NSObject>)anObject;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject nsInvocation:anInvocation];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelectorOnce:(SEL)aSelector forObject:(id <NSObject>)anObject;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector];
    [self addQueueEntryOnce:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)withObject;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:withObject];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelectorOnce:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)withObject;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:withObject];
    [self addQueueEntryOnce:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:object1 withObject:object2];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelectorOnce:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:object1 withObject:object2];
    [self addQueueEntryOnce:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2 withObject:(id <NSObject>)object3;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withObject:object1 withObject:object2 withObject:object3];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withBool:(BOOL)aBool;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withBool:aBool];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withInt:(int)anInt;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withInt:anInt];
    [self addQueueEntry:queueEntry];
}

- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withInt:(int)anInt withInt:(int)anotherInt;
{
    OFInvocation *queueEntry;

    if (!anObject)
        return;
    
    queueEntry = [[OFInvocation alloc] initForObject:anObject selector:aSelector withInt:anInt withInt:anotherInt];
    [self addQueueEntry:queueEntry];
}

// Debugging

+ (void)setDebug:(BOOL)shouldDebug;
{
    OFMessageQueueDebug = shouldDebug;
}

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;
    
    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:queue forKey:@"queue"];
    [debugDictionary setObject:[NSNumber numberWithInt:idleProcessors] forKey:@"idleProcessors"];
    [debugDictionary setObject:[NSNumber numberWithUnsignedInteger:uncreatedProcessors] forKey:@"uncreatedProcessors"];
    [debugDictionary setObject:flags.schedulesBasedOnPriority ? @"YES" : @"NO" forKey:@"flags.schedulesBasedOnPriority"];
    
    id <OFMessageQueueDelegate> strongDelegate = _weak_delegate;
    if (strongDelegate)
	[debugDictionary setObject:strongDelegate forKey:@"delegate"];
    
    return debugDictionary;
}

#pragma mark Private

- (void)_createProcessorsForQueueSize:(NSUInteger)queueCount;
{
    unsigned int projectedIdleProcessors;
    
    [queueProcessorsLock lock];
    projectedIdleProcessors = idleProcessors;
    while (projectedIdleProcessors < queueCount && uncreatedProcessors > 0) {
        OFQueueProcessor *newProcessor;
        
        newProcessor = [[OFQueueProcessor alloc] initForQueue:self];
        [newProcessor startProcessingQueueInNewThread];
        [queueProcessors addObject:newProcessor];
        uncreatedProcessors--;
        projectedIdleProcessors++;
    }
    [queueProcessorsLock unlock];
}

@end
