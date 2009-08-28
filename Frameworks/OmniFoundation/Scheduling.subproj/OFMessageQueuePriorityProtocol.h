// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#define OFInvocationNoGroup 0

enum {
    OFHighPriority = 100, OFMediumPriority = 800, OFLowPriority = 1600,
};

typedef struct {
    void *group;
    unsigned int priority:16;
    unsigned int maximumSimultaneousThreadsInGroup:8;
    unsigned int _private:8; // Input ignored, used internally to hold state
} OFMessageQueueSchedulingInfo;

#define OFMessageQueueSchedulingInfoDefault ((OFMessageQueueSchedulingInfo){.group = NULL, .priority = OFMediumPriority, .maximumSimultaneousThreadsInGroup = 255})

@protocol OFMessageQueuePriority
- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
@end

@interface NSObject (OFInvocationPriority)
- (unsigned int)fixedPriorityForSelector:(SEL)aSelector;
@end
