// Copyright 2000-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <QuartzCore/CALayer.h>

#import <OmniFoundation/OFExtent.h>

@interface OQHoleLayer : CALayer <CAAnimationDelegate>

- initWithGradientExtent:(OFExtent)gradientExtent shadowEdgeMask:(NSUInteger)shadowEdgeMask;

- (void)exposeByExpandingFromRect:(CGRect)originalRect toRect:(CGRect)finalRect inLayer:(CALayer *)parentLayer;
- (void)removeAfterShrinkingToRect:(CGRect)finalRect;

@end
