// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIVerticalSplitTransition.h>
#import <UIKit/UIKit.h>

RCS_ID("$Id$")

@implementation OUIVerticalSplitTransition

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    
    self.duration = 0.3;
    
    return self;
}

- (void)insertToViewIntoContainer:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    UIView *fromView = self.fromViewController.view;
    UIView *toView = self.toViewController.view;
    UIView *containerView = transitionContext.containerView;
    
    if (toView.superview == containerView)
        return;

    toView.frame = [transitionContext finalFrameForViewController:self.toViewController];
    
    [UIView performWithoutAnimation:^{
        if (self.operation == UINavigationControllerOperationPush) {
            [containerView insertSubview:toView aboveSubview:fromView];
        } else if (self.operation == UINavigationControllerOperationPop) {
            [containerView insertSubview:toView belowSubview:fromView];
        }

        [toView layoutIfNeeded];
    }];
}

- (void)didInsertViewIntoContainer:(id<UIViewControllerContextTransitioning>)transitionContext NS_REQUIRES_SUPER;
{
    // No additional work to perform in the base class
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    [super animateTransition:transitionContext];
    
    if (self.operation == UINavigationControllerOperationNone) {
        [transitionContext completeTransition:NO];
        return;
    }
    
    UIView *transitionView = [self _transitionView];
    if (transitionView == nil) {
        [transitionContext completeTransition:NO];
        return;
    }
    
    CGRect topRect = CGRectZero, bottomRect = CGRectZero;
    CGRect transitionFrame = [self _visibleFrameForTransitionViewsInContext:transitionContext];
    if (CGRectEqualToRect(transitionFrame, CGRectZero)) {
        [transitionContext completeTransition:NO];
        return;
    }
    
    [self insertToViewIntoContainer:transitionContext];
    [self didInsertViewIntoContainer:transitionContext];

    CGRect leftover;
    CGRect splitExclusionRect = (self.splitExcludingRectProvider != NULL) ? self.splitExcludingRectProvider() : CGRectZero;
    splitExclusionRect = [transitionContext.containerView convertRect:splitExclusionRect fromView:transitionView];
    CGRectDivide(transitionFrame, &topRect, &leftover, CGRectGetMinY(splitExclusionRect), CGRectMinYEdge);
    CGRectDivide(transitionFrame, &leftover, &bottomRect, CGRectGetMaxY(splitExclusionRect), CGRectMinYEdge);
    
    CGFloat topSpaceAdjustment = 0.0f;
    switch(self.operation) {
        case UINavigationControllerOperationPush: topSpaceAdjustment = [self.fromViewController.topLayoutGuide length]; break;
        case UINavigationControllerOperationPop: topSpaceAdjustment = [self.toViewController.topLayoutGuide length]; break;
        default: OBASSERT_NOT_REACHED("Unexpected navigation operation"); break;
    }
    
    CGRect shiftedTopRect = CGRectOffset(topRect, 0, -topRect.size.height + topSpaceAdjustment);
    CGRect shiftedBottomRect = CGRectOffset(bottomRect, 0, bottomRect.size.height);
    
    BOOL waitForScreenUpdates = (self.operation == UINavigationControllerOperationPop);
    
    UIView *containerView = [transitionContext containerView];
    UIView *backdropView = [[UIView alloc] initWithFrame:containerView.bounds];
    backdropView.backgroundColor = [UIColor blackColor];
    backdropView.alpha = [self _initialBackdropOpacity:transitionContext];
    
    self.topSnapshot = [transitionView resizableSnapshotViewFromRect:[transitionView convertRect:topRect fromView:containerView] afterScreenUpdates:waitForScreenUpdates withCapInsets:UIEdgeInsetsZero];
    self.topSnapshot.backgroundColor = self.snapshotBackgroundColor;
    
    self.bottomSnapshot = [transitionView resizableSnapshotViewFromRect:[transitionView convertRect:bottomRect fromView:containerView] afterScreenUpdates:waitForScreenUpdates withCapInsets:UIEdgeInsetsZero];
    self.bottomSnapshot.backgroundColor = self.snapshotBackgroundColor;

#if 0 && defined(DEBUG_correia)
    self.topSnapshot.layer.borderColor = [UIColor orangeColor].CGColor;
    self.topSnapshot.layer.borderWidth = 2;
    self.bottomSnapshot.layer.borderColor = [UIColor orangeColor].CGColor;
    self.bottomSnapshot.layer.borderWidth = 2;
#endif
    
    UIView *topShadowView = [self _shadowViewWithFrame:_topSnapshot.frame];
    UIView *bottomShadowView = [self _shadowViewWithFrame:_bottomSnapshot.frame];
    
    if (self.operation == UINavigationControllerOperationPush) {
        _topSnapshot.frame = topRect;
        topShadowView.frame = topRect;
        _bottomSnapshot.frame = bottomRect;
        bottomShadowView.frame = bottomRect;
    } else if (self.operation == UINavigationControllerOperationPop) {
        _topSnapshot.frame = shiftedTopRect;
        topShadowView.frame = shiftedTopRect;
        _bottomSnapshot.frame = shiftedBottomRect;
        bottomShadowView.frame = shiftedBottomRect;
    } else {
        OBASSERT_NOT_REACHED(@"Unexpected navigation controller operation");
        [transitionContext completeTransition:NO];
        return;
    }
    
    [UIView performWithoutAnimation:^{
        [containerView addSubview:backdropView];
        
        [containerView addSubview:topShadowView];
        [containerView addSubview:bottomShadowView];
        
        [containerView addSubview:_topSnapshot];
        [containerView addSubview:_bottomSnapshot];
    }];
    
    if (!CGRectIsEmpty(splitExclusionRect)) {
        if (_fadeType == FadedPortionFadesInPlace) {
            if (self.operation == UINavigationControllerOperationPush) {
                [self fadeOutRect:splitExclusionRect inContext:transitionContext];
            } else {
                [self fadeInRect:splitExclusionRect inContext:transitionContext];
            }
        } else if (_fadeType == FadedPortionSlidesInFromTop) {
            CGRect fadeToRect = [containerView convertRect:splitExclusionRect toView:transitionView];
            fadeToRect.origin.y = CGRectGetMaxY(shiftedTopRect);
            
            if (self.destinationRectHeightProvider != NULL) {
                CGFloat destinationRectHeight = self.destinationRectHeightProvider();
                if (destinationRectHeight > 0) {
                    fadeToRect.size.height = destinationRectHeight;
                }
            }

            if (self.operation == UINavigationControllerOperationPush) {
                [self crossFadeFromRect:splitExclusionRect toRect:fadeToRect inContext:transitionContext];
            } else {
                [self crossFadeFromRect:fadeToRect toRect:splitExclusionRect inContext:transitionContext];
            }
        }
    }
    
    [UIView animateWithDuration:self.duration delay:0 options:0 animations:^{
        backdropView.alpha = [self _finalBackdropOpacity:transitionContext];
        topShadowView.alpha = (self.operation == UINavigationControllerOperationPop) ? 1.0 : 0.0;
        bottomShadowView.alpha = (self.operation == UINavigationControllerOperationPop) ? 1.0 : 0.0;
        
        if (self.operation == UINavigationControllerOperationPush) {
            _topSnapshot.frame = shiftedTopRect;
            topShadowView.frame = shiftedTopRect;
            _bottomSnapshot.frame = shiftedBottomRect;
            bottomShadowView.frame = shiftedBottomRect;
        } else if (self.operation == UINavigationControllerOperationPop) {
            _topSnapshot.frame = topRect;
            topShadowView.frame = topRect;
            _bottomSnapshot.frame = bottomRect;
            bottomShadowView.frame = bottomRect;
        } else {
            OBASSERT_NOT_REACHED(@"Unexpected navigation controller operation");
        }
        
    } completion:^(BOOL finished) {
        OBASSERT(finished, @"The animation should always finish – even if the backing transition doesn't");
        
        [backdropView removeFromSuperview];
        
        [_topSnapshot removeFromSuperview];
        [topShadowView removeFromSuperview];
        
        [_bottomSnapshot removeFromSuperview];
        [bottomShadowView removeFromSuperview];
        
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
}

- (void)animationEnded:(BOOL)transitionCompleted;
{
    if (transitionCompleted && self.operation == UINavigationControllerOperationPop)
        [[self.fromViewController view] removeFromSuperview];
}

#pragma mark - Private

- (UIView *)_transitionView;
{
    if (self.operation == UINavigationControllerOperationPush) {
        return [self.fromViewController view];
    } else if (self.operation == UINavigationControllerOperationPop) {
        return [self.toViewController view];
    } else {
        OBASSERT_NOT_REACHED(@"Unexpected navigation controller operation");
        return nil;
    }
}

- (UIView *)_shadowViewWithFrame:(CGRect)frame;
{
    UIView *shadowView = [[UIView alloc] initWithFrame:frame];
    shadowView.opaque = YES;
    shadowView.backgroundColor = [UIColor whiteColor];
    shadowView.layer.shadowOffset = CGSizeZero;
    shadowView.layer.shadowOpacity = self.shadowOpacity;
    shadowView.alpha = (self.operation == UINavigationControllerOperationPop) ? 0.0 : 1.0;
    return shadowView;
}

- (CGFloat)_initialBackdropOpacity:(id< UIViewControllerContextTransitioning>)transitionContext;
{
    switch (self.operation) {
        case UINavigationControllerOperationPush: return self.backdropOpacity;
        case UINavigationControllerOperationPop: return 0.0f;
        default: OBASSERT_NOT_REACHED("Unexpected navigation operation"); return 1.0f;
    }
}

- (CGFloat)_finalBackdropOpacity:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    switch (self.operation) {
        case UINavigationControllerOperationPush: return 0.0f;
        case UINavigationControllerOperationPop: return self.backdropOpacity;
        default: OBASSERT_NOT_REACHED("Unexpected navigation operation"); return 1.0f;
    }
}

@end

#pragma mark -

@implementation OUIVerticalSplitTransition (Subclass)

- (UIColor *)snapshotBackgroundColor;
{
    return [UIColor whiteColor];
}

- (CGFloat)backdropOpacity;
{
    return 0.09f;
}

- (CGFloat)shadowOpacity;
{
    return 0.2f;
}

@end
