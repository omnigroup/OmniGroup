// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSToolbarItem-OAExtensions.h"

#import <Foundation/Foundation.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/OpenStepExtensions.subproj/NSToolbarItem-OAExtensions.m 68913 2005-10-03 19:36:19Z kc $");

@implementation NSToolbarItem (OAExtensions)

/*
These methods allow you to call the same labelling selectors on toolbar items as on menu items.  This can make menu validation/toolbar validation code simpler.
*/
- (NSString *) title;
{
    return [self label];
}

- (void) setTitle: (NSString *) title;
{
    [self setLabel: title];
}

@end
