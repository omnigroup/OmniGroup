// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

#import "OUIShared_Prefix.h"

typedef struct {
    NSInteger value;
    CFStringRef name;
} OUIEnumName;

__private_extern__ const OUIEnumName OUITextDirectionEnumNames[], OUITextSelectionGranularityNames[];
__private_extern__ NSString *OUINameOfEnum(NSInteger v, const OUIEnumName *ns);

#define OUITextDirectionName(d) OUINameOfEnum(d, OUITextDirectionEnumNames)
#define OUISelectionGranularityName(g) OUINameOfEnum(g, OUITextSelectionGranularityNames)

static inline void main_async(void (^block)(void)) {
    dispatch_async(dispatch_get_main_queue(), block);
}
static inline void main_sync(void (^block)(void)) {
    if ([NSThread isMainThread])
        block(); // else we'll deadlock since dispatch_sync doesn't check for this
    else
        dispatch_sync(dispatch_get_main_queue(), block);
}


#if 0 && defined(DEBUG)
    #define PREVIEW_DEBUG(format, ...) NSLog(@"PREVIEW: " format, ## __VA_ARGS__)
#else
    #define PREVIEW_DEBUG(format, ...)
#endif

#if 0 && defined(DEBUG)
    #define DEBUG_DOCUMENT(format, ...) NSLog(@"DOCUMENT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_DOCUMENT(format, ...)
#endif

#endif
