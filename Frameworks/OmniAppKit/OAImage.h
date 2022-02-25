// Copyright 2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#if OMNI_BUILDING_FOR_IOS || OMNI_BUILDING_FOR_MAC
#import <Foundation/NSBundle.h>
#import <OmniBase/OBBundle.h>
#endif

#if OMNI_BUILDING_FOR_IOS
#import <UIKit/UIImage.h>
#define OA_PLATFORM_IMAGE_CLASS UIImage
#endif

#if OMNI_BUILDING_FOR_MAC
#import <AppKit/NSImage.h>
#import <OmniAppKit/NSImage-OAExtensions.h>
#define OA_PLATFORM_IMAGE_CLASS NSImage
#endif

#ifdef OA_PLATFORM_IMAGE_CLASS
@class OA_PLATFORM_IMAGE_CLASS;

// To expose to Swift:
typedef OA_PLATFORM_IMAGE_CLASS *OAPlatformImageClass;
#endif

#ifdef OA_PLATFORM_IMAGE_CLASS
extern OA_PLATFORM_IMAGE_CLASS * _Nullable OAPlatformImageNamed(NSString * _Nonnull name, NSBundle * _Nullable bundle);
#endif
