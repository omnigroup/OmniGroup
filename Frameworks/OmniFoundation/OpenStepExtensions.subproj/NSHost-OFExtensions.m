// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSHost-OFExtensions.h>

#import <OmniBase/system.h>

RCS_ID("$Id$")

@implementation NSHost (OFExtensions)

- (NSNumber *)addressNumber
{
    return [NSNumber numberWithUnsignedLong:inet_addr([[self address] UTF8String])];
}

@end
