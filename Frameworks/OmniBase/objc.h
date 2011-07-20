// Copyright 2007-2011 Omni Development, Inc. All rights reserved.
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

#ifndef __has_feature
        #define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

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

#if !defined(CF_CONSUMED)
    #if __has_feature(attribute_cf_consumed)
        #define CF_CONSUMED __attribute__((cf_consumed))
    #else
        #define CF_CONSUMED
    #endif
#endif
