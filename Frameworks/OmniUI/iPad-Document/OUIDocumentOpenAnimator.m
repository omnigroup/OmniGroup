// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentOpenAnimator.h"

#import <OmniUIDocument/OmniUIDocumentAppearance.h>
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
    return self;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed;
{
    return self;
}

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    if ([transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] == _documentPicker.navigationController)
        return [[OmniUIDocumentAppearance appearance] documentOpeningAnimationDuration]; // open
    else
        return [[OmniUIDocumentAppearance appearance] documentClosingAnimationDuration]; // close
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
        if (finished) {
            [snapshot removeFromSuperview];
            [sourceShot removeFromSuperview];
            destinationView.frame = fromFrame;
            [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
        }else{
            OBASSERT_NOT_REACHED("we were expecting the transition animation to have finished.  UI may be in unreasonable state.");
        }
    }];
}

- (void)_doPopOpen:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    
    UIView *containerView = transitionContext.containerView;
    
    UIView *sourceView = [[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] view];
    CGRect sourceViewFrame = sourceView.frame;
    
    UIView *destinationView = [[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey] view];
    destinationView.tintColor = sourceView.window.tintColor; // set doc tint explicitly, otherwise snapshot will have default blue
    
    [UIView performWithoutAnimation:^{
        self.backgroundSnapshotView.translatesAutoresizingMaskIntoConstraints = NO;
        [containerView addSubview:self.backgroundSnapshotView];
        [containerView sendSubviewToBack:self.backgroundSnapshotView];
        
        [self.backgroundSnapshotView.topAnchor constraintEqualToAnchor:containerView.topAnchor].active = YES;
        [self.backgroundSnapshotView.rightAnchor constraintEqualToAnchor:containerView.rightAnchor].active = YES;
        [self.backgroundSnapshotView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor].active = YES;
        [self.backgroundSnapshotView.leftAnchor constraintEqualToAnchor:containerView.leftAnchor].active = YES;
        
        self.previewSnapshotView.translatesAutoresizingMaskIntoConstraints = YES;
        CGRect pr = [containerView convertRect:self.previewRect fromView:nil];
        self.previewSnapshotView.frame = pr;
        [containerView insertSubview:self.previewSnapshotView aboveSubview:self.backgroundSnapshotView];
        
        destinationView.alpha = 0.0;
        destinationView.frame = sourceViewFrame;
        [containerView insertSubview:destinationView aboveSubview:self.previewSnapshotView];
        
        [sourceView removeFromSuperview];
    }];
    
    CGFloat scaleValue = 1.2;
    [UIView animateWithDuration:duration animations:^{
        self.previewSnapshotView.transform = CGAffineTransformScale(self.previewSnapshotView.transform, scaleValue, scaleValue);
        destinationView.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (finished) {
            [self.previewSnapshotView removeFromSuperview];
            [self.backgroundSnapshotView removeFromSuperview];
            [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
        }else{
            OBASSERT_NOT_REACHED("we were expecting the transition animation to have finished.  UI may be in unreasonable state.");
        }
    }];
}

- (void)animateOpenTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    if (self.isOpeningFromPeek) {
        [self _doPopOpen:transitionContext];
        return;
    }
    
    OUIDocumentPickerViewController *pickerController = nil;
    
    __kindof UIViewController *fromViewController = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OBASSERT([fromViewController isViewLoaded]);
    OBASSERT(fromViewController.view.window != nil); // Animating from something that isn't visible?

    if ([fromViewController isKindOfClass:[OUIDocumentPicker class]]) {
        pickerController = ((OUIDocumentPicker*)fromViewController).selectedScopeViewController;
    } else if ([fromViewController isKindOfClass:[OUIDocumentPickerViewController class]]){
        pickerController = (OUIDocumentPickerViewController*)fromViewController;
    } else {
        OBASSERT_NOT_REACHED(@"Uh... what are we opening a document from?");
        pickerController = _documentPicker.selectedScopeViewController;
    }
    [pickerController.mainScrollView layoutIfNeeded];

    OUIDocumentPickerFileItemView *preview = [pickerController.mainScrollView fileItemViewForFileItem:_fileItem];
    if (!preview) {
        [self _doDissolve:transitionContext];
        return;
    }

    UIView *destinationView = [transitionContext viewForKey:UITransitionContextToViewKey];
    UIView *sourceView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    CGRect fromFrame = sourceView.frame;
    
    CGRect previewFrame = [preview convertRect:preview.bounds toView:sourceView];
    
    UIView *shield = [pickerController.backgroundView snapshotViewAfterScreenUpdates:NO];
    shield.alpha = 0.0f;
    
    destinationView.tintColor = sourceView.window.tintColor; // set doc tint explicitly, otherwise snapshot will have default blue
    __block UIView *docSnapshot = nil;
    __block UIView *previewSnapshot = nil;
    
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        [transitionContext.containerView insertSubview:destinationView belowSubview:sourceView];
        previewSnapshot = [preview snapshotViewAfterScreenUpdates:YES];

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
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];

}

