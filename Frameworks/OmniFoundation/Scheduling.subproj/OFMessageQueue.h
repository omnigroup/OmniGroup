// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>

@class NSConditionLock, NSLock, NSMutableArray, NSMutableSet;
@class OFInvocation;

#import <OmniFoundation/OFMessageQueueDelegateProtocol.h>

@interface OFMessageQueue : OFObject

+ (OFMessageQueue *)mainQueue;
    // The main message queue (often the one which is run from the appkit).  By default, it doesn't schedule queued messages by priority (unlike other queues).

// Configuration

- (void)setDelegate:(id <OFMessageQueueDelegate>)aDelegate;
- (void)startBackgroundProcessors:(NSUInteger)processorCount;
- (void)setSchedulesBasedOnPriority:(BOOL)shouldScheduleBasedOnPriority;

- (BOOL)hasInvocations;
- (OFInvocation *)copyNextInvocation;
- (OFInvocation *)copyNextInvocationWithBlock:(BOOL)shouldBlock;

- (void)addQueueEntry:(OFInvocation *)aQueueEntry;

- (void)queueInvocation:(NSInvocation *)anInvocation forObject:(id <NSObject>)anObject;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject;
- (void)queueSelectorOnce:(SEL)aSelector forObject:(id <NSObject>)anObject;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)withObject;
- (void)queueSelectorOnce:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)withObject;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2;
- (void)queueSelectorOnce:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2 withObject:(id <NSObject>)object3;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withBool:(BOOL)aBool;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withInt:(int)anInt;
- (void)queueSelector:(SEL)aSelector forObject:(id <NSObject>)anObject withInt:(int)anInt withInt:(int)anotherInt;

@end
