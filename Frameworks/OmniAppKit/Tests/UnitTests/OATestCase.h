// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Tests/UnitTests/OATestCase.h 102862 2008-07-15 05:14:37Z bungi $

#import "OFTestCase.h"

@interface OATestCase : OFTestCase
// This just has some +initialize crud to make this (hopefully) run better
@end

#import <OmniAppKit/OAController.h>
@interface OATestController : OAController
@end
