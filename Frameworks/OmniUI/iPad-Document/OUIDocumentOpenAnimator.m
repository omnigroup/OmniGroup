// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentOpenAnimator.h"

#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniDocumentStore/ODSFileItem.h>

RCS_ID("$Id$")

@implementation OUIDocumentOpenAnimator

+ (instancetype)sharedAnimator;
{
    static OUIDocumentOpenAnimator *instance = nil;
    
    if (!instance)
        instance = [[self alloc] init];
    return instance;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source;
{
    if (presenting != _documentPicker.navigationController)
        return nil;
    else
        return self;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed;
{
    return self;
}

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    if ([transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] == _documentPicker.navigationController)
        return 0.3; // open
    else
        return 0.5; // close
}

- (void)_doDissolve:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    UIView *destinationView = [[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey] view];
    UIView *sourceView = [[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] view];

    destinationView.tintColor = sourceView.window.tintColor; // set doc tint explicitly, otherwise snapshot will have default blue
    
    UIView *snapshot = [destinationView snapshotViewAfterScreenUpdates:YES];
    UIView *sourceShot = [sourceView snapshotViewAfterScreenUpdates:YES];
    CGRect fromFrame = sourceView.frame;
    
    [UIView performWithoutAnimation:^{
        snapshot.frame = fromFrame;
        snapshot.alpha = 0.0;
        sourceShot.frame = fromFrame;
        [transitionContext.containerView insertSubview:destinationView belowSubview:sourceView];
        [transitionContext.containerView insertSubview:sourceShot aboveSubview:sourceView];
        [transitionContext.containerView insertSubview:snapshot aboveSubview:sourceShot];
        [sourceView removeFromSuperview];
    }];
    
    [UIView animateWithDuration:duration animations:^{
        snapshot.alpha = 1.0;
    } completion:^(BOOL finished) {
        [snapshot removeFromSuperview];
        [sourceShot removeFromSuperview];
        destinationView.frame = fromFrame;
        [transitionContext completeTransition:finished];
    }];
}

- (void)animateOpenTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerViewController *pickerController = _documentPicker.selectedScopeViewController;
    [pickerController.mainScrollView layoutIfNeeded];

    OUIDocumentPickerFileItemView *preview = [pickerController.mainScrollView fileItemViewForFileItem:_fileItem];
    if (!preview)
        return [self _doDissolve:transitionContext];

    UIView *destinationView = [[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey] view];
    UIView *sourceView = [[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] view];
    CGRect fromFrame = sourceView.frame;
    
    CGRect previewFrame = [preview convertRect:preview.bounds toView:sourceView];
    
    UIView *shield = [pickerController.backgroundView snapshotViewAfterScreenUpdates:NO];
    shield.alpha = 0.0f;
    
    destinationView.tintColor = sourceView.window.tintColor; // set doc tint explicitly, otherwise snapshot will have default blue
    __block UIView *docSnapshot = nil;
    UIView *previewSnapshot = [preview snapshotViewAfterScreenUpdates:YES];
    
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        [transitionContext.containerView insertSubview:destinationView belowSubview:sourceView];
        docSnapshot = [destinationView snapshotViewAfterScreenUpdates:YES];
        [transitionContext.containerView insertSubview:shield aboveSubview:sourceView];
        
        CGRect startFrame = [sourceView convertRect:previewFrame toView:transitionContext.containerView];

        docSnapshot.frame = startFrame;
        [transitionContext.containerView insertSubview:docSnapshot aboveSubview:shield];

        previewSnapshot.frame = startFrame;
        [transitionContext.containerView insertSubview:previewSnapshot aboveSubview:docSnapshot];
        
    }];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    [UIView animateWithDuration:duration/2.0 delay:0 options:0 animations:^{
        shield.alpha = 1.0;
        previewSnapshot.alpha = 0.0;
    } completion:^(BOOL finished) {
    }];
    
    [UIView animateWithDuration:duration delay:0 options:0 animations:^{
        previewSnapshot.frame = fromFrame;
        docSnapshot.frame = fromFrame;
    } completion:^(BOOL finished) {
        [shield removeFromSuperview];
        [previewSnapshot removeFromSuperview];
        [docSnapshot removeFromSuperview];
        [transitionContext completeTransition:finished];
    }];

}

