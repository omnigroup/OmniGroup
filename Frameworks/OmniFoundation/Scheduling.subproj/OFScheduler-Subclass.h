// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFScheduler.h>

@interface OFScheduler ()
- (void)invokeScheduledEvents;
// Subclasses call this method to invoke all events scheduled to happen up to the current time
- (void)cancelScheduledEvents;
// Subclasses override this method to cancel their previously scheduled events.
@end

extern BOOL OFSchedulerDebug;
