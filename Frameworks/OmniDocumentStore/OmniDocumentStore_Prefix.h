// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>

#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFUTI.h>


#if 0 && defined(DEBUG)
    #define DEBUG_STORE_ENABLED 1
    #define DEBUG_STORE(format, ...) NSLog(@"DOC STORE: " format, ## __VA_ARGS__)
#else
    #define DEBUG_STORE_ENABLED 0
    #define DEBUG_STORE(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_METADATA(format, ...) NSLog(@"METADATA: " format, ## __VA_ARGS__)
#else
    #define DEBUG_METADATA(format, ...)
#endif