- (void)animateCloseTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerViewController *pickerController = _documentPicker.selectedScopeViewController;
    
    ODSFileItem *fileItem = _actualFileItem ? _actualFileItem : _fileItem;
    if (![[pickerController filteredItems] containsObject:fileItem])
        return [self _doDissolve:transitionContext];

    UIView *containerView = [transitionContext containerView];
    
    UINavigationController *destination = (UINavigationController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *destinationView = [destination view];
    [containerView addSubview:destinationView];
    UIView *sourceView = [[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] view];
    CGRect fromFrame = sourceView.frame;

    if (!pickerController.view.superview) // make sure vc view is loaded and in the nav controller
        [containerView addSubview:pickerController.view];
    
    [pickerController.mainScrollView scrollItemToVisible:fileItem animated:NO];
    [pickerController.mainScrollView layoutIfNeeded];
    OUIDocumentPickerFileItemView *preview = [pickerController.mainScrollView fileItemViewForFileItem:fileItem];

    
    
    UIView *shield = [pickerController.backgroundView snapshotViewAfterScreenUpdates:YES];

    /*
     * WARNING!
     * The system is HIGHLY order-dependent. calling -resizableSnapshotViewFromRect:afterScreenUpdates: prompts our navigation controller to set itself up for the destination device orientation. Thus, we need to calculate the destination frame AFTER taking the snapshot.
     */
    UIView *itemShield = [pickerController.backgroundView resizableSnapshotViewFromRect:preview.frame afterScreenUpdates:YES withCapInsets:UIEdgeInsetsZero];
    itemShield.frame = [containerView convertRect:preview.bounds fromView:preview];;
    
    // Making snapshots removes and reinserts the view, and it ends up in the wrong order. Yuck.
    [pickerController.backgroundView removeFromSuperview];
    [pickerController.view insertSubview:pickerController.backgroundView atIndex:0];
    
    UIView *sourceSnapshot = [sourceView snapshotViewAfterScreenUpdates:NO];
    
    UIView *previewSnapshot = [preview snapshotViewAfterScreenUpdates:YES];
    
    CGRect navRect = destination.navigationBar.frame;
    navRect.size.height = CGRectGetMaxY(navRect) + 1.0; // extend to cover status bar and 1px separator
    navRect.origin.y = 0;
    
    UIView *navSnapshot = [destinationView resizableSnapshotViewFromRect:navRect afterScreenUpdates:YES withCapInsets:UIEdgeInsetsZero];

    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        [containerView insertSubview:destinationView aboveSubview:sourceView];
        [containerView insertSubview:itemShield aboveSubview:destinationView];
        [containerView insertSubview:shield aboveSubview:itemShield];

        previewSnapshot.frame = fromFrame;
        [containerView insertSubview:previewSnapshot aboveSubview:shield];

        sourceSnapshot.frame = fromFrame;
        [containerView insertSubview:sourceSnapshot aboveSubview:previewSnapshot];
        
        navSnapshot.frame = navRect;
        navSnapshot.alpha = 0.0;
        [containerView insertSubview:navSnapshot aboveSubview:sourceSnapshot];
    }];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    
    [UIView animateWithDuration:duration/4.0 delay:0 options:0 animations:^{
        sourceSnapshot.alpha = 0.0;
    } completion:^(BOOL finished) {
    }];

    [UIView animateWithDuration:duration/2.0 delay:0 options:0 animations:^{
        shield.alpha = 0.0;
        sourceSnapshot.alpha = 0.0;
        navSnapshot.alpha = 1.0;
    } completion:^(BOOL finished) {
    }];
    
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        CGRect finalFrame = [containerView convertRect:preview.bounds fromView:preview];
        previewSnapshot.frame = finalFrame;
        sourceSnapshot.frame = finalFrame;
    } completion:^(BOOL finished) {
        [shield removeFromSuperview];
        [itemShield removeFromSuperview];
        [previewSnapshot removeFromSuperview];
        [sourceSnapshot removeFromSuperview];
        [navSnapshot removeFromSuperview];
        [sourceView removeFromSuperview];
        [transitionContext completeTransition:finished];
    }];
}



- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    if ([transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] == _documentPicker.navigationController)
        return [self animateOpenTransition:transitionContext];
    else
        return [self animateCloseTransition:transitionContext];
}

@end
