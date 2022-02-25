// Copyright 2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAImage.h>

#ifdef OA_PLATFORM_IMAGE_CLASS

OA_PLATFORM_IMAGE_CLASS * _Nullable OAPlatformImageNamed(NSString * _Nonnull name, NSBundle * _Nullable bundle)
{
    OA_PLATFORM_IMAGE_CLASS *mainBundleImage = nil;
#if TARGET_OS_IOS
    // Use the bundle if provided
    if (bundle != nil) {
        return [UIImage imageNamed:name inBundle:bundle withConfiguration:nil];
    }
    
    // Otherwise, prioritize the main bundle falling back to OMNI_BUNDLE
    mainBundleImage = [UIImage imageNamed:name inBundle:[NSBundle mainBundle] withConfiguration:nil];
    if (mainBundleImage != nil) {
        return mainBundleImage;
    } else {
        return [UIImage imageNamed:name inBundle:OMNI_BUNDLE withConfiguration:nil];
    }
#else
    // Use the bundle if provided
    if (bundle != nil) {
        OAImageNamed(name, bundle);
    }

    // Otherwise, prioritize the main bundle falling back to OMNI_BUNDLE
    mainBundleImage = OAImageNamed(name, [NSBundle mainBundle]);
    if (mainBundleImage != nil) {
        return mainBundleImage;
    } else {
        return OAImageNamed(name, OMNI_BUNDLE);
    }
#endif
}

#endif // #ifdef OA_PLATFORM_IMAGE_CLASS
