// Copyright 2009-2010 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQSlideOutLayerRemovalAnimation.h>
#import <OmniQuartz/CALayer-OQExtensions.h>

RCS_ID("$Id$");

@implementation OQSlideOutLayerRemovalAnimation

+ animationForRemovingLayer:(CALayer *)layer;
{
    CGRect bounds = OQCurrentAnimationValueInLayer(layer, bounds);
    CABasicAnimation *boundsAnimation = [CABasicAnimation animationWithKeyPath:@"bounds"];
    boundsAnimation.fromValue = [NSValue valueWithRect:bounds];
    boundsAnimation.toValue = [NSValue valueWithRect:NSMakeRect(CGRectGetMinX(bounds), CGRectGetMaxY(bounds), CGRectGetWidth(bounds), 0)];
    
    CABasicAnimation *contentsRectAnimation = [CABasicAnimation animationWithKeyPath:@"contentsRect"];
    contentsRectAnimation.fromValue = [NSValue valueWithRect:NSMakeRect(0, 0, 1, 1)];
    contentsRectAnimation.toValue = [NSValue valueWithRect:NSMakeRect(0, 1, 1, 0)];
    
    OQAnimationGroup *group = [OQAnimationGroup animation];
    group.animations = [NSArray arrayWithObjects:boundsAnimation, contentsRectAnimation, nil];
    
    return group;
}

@end
