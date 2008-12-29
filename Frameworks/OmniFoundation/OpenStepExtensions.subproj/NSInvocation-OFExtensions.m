// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSInvocation-OFExtensions.h>

// This is not included in OmniBase.h since system.h shouldn't be used except when covering OS specific behaviour
#import <OmniBase/system.h>
#import <objc/Protocol.h>

RCS_ID("$Id$")

@implementation NSInvocation (OFExtensions)

- (BOOL)isDefinedByProtocol:(Protocol *)aProtocol
{
    SEL invocationSelector = [self selector];

#if !defined(MAC_OS_X_VERSION_10_5) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    return ([aProtocol descriptionForInstanceMethod:invocationSelector] != nil);
#else
    OBRequestConcreteImplementation(self, _cmd); // protocol_getMethodDescription has no documentation, so I'm guessing at how it works (particularly the 'isRequiredMethod' argument and the result).
    struct objc_method_description desc = protocol_getMethodDescription(aProtocol, invocationSelector, YES /*isRequiredMethod*/, YES/*isInstanceMethod*/);
    return desc.name != NULL;
#endif
}

@end
