// Copyright 2009-2010 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniQuartz/OQFadeOutLayerRemovalAnimation.h>

RCS_ID("$Id$");

@implementation OQFadeOutLayerRemovalAnimation

+ animationForRemovingLayer:(CALayer *)layer;
{
    CABasicAnimation *anim = [self animationWithKeyPath:@"opacity"];
    anim.fromValue = [NSNumber numberWithFloat:1.0f];
    anim.toValue = [NSNumber numberWithFloat:0.0f];

    OQAnimationGroup *group = [OQAnimationGroup animation];
    group.animations = [NSArray arrayWithObject:anim];
    return group;
}

@end
