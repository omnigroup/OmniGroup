// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFInvocation.h>

#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>

@interface OFConcreteInvocation : OFInvocation
{
    id <NSObject> object;
    OFMessageQueueSchedulingInfo schedulingInfo;
}

- initForObject:(id <NSObject>)targetObject;

@end
