// Copyright 2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AvailabilityMacros.h>

// An NSTextFieldCell subclass that returns NSZeroRect from -expansionFrameWithFrame:inView:. If targeting 10.8 or higher, use -[NSControl setAllowsExpansionToolTips:] instead.

#if defined(MAC_OS_X_VERSION_MIN_REQUIRED) && MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_7

#import <AppKit/NSTextFieldCell.h>

@interface OANoExpansionFrameTextFieldCell : NSTextFieldCell
@end

#endif
