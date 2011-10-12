// Copyright 2010-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

// NSFileWrapper is finally making its long overdue migration to Foundation
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || (defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    #import <Foundation/NSFileWrapper.h>
#else
    #import <AppKit/NSFileWrapper.h>
#endif
