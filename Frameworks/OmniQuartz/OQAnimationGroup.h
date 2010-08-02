// Copyright 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <QuartzCore/CAAnimation.h>

@interface OQAnimationGroup : CAAnimationGroup {
@private
    void(^ completionHandler)(BOOL finished);
}

- (void)setCompletionHandler:(void (^)(BOOL finished))completion;
- (void)animationDidComplete:(BOOL)flag;

@end
