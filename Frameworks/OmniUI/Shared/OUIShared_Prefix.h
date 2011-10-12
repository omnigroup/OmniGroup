// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if 0 && defined(DEBUG)
    #define DEBUG_VERSIONS(format, ...) NSLog(@"FILE VERSION: " format, ## __VA_ARGS__)
    #define DEBUG_VERSIONS_ENABLED 1
#else
    #define DEBUG_VERSIONS(format, ...)
    #define DEBUG_VERSIONS_ENABLED 0
#endif


