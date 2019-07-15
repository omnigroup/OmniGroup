// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#error OFFileUtilities are currently Mac-only
#endif

@class NSString;

NSString *OFUnsandboxedHomeDirectory(void);
