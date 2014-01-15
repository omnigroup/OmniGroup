// Copyright 2005-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Availability.h>

// Mac-only
#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniQuartz/OQTargetAnimation.h>
#import <OmniQuartz/OQSlideOutLayerRemovalAnimation.h>
#import <OmniQuartz/OQFadeOutLayerRemovalAnimation.h>
#import <OmniQuartz/OQFlipSwapViewAnimation.h>

#import <OmniQuartz/OQHoleLayer.h>
#import <OmniQuartz/CIColor-OQExtensions.h>
#import <OmniQuartz/CIContext-OQExtensions.h>
#import <OmniQuartz/CIImage-OQExtensions.h>
#import <OmniQuartz/NSView-OQExtensions.h>
#import <OmniQuartz/OQAlphaScaleFilter.h>
#import <OmniQuartz/OQGradient.h>
#import <OmniQuartz/OQSimpleFilter.h>
#endif


#import <OmniQuartz/OQContentAnimatingLayer.h>

#import <OmniQuartz/CALayer-OQExtensions.h>
#import <OmniQuartz/OQColor.h>
