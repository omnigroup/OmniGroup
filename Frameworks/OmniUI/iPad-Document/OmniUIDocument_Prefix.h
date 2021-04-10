// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSArray-OFExtensions.h>

#if 0 && defined(DEBUG)
    #define DEBUG_PREVIEW_DISPLAY(format, ...) NSLog(@"PREVIEW: " format, ## __VA_ARGS__)
#else
    #define DEBUG_PREVIEW_DISPLAY(format, ...)
#endif

OB_HIDDEN extern NSInteger OUIDocumentPreviewGeneratorDebug;
#define DEBUG_PREVIEW_GENERATION(level, format, ...) do { \
    if (OUIDocumentPreviewGeneratorDebug >= (level)) \
        NSLog(@"PREVIEW: " format, ## __VA_ARGS__); \
    } while (0)

OB_HIDDEN extern NSInteger OUIApplicationLaunchDebug;
#define DEBUG_LAUNCH(level, format, ...) do { \
    if (OUIApplicationLaunchDebug >= (level)) \
        NSLog(@"APP: " format, ## __VA_ARGS__); \
    } while (0)

#if 0 && defined(DEBUG)
    #define DEBUG_DOCUMENT_DEFINED 1
    #define DEBUG_DOCUMENT(format, ...) NSLog(@"DOCUMENT: " format, ## __VA_ARGS__)
#else
    #define DEBUG_DOCUMENT_DEFINED 0
    #define DEBUG_DOCUMENT(format, ...)
#endif


static inline void main_async(void (^block)(void)) {
    dispatch_async(dispatch_get_main_queue(), block);
}
static inline void main_sync(void (^block)(void)) {
    if ([NSThread isMainThread])
        block(); // else we'll deadlock since dispatch_sync doesn't check for this
    else
        dispatch_sync(dispatch_get_main_queue(), block);
}
