// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
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

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    return self.duration;
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    UIView *fromView = [fromViewController view];
    UIView *toView = [toViewController view];
    
    OBASSERT([fromView isDescendantOfView:[transitionContext containerView]]);
    OBASSERT(![toView isDescendantOfView:[transitionContext containerView]]);

    toView.frame = [transitionContext finalFrameForViewController:toViewController];
    
    [UIView transitionFromView:fromView toView:toView duration:[self transitionDuration:transitionContext] options:UIViewAnimationOptionTransitionCrossDissolve completion:^(BOOL finished) {
        [transitionContext completeTransition:finished];
    }];
}

@end
