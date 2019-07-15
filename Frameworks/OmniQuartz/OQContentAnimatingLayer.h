// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <QuartzCore/CALayer.h>

// Nearly ever subclass will want OQCurrentAnimationValue().
#import <OmniQuartz/CALayer-OQExtensions.h>

@class CABasicAnimation;

@interface OQContentAnimatingLayer : CALayer <CAAnimationDelegate>

+ (NSSet *)keyPathsForValuesAffectingContents;

- (BOOL)isContentAnimation:(CAAnimation *)anim;
- (void)finishedAnimatingContent;

- (CABasicAnimation *)basicAnimationForKey:(NSString *)key;

@end
