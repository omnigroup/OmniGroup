// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import "OFTestCase.h"

@interface OATestCase : OFTestCase
// This just has some +initialize crud to make this (hopefully) run better
@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniAppKit/OAController.h>
#import <AppKit/NSApplication.h>
@interface OATestController : OAController <NSApplicationDelegate>
@end
#endif

