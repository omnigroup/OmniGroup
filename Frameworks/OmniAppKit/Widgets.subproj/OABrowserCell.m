// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OABrowserCell.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OABrowserCell.m 68913 2005-10-03 19:36:19Z kc $")

@implementation OABrowserCell

- (void) dealloc;
{
    [userInfo release];
    [super dealloc];
}

- (NSDictionary *) userInfo;
{
    return userInfo;
}

- (void)setUserInfo: (NSDictionary *) newInfo;
{
    if (userInfo != newInfo) {
	[userInfo release];
	userInfo = [newInfo copy];
    }
}

@end
