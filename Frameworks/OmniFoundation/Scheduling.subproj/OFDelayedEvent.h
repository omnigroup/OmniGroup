// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/Scheduling.subproj/OFDelayedEvent.h 68913 2005-10-03 19:36:19Z kc $

#import <OmniFoundation/OFObject.h>
#import <Foundation/NSDate.h>

@class NSLock;
@class OFInvocation, OFScheduler, OFScheduledEvent;

@interface OFDelayedEvent : OFObject
{
    NSLock           *lock;
    OFInvocation     *invocation;
    NSTimeInterval    delayInterval;
    BOOL              fireOnTermination;
    OFScheduler      *scheduler;
    
    OFScheduledEvent *scheduledEvent;
}

- initWithInvocation:(OFInvocation *)anInvocation delayInterval:(NSTimeInterval)aDelayInterval scheduler:(OFScheduler *)aScheduler fireOnTermination:(BOOL)shouldFireOnTermination;
- initWithInvocation:(OFInvocation *)anInvocation delayInterval:(NSTimeInterval)aDelayInterval;

- initForObject:(id)anObject selector:(SEL)aSelector withObject:(id)aWithObject delayInterval:(NSTimeInterval)aDelayInterval scheduler:(OFScheduler *)aScheduler fireOnTermination:(BOOL)shouldFireOnTermination;
- initForObject:(id)anObject selector:(SEL)aSelector withObject:(id)aWithObject delayInterval:(NSTimeInterval)aDelayInterval;

- (OFInvocation *)invocation;
- (NSTimeInterval)delayInterval;
- (NSDate *)pendingDate;
- (NSDate *)fireDate;
- (OFScheduler *)scheduler;
- (BOOL) fireOnTermination;

- (BOOL) isPending;
- (BOOL) invokeIfPending;
- (BOOL) cancelIfPending;

- (void) invokeLater;

@end
