// Copyright 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#define HAS_REMOVEOBSERVER_FORKEYPATH_CONTEXT \
    ((!TARGET_OS_IPHONE && defined(MAC_OS_X_VERSION_10_7) && MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_7) || (TARGET_OS_IPHONE && defined(__IPHONE_5_0) && __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_5_0))
