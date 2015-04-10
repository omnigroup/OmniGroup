// Copyright 2014-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFullScreenNoteTransition.h>

#import <OmniUI/OUIFullScreenNoteTextViewController.h>
#import <OmniUI/OUINoteTextView.h>
#import <OmniUI/OUIKeyboardLock.h>

RCS_ID("$Id$")

@implementation OUIFullScreenNoteTransition

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    return 0.6;
}

- (void)animateOpeningDetail:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    UIViewController *fromController = OB_CHECKED_CAST(UIViewController, [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey]);
    UIView *fromView = [fromController view];
    OUIFullScreenNoteTextViewController *toController = OB_CHECKED_CAST(OUIFullScreenNoteTextViewController, [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey]);
    UIView *toView = [toController view];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    
    [UIView performWithoutAnimation:^{
        toView.alpha = 0.0f;
        toController.textView.selectedRange = NSMakeRange(0, 0);
        
        [[transitionContext containerView] addSubview:toView];
        if (self.fromTextView)
            toView.frame = [toView convertRect:[self.fromTextView frame] fromView:self.fromTextView];
        else
            toView.frame = [toView convertRect:[fromView frame] fromView:fromView];
        
    }];
    
    [UIView animateWithDuration:duration animations:^{
        toView.alpha = 1.0f;
        toView.frame = [transitionContext finalFrameForViewController:toController];
    } completion:^(BOOL finished) {
        if (finished) {
            if (/* DISABLES CODE */ (YES) || self.fromTextView) {
                toController.textView.editable = YES; //[self.fromTextView isEditable];
            }
            
            if (toController.selectedRange.location != NSNotFound) {
                [toController.textView becomeFirstResponder];
                toController.textView.selectedRange = toController.selectedRange;
                [toController.textView scrollRangeToVisible:toController.textView.selectedRange];
            }
        }
        
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
}

- (void)animateClosingDetail:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    OUIFullScreenNoteTextViewController *presentedViewController = OB_CHECKED_CAST(OUIFullScreenNoteTextViewController, [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey]);
    UIView *presentedView = [presentedViewController view];
    UIViewController *presentingViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *presentingView = [presentingViewController view];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    self.fromTextView.editable = NO;

    [UIView animateWithDuration:duration animations:^{
        presentedView.alpha = 0.0f;
        if (self.fromTextView)
            presentedView.frame = [presentedView convertRect:[self.fromTextView frame] fromView:self.fromTextView];
        else
            presentedView.frame = [presentedView convertRect:[presentingView frame] fromView:presentingView];
        
    } completion:^(BOOL finished) {
        [self.fromTextView resignFirstResponder];
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
}

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)transitionContext;
{
    if ([[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey] isKindOfClass:[OUIFullScreenNoteTextViewController class]])
        return [self animateOpeningDetail:transitionContext];
    else
        return [self animateClosingDetail:transitionContext];
}

@end
