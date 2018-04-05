// Copyright 1997-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFConcreteInvocation.h>

RCS_ID("$Id$")

#import <OmniFoundation/OFMessageQueuePriorityProtocol.h>

static void getSchedulingInfo(OFMessageQueueSchedulingInfo *returnValue, id target)
{
    if (returnValue->_private == 0) {
        if ([target respondsToSelector:@selector(messageQueueSchedulingInfo)]) {
            *returnValue = [(id <OFMessageQueuePriority>)target messageQueueSchedulingInfo];
            if (returnValue->maximumSimultaneousThreadsInGroup < 1)
                returnValue->maximumSimultaneousThreadsInGroup = 1;
        } else {
            *returnValue = OFMessageQueueSchedulingInfoDefault;
        }
        returnValue->_private = 1;
    }
}


@implementation OFConcreteInvocation

- initForObject:(id <NSObject>)targetObject;
{
    OBPRECONDITION(targetObject != nil); // since we are going to dereference it below

    if (!(self = [super init]))
        return nil;

    object = [targetObject retain];
    
    return self;
}

- (void)dealloc;
{
    [object release];
    [super dealloc];
}

// OFInvocation subclass

- (id <NSObject>)object;
{
    return object;
}

// OFMessageQueuePriority protocol

- (OFMessageQueueSchedulingInfo)messageQueueSchedulingInfo;
{
    getSchedulingInfo(&schedulingInfo, object);
    return schedulingInfo;
}

@end


#import <OmniFoundation/OFIObjectNSInvocation.h>
#import <OmniFoundation/OFIObjectSelector.h>
#import <OmniFoundation/OFIObjectSelectorBool.h>
#import <OmniFoundation/OFIObjectSelectorInt.h>
#import <OmniFoundation/OFIObjectSelectorIntInt.h>
#import <OmniFoundation/OFIObjectSelectorObject.h>
#import <OmniFoundation/OFIObjectSelectorObjectInt.h>
#import <OmniFoundation/OFIObjectSelectorObjectObject.h>
#import <OmniFoundation/OFIObjectSelectorObjectObjectObject.h>

@implementation OFInvocation (Inits)

- initForObject:(id <NSObject>)targetObject nsInvocation:(NSInvocation *)anInvocation;
{
    [self release];
    return [[OFIObjectNSInvocation alloc] initForObject:targetObject nsInvocation:anInvocation];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector;
{
    [self release];
    return [[OFIObjectSelector alloc] initForObject:targetObject selector:aSelector];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withBool:(BOOL)aBool;
{
    [self release];
    return [[OFIObjectSelectorBool alloc] initForObject:targetObject selector:aSelector withBool:aBool];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withInt:(int)anInt;
{
    [self release];
    return [[OFIObjectSelectorInt alloc] initForObject:targetObject selector:aSelector withInt:anInt];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withInt:(int)anInt withInt:(int)anotherInt;
{
    [self release];
    return [[OFIObjectSelectorIntInt alloc] initForObject:targetObject selector:aSelector withInt:anInt withInt:anotherInt];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withObject:(id <NSObject>)aWithObject;
{
    [self release];
    return [[OFIObjectSelectorObject alloc] initForObject:targetObject selector:aSelector withObject:aWithObject];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withObject:(id <NSObject>)anObject withInt:(int)anInt;
{
    [self release];
    return [[OFIObjectSelectorObjectInt alloc] initForObject:targetObject selector:aSelector withObject:anObject withInt:anInt];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2;
{
    [self release];
    return [[OFIObjectSelectorObjectObject alloc] initForObject:targetObject selector:aSelector withObject:object1 withObject:object2];
}

- initForObject:(id <NSObject>)targetObject selector:(SEL)aSelector withObject:(id <NSObject>)object1 withObject:(id <NSObject>)object2 withObject:(id <NSObject>)object3;
{
    [self release];
    return [[OFIObjectSelectorObjectObjectObject alloc] initForObject:targetObject selector:aSelector withObject:object1 withObject:object2 withObject:object3];
}

@end
