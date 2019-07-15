// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if 0 && defined(DEBUG)
    #define DEBUG_ANIMATION(format, ...) NSLog(@"ANIM: " format, ## __VA_ARGS__)
#else
    #define DEBUG_ANIMATION(format, ...)
#endif
