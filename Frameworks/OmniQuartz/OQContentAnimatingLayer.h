// Copyright 2008-2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <QuartzCore/CALayer.h>

// Nearly ever subclass will want OQCurrentAnimationValue().
#import <OmniQuartz/CALayer-OQExtensions.h>

@class CABasicAnimation;

@interface OQContentAnimatingLayer : CALayer
{
@private
    NSMutableArray *_activeContentAnimations;
}

+ (NSSet *)keyPathsForValuesAffectingContent;

- (BOOL)hasContentAnimations;
- (BOOL)isContentAnimation:(CAAnimation *)anim;
- (void)finishedAnimatingContent;

- (CABasicAnimation *)basicAnimationForKey:(NSString *)key;

@end
