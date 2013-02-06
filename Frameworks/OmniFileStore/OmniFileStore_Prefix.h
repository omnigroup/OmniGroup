// Copyright 2008-2012 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniBase/OmniBase.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CFError.h>

// Common stuff we need from OmniFoundation
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSString-OFReplacement.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSMutableArray-OFExtensions.h>
#import <OmniFoundation/OFBindingPoint.h>

#if 0 && defined(DEBUG)
    #define DEBUG_STORE_ENABLED
    #define DEBUG_STORE(format, ...) NSLog(@"DOC STORE: " format, ## __VA_ARGS__)
#else
    #define DEBUG_STORE(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_METADATA(format, ...) NSLog(@"METADATA: " format, ## __VA_ARGS__)
#else
    #define DEBUG_METADATA(format, ...)
#endif