- (void)animateCloseTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerViewController *pickerController = nil;
    
    id toViewController = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    if ([toViewController isKindOfClass:[OUIDocumentPicker class]]) {
        pickerController = ((OUIDocumentPicker*)toViewController).selectedScopeViewController;
    } else if ([toViewController isKindOfClass:[OUIDocumentPickerViewController class]]){
        pickerController = (OUIDocumentPickerViewController*)toViewController;
    } else {
        OBASSERT_NOT_REACHED(@"Uh... what are we closing a document to?");
        pickerController = _documentPicker.selectedScopeViewController;
    }
    [pickerController.mainScrollView layoutIfNeeded];
    
    ODSFileItem *fileItem = _actualFileItem ? _actualFileItem : _fileItem;
    if (![[pickerController filteredItems] containsObject:fileItem]) {
        [self _doDissolve:transitionContext];
        return ;
    }

    UIView *containerView = [transitionContext containerView];
    
    UIView *destinationView = [transitionContext viewForKey:UITransitionContextToViewKey];
    [containerView addSubview:destinationView];
    UIView *sourceView = [transitionContext viewForKey:UITransitionContextFromViewKey];
    CGRect fromFrame = sourceView.frame;

    if (!destinationView.superview) // make sure vc view is loaded and in the nav controller
        [containerView addSubview:pickerController.view];

    if (!CGRectEqualToRect(destinationView.frame, destinationView.window.frame)) {  // this can happen if size transitions happen while the document is open.  should be a radar.
        destinationView.frame = destinationView.window.frame;
    }
    [destinationView setNeedsLayout];
    [destinationView layoutIfNeeded];
    [pickerController.mainScrollView scrollItemToVisible:fileItem animated:NO];
    OUIDocumentPickerFileItemView *preview = [pickerController.mainScrollView fileItemViewForFileItem:fileItem];

    /*
     * WARNING!
     * The system is HIGHLY order-dependent. calling -resizableSnapshotViewFromRect:afterScreenUpdates: prompts our navigation controller to set itself up for the destination device orientation. Thus, we need to calculate the destination frame AFTER taking the snapshot.
     */
    
    UIView *sourceSnapshot = [sourceView snapshotViewAfterScreenUpdates:YES];  /*WARNING!  The source view doesn't actually need updates, but if we pass NO here, then snapshotting the preview (next line) causes some bizzarre thing where, when closing a newly created document, the doc picker never realizes it has stopped presenting the document and therefore becomes unable to present anything ever again.  This problem is solved by taking a snapshotViewAfterScreenUpdates:YES of any view at all, including a randomly created blank UIView.  It is also solved by putting the previewSnapshot taking and all following code into a block to perform after delay 0, allowing the run loop to turn before it's executed (although the visual result is jerky).*/
    UIView *previewSnapshot = [preview snapshotViewAfterScreenUpdates:YES];

    [UIView performWithoutAnimation:^{
        [pickerController.mainScrollView scrollItemToVisible:fileItem animated:NO];  // we have to do this scroll again to cover the case where the device rotated while the document was open.  if we ONLY do it here, the close animation sometimes isn't smooth.
        [pickerController.mainScrollView layoutIfNeeded];
        
        preview.hidden = YES;
        destinationView.frame = fromFrame;
        [containerView insertSubview:destinationView aboveSubview:sourceView];
        
        previewSnapshot.frame = fromFrame;
        [containerView insertSubview:previewSnapshot aboveSubview:destinationView];
        
        sourceSnapshot.frame = fromFrame;
        [containerView insertSubview:sourceSnapshot aboveSubview:previewSnapshot];

    }];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        OUIDocumentPickerFileItemView *displayedPreview = [pickerController.mainScrollView fileItemViewForFileItem:fileItem];  // will have changed since last time we checked if this is a newly created document, so we need to get it again in order to have the correct frames to work with.
        displayedPreview.hidden = YES;
        CGRect finalFrame = [containerView convertRect:displayedPreview.bounds fromView:displayedPreview];
        previewSnapshot.frame = finalFrame;
        sourceSnapshot.frame = finalFrame;
    } completion:^(BOOL finished) {
        OUIDocumentPickerFileItemView *displayedPreview = [pickerController.mainScrollView fileItemViewForFileItem:fileItem];
        displayedPreview.hidden = NO;
        [previewSnapshot removeFromSuperview];
        [sourceSnapshot removeFromSuperview];
        
        [transitionContext completeTransition:![transitionContext transitionWasCancelled]];
    }];
    
    [UIView animateWithDuration:duration*(.75) delay:0 options:0 animations:^{
        sourceSnapshot.alpha = 0.0;
    } completion:^(BOOL finished) {
    }];
}



- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    UIViewController *source = [transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIViewController *destination = [transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    if (source == _documentPicker || [source isKindOfClass:[OUIDocumentPickerViewController class]])
        [self animateOpenTransition:transitionContext];
    else if (destination == _documentPicker || [source isKindOfClass:[OUIDocumentPickerViewController class]])
        [self animateCloseTransition:transitionContext];
    else
        [self _doDissolve:transitionContext];
}

@end
