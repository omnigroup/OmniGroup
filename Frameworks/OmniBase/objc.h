// Copyright 2007-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AvailabilityMacros.h>
#import <TargetConditionals.h>
#import <Foundation/NSObjCRuntime.h>
#import <objc/runtime.h>
#import <objc/message.h>

// These aren't defined in iPhone OS 3.2, but we want to use them unconditionally.
#if !defined(NS_RETURNS_RETAINED)
    #if defined(__clang__)
        #define NS_RETURNS_RETAINED __attribute__((ns_returns_retained))
    #else
        #define NS_RETURNS_RETAINED
    #endif
#endif

#import <CoreFoundation/CFBase.h>

#if !defined(CF_RETURNS_RETAINED)
    #if defined(__clang__)
        #define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
    #else
        #define CF_RETURNS_RETAINED
    #endif
#endif
