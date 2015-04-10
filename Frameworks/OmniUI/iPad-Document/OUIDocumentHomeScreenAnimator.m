// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentHomeScreenAnimator.h"

#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniUIDocument/OUIDocumentPreviewGenerator.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import "OUIDocumentPickerAdaptableContainerViewController.h"

#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniQuartz/CALayer-OQExtensions.h>

RCS_ID("$Id$")

@implementation OUIDocumentHomeScreenAnimator

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    return [[OmniUIDocumentAppearance appearance] documentPickerHomeScreenAnimationDuration];
}

static CGAffineTransform shrinkAndTranslateTransform(CGRect cellFrameInTransitionContainerView, CGRect finalFrameForToView, UIView *transitionContainerView)
{
    // The document grid will animate from the same width as the selected cell in the location list. (Its height will shrink by the same proportion.)
    
    CGFloat zoomFactor = finalFrameForToView.size.width / cellFrameInTransitionContainerView.size.width;
    CGAffineTransform documentGridShrinkingTransform = CGAffineTransformMakeScale(1.0f / zoomFactor, 1.0f / zoomFactor);
    
    // Now figure out how to transform the shrunken document grid so its origin coincides with the origin of the selected cell
    CGRect documentGridShrunkenFinalFrame = CGRectApplyAffineTransform(finalFrameForToView, CGAffineTransformMakeTranslation(-(finalFrameForToView.origin.x + (finalFrameForToView.size.width / 2.0f)), -(finalFrameForToView.origin.y + (finalFrameForToView.size.height / 2.0f))));
    documentGridShrunkenFinalFrame = CGRectApplyAffineTransform(documentGridShrunkenFinalFrame, CGAffineTransformMakeScale(1.0f / zoomFactor, 1.0f / zoomFactor));
    documentGridShrunkenFinalFrame = CGRectApplyAffineTransform(documentGridShrunkenFinalFrame, CGAffineTransformMakeTranslation(finalFrameForToView.origin.x + (finalFrameForToView.size.width / 2.0f), finalFrameForToView.origin.y + (finalFrameForToView.size.height / 2.0f)));
    CGAffineTransform documentGridTranslationTransform = CGAffineTransformMakeTranslation(cellFrameInTransitionContainerView.origin.x - documentGridShrunkenFinalFrame.origin.x, cellFrameInTransitionContainerView.origin.y - documentGridShrunkenFinalFrame.origin.y);
    
    return CGAffineTransformConcat(documentGridShrinkingTransform, documentGridTranslationTransform);
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    [OUIDocumentPreviewGenerator disablePreviewsForAnimation];
    
    UIViewController *fromVC = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIView *fromView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    UIViewController *toVC = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *toView = [transitionContext viewForKey:UITransitionContextToViewKey];
    
    CGRect finalFrameOfDestinationView = [transitionContext finalFrameForViewController:toVC];
    UIView *transitionContainerView = [transitionContext containerView];
    OUIDocumentPickerAdaptableContainerViewController *homeScreenContainerVC;
    OUIDocumentPickerViewController *documentGridVC;
    
    if (_pushing) {
        homeScreenContainerVC = OB_CHECKED_CAST(OUIDocumentPickerAdaptableContainerViewController, fromVC);
        documentGridVC = OB_CHECKED_CAST(OUIDocumentPickerViewController, toVC);
    } else {
        homeScreenContainerVC = OB_CHECKED_CAST(OUIDocumentPickerAdaptableContainerViewController, toVC);
        documentGridVC = OB_CHECKED_CAST(OUIDocumentPickerViewController, fromVC);
    }
    
    OBASSERT(CGRectEqualToRect([transitionContext finalFrameForViewController:fromVC], CGRectZero), "This animation is going to look weird because we were asked not to remove the view being dismissed (but we're going to do it anyway).");
    OBASSERT(CGRectEqualToRect(finalFrameOfDestinationView, fromView.frame), "This animation is going to look weird because the view being dismissed doesn't currently have the same frame as the view we're transitioning to.");
    
    // Perform initial setup of the destination view.
    [UIView performWithoutAnimation:^{
        toView.frame = finalFrameOfDestinationView;
        toView.alpha = 0.0f;
        [transitionContainerView addSubview:toView];
        
        OBASSERT(toVC.parentViewController != nil, "About to ask the destination view controller to lay out, but it doesn't have a parent view controller so its topLayoutGuide is probably going to be wrong.");
        [toVC.view layoutIfNeeded];
    }];
    
    // Now that we know both views are in the view hierarchy, we can figure out the transform that relates the full-size and shrunken document grids.
    OUIDocumentPickerHomeScreenViewController *homeScreenVC = OB_CHECKED_CAST(OUIDocumentPickerHomeScreenViewController, ((UINavigationController *)homeScreenContainerVC.wrappedViewController).topViewController);
    CGAffineTransform shrinkingTransform = shrinkAndTranslateTransform([homeScreenVC frameOfCellForScope:documentGridVC.selectedScope inView:transitionContainerView], finalFrameOfDestinationView, transitionContainerView);
    CGAffineTransform zoomingTransform = CGAffineTransformInvert(shrinkingTransform);
    
    // Final setup: start zoomed out or zoomed in.
    [UIView performWithoutAnimation:^{
        toView.transform = _pushing ? shrinkingTransform : zoomingTransform;
    }];
    
    // Actually animate by applying the opposite transform to the view being dismissed.
    CGFloat bounceFactor = _pushing ? [[OmniUIDocumentAppearance appearance] documentPickerHomeScreenAnimationBounceFactor] : 1.0f; // don't bounce when navigating back to the home screen
    [UIView animateWithDuration:[self transitionDuration:transitionContext] delay:0 usingSpringWithDamping:bounceFactor initialSpringVelocity:0 options:0 animations:^{
        toView.transform = CGAffineTransformIdentity;
        toView.alpha = 1.0f;
        
        fromView.transform = _pushing ? zoomingTransform : shrinkingTransform;
        fromView.alpha = 0.0f;
    } completion:^(BOOL finished) {
        fromView.transform = CGAffineTransformIdentity;
        [fromView removeFromSuperview];
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
}

- (void)animationEnded:(BOOL) transitionCompleted;
{
    [OUIDocumentPreviewGenerator enablePreviewsForAnimation];
}

@end
