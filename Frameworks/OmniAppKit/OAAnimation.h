// Copyright 2012-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSAnimation.h>

@protocol OAAnimationDelegate;

typedef void (^OAAnimationProgressHandler)(NSAnimationProgress progress, CGFloat CGFloatValue);
typedef CGFloat (^OAAnimationCGFloatValueTransformer)(NSAnimationProgress progress);

@interface OAAnimation : NSAnimation
{
    CGFloat _CGFloatValue;
    OAAnimationCGFloatValueTransformer _CGFloatValueTransformer;
    OAAnimationProgressHandler _progressHandler;
}

@property (nonatomic, readonly) CGFloat currentCGFloatValue;
@property (nonatomic, copy) OAAnimationCGFloatValueTransformer CGFloatValueTransformer; // Replacement for -animation:valueForProgress:
@property (nonatomic, copy) OAAnimationProgressHandler progressHandler;

@end
