// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentTemplateAnimator.h"

#import <OmniUIDocument/OUIDocumentPickerViewController.h>

#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentCreationTemplatePickerViewController.h>
#import "OUIDocumentParameters.h"
#import <OmniDocumentStore/ODSFileItem.h>

RCS_ID("$Id$")

@interface OUIDocumentTemplateAnimator ()
{
    CGRect _lastPlusButtonRect;
}
@end


@implementation OUIDocumentTemplateAnimator

+ (instancetype)sharedAnimator;
{
    static OUIDocumentTemplateAnimator *instance = nil;
    
    if (!instance)
        instance = [[self alloc] init];
    return instance;
}

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    return kOUIDocumentPickerTemplateAnimationDuration;
}

- (void)_animateAppearTransition:(id <UIViewControllerContextTransitioning>)transitionContext topView:(UIView *)topView bottomView:(UIView *)bottomView;
{
    CGRect bottomFrame = bottomView.frame;
    
    UIView *shield = [[UIView alloc] initWithFrame:bottomFrame];
    shield.backgroundColor = bottomView.backgroundColor;
    
    [UIView performWithoutAnimation:^{
        topView.alpha = 0;
        topView.frame = bottomFrame;
        topView.transform = CGAffineTransformMakeScale(kOUIDocumentPickerTemplateAnimationScaleFactor, kOUIDocumentPickerTemplateAnimationScaleFactor);
        
        UIView *containerView = transitionContext.containerView;
        [containerView insertSubview:shield aboveSubview:bottomView];
        [containerView insertSubview:topView aboveSubview:shield];
    }];
    
    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 options:0 animations:^{
        topView.alpha = 1;
        topView.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [shield removeFromSuperview];
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
}

- (void)_animateDisappearTransition:(id <UIViewControllerContextTransitioning>)transitionContext topView:(UIView *)topView bottomView:(UIView *)bottomView;
{
    CGRect topFrame = topView.frame;
    
    [UIView performWithoutAnimation:^{
        bottomView.frame = topFrame;
        
        UIView *containerView = transitionContext.containerView;
        [containerView insertSubview:bottomView belowSubview:topView];
    }];
    
    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 options:0 animations:^{
        topView.alpha = 0;
        topView.transform = CGAffineTransformMakeScale(kOUIDocumentPickerTemplateAnimationScaleFactor, kOUIDocumentPickerTemplateAnimationScaleFactor);
    } completion:^(BOOL finished) {
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
        topView.transform = CGAffineTransformIdentity;
        topView.alpha = 1;
    }];
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerViewController *sourceController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OUIDocumentPickerViewController *destinationController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    if ([destinationController isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]])
        return [self _animateAppearTransition:transitionContext topView:destinationController.view bottomView:sourceController.view];
    else if ([sourceController isKindOfClass:[OUIDocumentCreationTemplatePickerViewController class]])
        return [self _animateDisappearTransition:transitionContext topView:sourceController.view bottomView:destinationController.view];
}

@end
