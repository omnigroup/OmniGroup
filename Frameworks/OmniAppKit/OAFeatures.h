// Copyright 2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if !defined(MAC_OS_X_VERSION_10_7) || MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_7
    #define OA_USE_COLOR_MANAGER 1
    #define OA_INTERNET_CONFIG_ENABLED 1
#else
    #define OA_USE_COLOR_MANAGER 0 // Deprecated in 10.7
    #define OA_INTERNET_CONFIG_ENABLED 0
#endif
