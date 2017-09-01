// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITransition.h>


RCS_ID("$Id$")

@implementation OUITransition

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    
    _operation = UINavigationControllerOperationNone;
    return self;
}

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    return _duration;
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    self.fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    self.toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    if (self.fromViewController == nil || self.toViewController == nil) {
        [transitionContext completeTransition:NO];
    }
}

- (CGRect)_visibleFrameForTransitionViewsInContext:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    if (self.operation == UINavigationControllerOperationPush) {
        return [transitionContext initialFrameForViewController:self.fromViewController];
    } else if (self.operation == UINavigationControllerOperationPop) {
        return [transitionContext finalFrameForViewController:self.toViewController];
    } else {
        return [transitionContext initialFrameForViewController:self.fromViewController];
    }
}

- (void)crossFadeFromRect:(CGRect)fromRect toRect:(CGRect)toRect inContext:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    if (CGRectIsEmpty(fromRect) || CGRectIsEmpty(toRect))
        return;
    
    CGRect fromSnapshotRect = [self.fromViewController.view convertRect:fromRect fromView:transitionContext.containerView];
    UIView *fromSnapshot = [self.fromViewController.view resizableSnapshotViewFromRect:fromSnapshotRect afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    fromSnapshot.frame = fromRect;
    [transitionContext.containerView addSubview:fromSnapshot];
    
    CGRect toSnapshotRect = [self.toViewController.view convertRect:toRect fromView:transitionContext.containerView];
    UIView *toSnapshot = [self.toViewController.view resizableSnapshotViewFromRect:toSnapshotRect afterScreenUpdates:YES withCapInsets:UIEdgeInsetsZero];
    toSnapshot.frame = [self _rectOfHeight:CGRectGetHeight(toSnapshot.frame) verticallyCenteredOnRect:fromSnapshot.frame];
    toSnapshot.alpha = 0;
    [transitionContext.containerView insertSubview:toSnapshot aboveSubview:fromSnapshot];
    
#if 0 && defined(DEBUG_correia)
    fromSnapshot.layer.borderColor = [UIColor greenColor].CGColor;
    fromSnapshot.layer.borderWidth = 2;
    toSnapshot.layer.borderColor = [UIColor redColor].CGColor;
    toSnapshot.layer.borderWidth = 2;
#endif

    [UIView animateWithDuration:self.duration delay:0 options:0 animations:^{
        fromSnapshot.frame = [self _rectOfHeight:CGRectGetHeight(fromSnapshot.frame) verticallyCenteredOnRect:toRect];
        fromSnapshot.alpha = 0.0f;
        toSnapshot.frame = toRect;
        toSnapshot.alpha = 1.0f;
    } completion:^(BOOL finished) {
        OBASSERT(finished, @"Expected the transition animation to finish - even if the backing transition was cancelled");
        
        [fromSnapshot removeFromSuperview];
        [toSnapshot removeFromSuperview];
    }];
}

- (void)fadeOutRect:(CGRect)fromRect inContext:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    if (CGRectIsEmpty(fromRect))
        return;

    fromRect = [transitionContext.containerView convertRect:fromRect fromView:self.fromViewController.view];
    UIView *fromSnapshot = [self.fromViewController.view resizableSnapshotViewFromRect:fromRect afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    fromSnapshot.frame = fromRect;
    [transitionContext.containerView addSubview:fromSnapshot];

    [UIView animateWithDuration:self.duration delay:0 options:0 animations:^{
        fromSnapshot.alpha = 0.0f;
    } completion:^(BOOL finished) {
        OBASSERT(finished, @"Expected the transition animation to finish - even if the backing transition was cancelled");
        [fromSnapshot removeFromSuperview];
    }];
}

- (void)fadeInRect:(CGRect)toRect inContext:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    if (CGRectIsEmpty(toRect))
        return;

    toRect = [transitionContext.containerView convertRect:toRect fromView:self.toViewController.view];
    UIView *toSnapshot = [self.toViewController.view resizableSnapshotViewFromRect:toRect afterScreenUpdates:YES withCapInsets:UIEdgeInsetsZero];
    toSnapshot.frame = toRect;
    toSnapshot.alpha = 0.0f;
    [transitionContext.containerView addSubview:toSnapshot];
    
    [UIView animateWithDuration:self.duration delay:0 options:0 animations:^{
        toSnapshot.alpha = 1.0f;
    } completion:^(BOOL finished) {
        OBASSERT(finished, @"Expected the transition animation to finish - even if the backing transition was cancelled");
        [toSnapshot removeFromSuperview];
    }];
    
}

- (CGRect)_rectOfHeight:(CGFloat)height verticallyCenteredOnRect:(CGRect)anchorRect;
{
    CGRect rect = anchorRect;
    rect.origin.y = CGRectGetMidY(anchorRect) - height / 2.0;
    rect.size.height = height;
    return rect;
}

@end
