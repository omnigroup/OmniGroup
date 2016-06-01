// Copyright 2002-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSAppleEventDescriptor-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation NSAppleEventDescriptor (OAExtensions)

+ (NSAppleEventDescriptor *)newDescriptorWithAEDescNoCopy:(const AEDesc *)aeDesc;
{
    return [[self alloc] initWithAEDescNoCopy:aeDesc];
}

@end

