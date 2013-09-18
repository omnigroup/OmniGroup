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
    UIView *containerView = [transitionContext containerView];
    
    OBASSERT([fromView isDescendantOfView:containerView]);
    OBASSERT(![toView isDescendantOfView:containerView]);
    
    [containerView insertSubview:toView aboveSubview:fromView];
    toView.alpha = 0.0f;
    toView.frame = [transitionContext finalFrameForViewController:toViewController];
    
    [UIView animateWithDuration:[self transitionDuration:transitionContext]
                     animations:^{
                         toView.alpha = 1.0f;
                     }
                     completion:^(BOOL finished) {
                         [fromView removeFromSuperview];
                         [transitionContext completeTransition:YES];
                     }];
}

@end
