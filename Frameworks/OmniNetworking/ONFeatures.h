// Copyright 1997-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

// This header has gone missing in 10.6, but AF_APPLETALK is still there.
#if !defined(MAC_OS_X_VERSION_10_6) || (MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_6)
    #define ON_SUPPORT_APPLE_TALK 1
#else
    #define ON_SUPPORT_APPLE_TALK 0
#endif

