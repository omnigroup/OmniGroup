// Copyright 2008-2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

// The document store classes depend on 10.7 or iOS 5 for NSFileCoordinator/NSFilePresenter, etc. We require iOS 5 on the trunk, so we don't check the iOS version.
#if (defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE) || (defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7)
    #define OFS_DOCUMENT_STORE_SUPPORTED 1
#else
    #define OFS_DOCUMENT_STORE_SUPPORTED 0
#endif


