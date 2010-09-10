// Copyright 2000-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <QuartzCore/CALayer.h>

#import <OmniFoundation/OFExtent.h>

@interface OQHoleLayer : CALayer
{
    CGGradientRef _gradient;
    NSUInteger _shadowEdgeMask; // one bit set for each of the min/max x/y edge constants for the edges that should have shadows.
    
    CGSize _shadowImageSize;
    CGImageRef _shadowImage;
    
    CALayer *_minXEdge, *_maxXEdge;
    CALayer *_minYEdge, *_maxYEdge;
}

- initWithGradientExtent:(OFExtent)gradientExtent shadowEdgeMask:(NSUInteger)shadowEdgeMask;

- (void)exposeByExpandingFromRect:(CGRect)originalRect toRect:(CGRect)finalRect inLayer:(CALayer *)parentLayer;
- (void)removeAfterShrinkingToRect:(CGRect)finalRect;

@end
