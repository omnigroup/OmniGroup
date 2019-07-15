// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Availability.h>

// Availability macros don't work reliably when module headers are implicitly built, so use ours as a backup.
// Mac-only
#if (!defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE) && !OMNI_BUILDING_FOR_IOS
#import <OmniQuartz/CIColor-OQExtensions.h>
#import <OmniQuartz/CIContext-OQExtensions.h>
#import <OmniQuartz/CIImage-OQExtensions.h>
#import <OmniQuartz/NSView-OQExtensions.h>
#import <OmniQuartz/OQFadeOutLayerRemovalAnimation.h>
#import <OmniQuartz/OQFlipSwapViewAnimation.h>
#import <OmniQuartz/OQGradient.h>
#import <OmniQuartz/OQHoleLayer.h>
#import <OmniQuartz/OQSlideOutLayerRemovalAnimation.h>
#import <OmniQuartz/OQTargetAnimation.h>
#endif

#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQContentAnimatingLayer.h>
#import <OmniQuartz/OQDrawing.h>
