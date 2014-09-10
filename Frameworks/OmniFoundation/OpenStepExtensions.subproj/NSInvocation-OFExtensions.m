// Copyright 1997-2005, 2007, 2010-2011, 2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSInvocation-OFExtensions.h>

#import <OmniBase/objc.h>

RCS_ID("$Id$")

@implementation NSInvocation (OFExtensions)

+ (NSInvocation *)invocationWithTarget:(id)target action:(SEL)action;
{
    OBPRECONDITION(target != nil);
    OBPRECONDITION([target respondsToSelector:action]);

    NSMethodSignature *methodSignature = [target methodSignatureForSelector:action];
    NSInvocation *invocation = [self invocationWithMethodSignature:methodSignature];
    [invocation setTarget:target];
    [invocation setSelector:action];

    OBPOSTCONDITION(invocation != nil);
    return invocation;
}

- (BOOL)isDefinedByProtocol:(Protocol *)aProtocol
{
    OBRequestConcreteImplementation(self, _cmd); // protocol_getMethodDescription has no documentation, so I'm guessing at how it works (particularly the 'isRequiredMethod' argument and the result).
#if 0
    SEL invocationSelector = [self selector];

    struct objc_method_description desc = protocol_getMethodDescription(aProtocol, invocationSelector, YES /*isRequiredMethod*/, YES/*isInstanceMethod*/);
    return desc.name != NULL;
#endif
}

@end
