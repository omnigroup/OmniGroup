// Copyright 1997-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSData-OBObjectCompatibility.h>

#import <OmniBase/rcsid.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/NSData-OBObjectCompatibility.m 98221 2008-03-04 21:06:19Z kc $")

@implementation NSData (OBObjectCompatibility)

static const unsigned int NSDataShortDescriptionLength = 40;

- (NSString *)shortDescription;
{
    NSString *description = [self description];
    if ([description length] <= NSDataShortDescriptionLength)
	return description;
    return [[description substringToIndex:NSDataShortDescriptionLength] stringByAppendingString:@"..."];
}

@end

