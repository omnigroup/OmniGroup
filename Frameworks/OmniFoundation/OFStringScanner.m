// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFStringScanner.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniFoundation/OFStringScanner.m 93428 2007-10-25 16:36:11Z kc $")

@implementation OFStringScanner

- initWithString:(NSString *)aString;
{
    if ([super init] == nil)
	return nil;

    targetString = [aString retain];
    [self fetchMoreDataFromString:aString];

    return self;
}

- (void)dealloc;
{
    [targetString release];
    [super dealloc];
}

@end


