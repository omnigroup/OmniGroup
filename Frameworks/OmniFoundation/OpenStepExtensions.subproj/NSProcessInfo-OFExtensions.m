// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSProcessInfo-OFExtensions.h>

// This is not included in OmniBase.h since system.h shouldn't be used except when covering OS specific behaviour
#import <OmniBase/system.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OpenStepExtensions.subproj/NSProcessInfo-OFExtensions.m 90130 2007-08-15 07:15:53Z bungi $")

@implementation NSProcessInfo (OFExtensions)

- (NSNumber *)processNumber;
{
    // Don't assume the pid is 16 bits since it might be 32.
    return [NSNumber numberWithInt:getpid()];
}

@end
