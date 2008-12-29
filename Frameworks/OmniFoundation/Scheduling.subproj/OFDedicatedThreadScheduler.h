// Copyright 1999-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFScheduler.h>

@class NSConditionLock, NSLock;

@interface OFDedicatedThreadScheduler : OFScheduler
{
    NSConditionLock *scheduleConditionLock;
    NSConditionLock *mainThreadSynchronizationLock;
    NSDate *wakeDate;
    NSLock *wakeDateLock;
    struct {
        unsigned int invokesEventsInMainThread:1;
    } flags;
}

+ (OFDedicatedThreadScheduler *)dedicatedThreadScheduler;

- (void)setInvokesEventsInMainThread:(BOOL)shouldInvokeEventsInMainThread;
- (void)runScheduleForeverInNewThread;
- (void)runScheduleForeverInCurrentThread;

@end
