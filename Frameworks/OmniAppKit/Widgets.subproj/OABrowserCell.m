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

RCS_ID("$Id$")

@implementation OABrowserCell

- (void) dealloc;
{
    [_userInfo release];
    [super dealloc];
}

@synthesize userInfo = _userInfo;

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    OABrowserCell *copy = [super copyWithZone:zone];
    copy->_userInfo = [_userInfo copyWithZone:zone];
    return copy;
}

@end
