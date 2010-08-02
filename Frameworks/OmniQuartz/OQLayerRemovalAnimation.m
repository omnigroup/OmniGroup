// Copyright 2009-2010 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQLayerRemovalAnimation.h>

#import <OmniQuartz/CALayer-OQExtensions.h>

RCS_ID("$Id$");

static NSString * const RemovalAnimation = @"OQLayerRemovalAnimation";
static NSString * const TargetLayerKey = @"OQLayerRemovalAnimationTargetLayer";

// The normal order-out event cannot be used to trigger animations since the layer is gone already when it starts.  Radar 6408602.  Instead, we animate the bounds & contentRect to slide the content out and then remove the layer when the animation finishes.  

@implementation OQLayerRemovalAnimation

+ (BOOL)isRemovingLayer:(CALayer *)layer;
{
    return ([layer animationForKey:RemovalAnimation] != nil);
}

+ (BOOL)isRemovingAncestorOfLayer:(CALayer *)layer;
{
    return [layer ancestorHasAnimationForKey:RemovalAnimation];
}

+ (void)removeLayer:(CALayer *)layer completion:(void (^)(BOOL finished))completion;
{
    OBPRECONDITION(![self isRemovingLayer:layer]);
    
    BOOL animate = ![[CATransaction valueForKey:kCATransactionDisableActions] boolValue];
    if (!animate) {
        DEBUG_ANIMATION(@"%@ NOT animating removal", [layer shortDescription]);
        [layer removeFromSuperlayer];
        return;
    }
    
    OQAnimationGroup *anim = [self animationForRemovingLayer:layer];
    
    // We use fillMode=forward and removedOnCompletion=NO so that we don't get a pop at the end where the layer reappears briefly.  Our animationDidStop:finished: will remove it.
    anim.fillMode = kCAFillModeForwards;
    anim.removedOnCompletion = NO;
    if (completion != NULL)
        [anim setCompletionHandler:completion];
    
    // Make this animate with the same non-default curve that default-created animations use.  Grrr.
    anim.timingFunction = [CAMediaTimingFunction functionCompatibleWithDefault];
    
    DEBUG_ANIMATION(@"%@ animating removal with %@", [layer shortDescription], anim);

    anim.delegate = self;
    [anim setValue:layer forKey:TargetLayerKey];
    [layer addAnimation:anim forKey:RemovalAnimation];
}

+ (void)removeLayer:(CALayer *)layer;
{
    [self removeLayer:layer completion:NULL];
}

+ (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)flag;
{
    DEBUG_ANIMATION(@"animation did stop:%@ finished:%d", anim, flag);
    
    CALayer *layer = [anim valueForKey:TargetLayerKey];
    OBASSERT(layer);
    DEBUG_ANIMATION(@"  %@ has completely faded; removing", [layer shortDescription]);

    // Only removing the layer from superlayer if the animation finishes, because if the animation got cancelled halfway through (like via quickly collapse then expand in OOOutline) we need the layer to stay around. 
    // WARNING: The other reason why the finished flag might be NO is if the layers were never on-screen in the first place, so the animation just stops immediately. Which means anywhere you do removal animations, you need to test for that condition, and if the layer isn't visible, it should immediately removeFromSuperlayer instead.
    if (flag) {
        [CATransaction begin];
        [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
        [layer removeFromSuperlayer];
        [CATransaction commit];
    }
    
    if ([anim isKindOfClass:[OQAnimationGroup class]]) {
        [(OQAnimationGroup *)anim animationDidComplete:flag];
    }

    // Clean up potential retain cycles
    [layer removeAnimationForKey:RemovalAnimation];
    [anim setValue:nil forKey:TargetLayerKey];
}

+ animationForRemovingLayer:(CALayer *)layer;
{
    OBRequestConcreteImplementation(self, _cmd);
}

@end
