// Copyright 2011-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

// Deprecated in 10.7, but there is no replacement yet. In 10.11, the externs for the functions are gone entirely (though declaring them ourselves doesn't result in link errors, that's rather scary...)
#if defined(MAC_OS_X_VERSION_10_11) && MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_11
    #define OA_USE_COLOR_MANAGER 0
#else
    #define OA_USE_COLOR_MANAGER 1
#endif
