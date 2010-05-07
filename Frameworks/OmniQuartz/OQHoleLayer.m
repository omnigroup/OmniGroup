// Copyright 2000-2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQHoleLayer.h>

#import <OmniQuartz/CALayer-OQExtensions.h>

RCS_ID("$Id$");

@implementation OQHoleLayer

- initWithGradientExtent:(OFExtent)gradientExtent shadowEdgeMask:(NSUInteger)shadowEdgeMask;
{
    if (!(self = [super init]))
        return nil;
    
    _shadowEdgeMask = shadowEdgeMask;
    
    // The full gray range we'll use if we get (0,1) as an input.
    OFExtent grayRange = OFExtentFromLocations(0.66f, 0.70f);
    
    // 10.6 has a gradient layer, but we don't on 10.5.
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
    CGColorRef topColor = CGColorCreateGenericGray(OFExtentValueAtPercentage(grayRange, OFExtentMax(gradientExtent)), 1.0f);
    CGColorRef bottomColor = CGColorCreateGenericGray(OFExtentValueAtPercentage(grayRange, OFExtentMin(gradientExtent)), 1.0f);
    _gradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)[NSArray arrayWithObjects:(id)bottomColor, (id)topColor, nil], NULL/*locations -> evenly spaced*/);
    CFRelease(colorSpace);
    CFRelease(topColor);
    CFRelease(bottomColor);
    
    self.needsDisplayOnBoundsChange = YES;
    self.anchorPoint = NSZeroPoint;
    self.edgeAntialiasingMask = 0; // Default to no anti-aliasing

    return self;
}

- init;
{
    return [self initWithGradientExtent:OFExtentMake(0, 1) shadowEdgeMask:(1<<NSMinXEdge)|(1<<NSMinYEdge)|(1<<NSMaxXEdge)|(1<<NSMaxYEdge)];
}

- (void)dealloc;
{
    if (_gradient)
        CFRelease(_gradient);
    [super dealloc];
}

static NSString * const OQHoleLayerRemoveAtEndOfAnimationKey = @"OQHoleLayerRemoveAtEndOfAnimation";

- (void)removeFromSuperlayerAtEndOfAnimation;
{    
    // Add an animation that we understand to indicate we should remove ourselves at its end.  The animation itself make sure we say behind the cell that is going opaque above us.
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"zPosition"];
    anim.fromValue = [NSNumber numberWithFloat:/*OOOutlineViewDefaultLayerZPosition*/-1];
    anim.toValue = [NSNumber numberWithFloat:/*OOOutlineViewDefaultLayerZPosition*/-1];
    anim.removedOnCompletion = NO;
    anim.fillMode = kCAFillModeForwards;
    anim.timingFunction = [CAMediaTimingFunction functionCompatibleWithDefault];
    anim.delegate = self;
    [self addAnimation:anim forKey:OQHoleLayerRemoveAtEndOfAnimationKey];
}

#pragma mark CAAnimation delegate

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
{
    OBPRECONDITION(![[[self class] superclass] instancesRespondToSelector:_cmd]);
    
    if ([self animationForKey:OQHoleLayerRemoveAtEndOfAnimationKey] == anim) {
        // We are likely only retained by our superlayer.
        [[self retain] autorelease];
        
        [CATransaction begin];
        [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
        [self removeFromSuperlayer];
        [CATransaction commit];
        
        [self removeAnimationForKey:OQHoleLayerRemoveAtEndOfAnimationKey]; // break the retain cycle; apparently CAAnimation retains its delegate
    } else {
        OBASSERT_NOT_REACHED("Unknown animation finished");
    }
}

#pragma mark CALayer subclass

#define SHADOW_RADIUS (40.0f)

- (void)drawInContext:(CGContextRef)ctx;
{
    NSRect bounds = self.bounds;
    
    CGContextSaveGState(ctx);
    {
        CGContextAddRect(ctx, bounds);
        CGContextClip(ctx);
        CGContextDrawLinearGradient(ctx, _gradient, bounds.origin, NSMakePoint(NSMinX(bounds), NSMaxY(bounds)), 0/*options*/);
    }
    CGContextRestoreGState(ctx);

    CGContextAddRect(ctx, NSInsetRect(bounds, -4*SHADOW_RADIUS, -4*SHADOW_RADIUS));
    
    // Set up a path outside our bounds so the shadow will be cast into the bounds but no fill.  Push each edge out based on whether we want a shadow on that edge.  If we do, 
    CGRect interiorRect = bounds;
    CGFloat noShadowOutset = 2*SHADOW_RADIUS;
    
    if ((_shadowEdgeMask & (1<<NSMinXEdge)) == 0) {
        interiorRect.origin.x -= noShadowOutset;
        interiorRect.size.width += noShadowOutset;
    }
    if ((_shadowEdgeMask & (1<<NSMinYEdge)) == 0) {
        interiorRect.origin.y -= noShadowOutset;
        interiorRect.size.height += noShadowOutset;
    }
    if ((_shadowEdgeMask & (1<<NSMaxXEdge)) == 0) {
        interiorRect.size.width += noShadowOutset;
    }
    if ((_shadowEdgeMask & (1<<NSMaxYEdge)) == 0) {
        interiorRect.size.height += noShadowOutset;
    }
    CGContextAddRect(ctx, interiorRect);

    CGColorRef shadowColor = CGColorCreateGenericGray(0.0f, 0.8f);
    CGContextSetShadowWithColor(ctx, NSMakeSize(0, 2)/*offset*/, SHADOW_RADIUS, shadowColor);
    CFRelease(shadowColor);
    
    CGContextSetFillColorWithColor(ctx, CGColorGetConstantColor(kCGColorWhite));
    CGContextDrawPath(ctx, kCGPathEOFill);
}

@end
