// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
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

#import <OmniAppKit/OAController.h>
@interface OATestController : OAController
#if defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
<NSApplicationDelegate>
#endif
@end
