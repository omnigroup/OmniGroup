// Copyright 2009-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

/* In 10.7, Apple deprecated all existing crypto APIs and replaced them with new, completely different APIs which aren't available on previous versions (and which aren't as functional). */
#if !defined(OF_ENABLE_CDSA) // OFCDSAUtilities.m overrides this
    #if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        #define OF_ENABLE_CDSA 0
    #else
        #define OF_ENABLE_CDSA 0
    #endif
#endif
