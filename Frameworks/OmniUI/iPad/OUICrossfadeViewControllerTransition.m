// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUICrossfadeViewControllerTransition.h>

RCS_ID("$Id$");

@implementation OUICrossfadeViewControllerTransition

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    
    self.duration = 0.2;
    
    return self;
}

#pragma mark - UIViewControllerAnimatedTransitioning

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    [super animateTransition:transitionContext];
    
    UIView *fromView = [self.fromViewController view];
    UIView *toView = [self.toViewController view];
    
    OBASSERT([fromView isDescendantOfView:[transitionContext containerView]]);
    OBASSERT(![toView isDescendantOfView:[transitionContext containerView]]);

    toView.frame = [transitionContext finalFrameForViewController:self.toViewController];
    
    [UIView transitionFromView:fromView toView:toView duration:self.duration options:UIViewAnimationOptionTransitionCrossDissolve completion:^(BOOL finished) {
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
}

@end
