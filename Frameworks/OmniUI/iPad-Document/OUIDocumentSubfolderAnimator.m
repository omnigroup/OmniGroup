// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentSubfolderAnimator.h"

#import <OmniUIDocument/OUIDocumentPickerViewController.h>

#import <OmniUIDocument/OUIDocumentPickerFileItemView.h>
#import <OmniUIDocument/OUIDocumentPickerScrollView.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniUI/UIView-OUIExtensions.h>

RCS_ID("$Id$")

@implementation OUIDocumentSubfolderAnimator

+ (instancetype)sharedAnimator;
{
    static OUIDocumentSubfolderAnimator *instance = nil;
    
    if (!instance)
        instance = [[self alloc] init];
    return instance;
}

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    return 0.5;
}

// the difference between the first tile finishing (at duration - variance) and last tile finishing (at duration)
#define DURATION_VARIANCE 0.10

- (void)animateOpenTransition:(id <UIViewControllerContextTransitioning>)transitionContext forItem:(ODSItem *)folder;
{
    OUIDocumentPickerViewController *sourceController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OUIDocumentPickerViewController *destinationController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];

    OUIDocumentPickerScrollView *fromScrollview = [sourceController mainScrollView];
    OUIDocumentPickerItemView *fromPreview = [fromScrollview itemViewForItem:folder];
    
    UIView *destinationView = [destinationController view];
    UIView *sourceView = [sourceController view];
    UIView *sourceViewSnapshot = [sourceView snapshotViewAfterScreenUpdates:NO];
    CGRect fromFrame = sourceView.frame;
    
    CGRect previewFrame = [fromPreview convertRect:fromPreview.bounds toView:sourceView];
    
    UIView *background = sourceController.backgroundView;
    UIImage *backgroundImage = [background snapshotImageWithRect:background.bounds];
    UIImageView *shield = [[UIImageView alloc] initWithImage:backgroundImage];
    shield.alpha = 0.0f;
    
    UIView *border = [fromPreview snapshotViewAfterScreenUpdates:NO];
    NSMutableArray *snapshots = [NSMutableArray array];
    NSMutableArray *snapshotItems = [NSMutableArray array];
    
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        sourceViewSnapshot.frame = fromFrame;
        shield.frame = fromFrame;
        
        [transitionContext.containerView insertSubview:sourceViewSnapshot aboveSubview:sourceView];
        [transitionContext.containerView insertSubview:destinationView belowSubview:sourceViewSnapshot];
        [transitionContext.containerView insertSubview:shield aboveSubview:destinationView];

        CGRect startFrame = [sourceView convertRect:previewFrame toView:transitionContext.containerView];
        border.frame = startFrame;
        [transitionContext.containerView insertSubview:border aboveSubview:shield];
        
        OUIDocumentPickerScrollView *toScrollview = [destinationController mainScrollView];
        NSUInteger locationIndex = 0;
        [toScrollview layoutIfNeeded];
        for (ODSFileItem *item in [toScrollview sortedItems]) {
            OUIDocumentPickerItemView *toPreview = [toScrollview itemViewForItem:item];
            
            if (!toPreview)
                continue;

            CGRect subFrame = CGRectInset(startFrame, 1, 1);
            subFrame.size.width /= 3;
            subFrame.size.height /= 3;
            subFrame.origin.x = CGRectGetMinX(startFrame) + CGRectGetWidth(subFrame) * (locationIndex % 3);
            subFrame.origin.y = CGRectGetMinY(startFrame) + CGRectGetHeight(subFrame) * (locationIndex / 3);
            subFrame = CGRectInset(subFrame, 8, 8);

            UIView *snapshot = [toPreview snapshotViewAfterScreenUpdates:YES];
            snapshot.alpha = 0.2;
            snapshot.frame = subFrame;
            [transitionContext.containerView insertSubview:snapshot aboveSubview:border];
            [snapshotItems addObject:item];
            [snapshots addObject:snapshot];
            locationIndex = (locationIndex+1) % 9;
        }
        
        [sourceView removeFromSuperview];
        sourceViewSnapshot.alpha = 1;
        destinationView.alpha = 0;
        shield.alpha = 0;
    }];
    
    id finished = ^(BOOL finished) {
        [shield removeFromSuperview];
        [border removeFromSuperview];
        [snapshots makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [transitionContext completeTransition:finished];
        
        [destinationView setAlpha:1];
    };
    
    NSUInteger itemsLeft = snapshotItems.count;
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    [UIView animateWithDuration:duration/4.0 delay:0 options:0 animations:^{
        shield.alpha = 1.0;
        border.alpha = 0.0;
        
        sourceViewSnapshot.alpha = 0.0;
        
        for (UIView *snapshot in snapshots)
            snapshot.alpha = 1.0;
    } completion:(!itemsLeft ? finished : nil)];
    
    CGFloat delayPerTile = DURATION_VARIANCE / snapshotItems.count;
    CGFloat currentDelay = 0;
    
    NSEnumerator *snapshotEnumerator = [snapshots objectEnumerator];
    for (ODSFileItem *item in snapshotItems) {
        OUIDocumentPickerItemView *toPreview = [[destinationController mainScrollView] itemViewForItem:item];
        UIView *snapshot = [snapshotEnumerator nextObject];
        
        [UIView animateWithDuration:(duration-DURATION_VARIANCE) delay:currentDelay usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
            snapshot.frame = [toPreview convertRect:toPreview.bounds toView:transitionContext.containerView];
        } completion:(!--itemsLeft ? finished : nil)];
        
        currentDelay += delayPerTile;
    }
}

- (void)animateCloseTransition:(id <UIViewControllerContextTransitioning>)transitionContext forItem:(ODSItem *)folder;
{
    OUIDocumentPickerViewController *sourceController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OUIDocumentPickerViewController *destinationController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    UIView *destinationView = [destinationController view];
    UIView *sourceView = [sourceController view];
    CGRect fromFrame = sourceView.frame;
    
    UIView *background = sourceController.backgroundView;
    UIImage *backgroundImage = [background snapshotImageWithRect:background.bounds];
    UIImageView *shield = [[UIImageView alloc] initWithImage:backgroundImage];
    shield.backgroundColor = sourceController.view.backgroundColor; // Need the background color from the scroll view because the background image has transparency in it.
    
    NSMutableArray *snapshots = [NSMutableArray array];
    
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        [transitionContext.containerView insertSubview:destinationView aboveSubview:sourceView];
        [transitionContext.containerView insertSubview:shield aboveSubview:destinationView];
        
        OUIDocumentPickerScrollView *fromScrollview = [sourceController mainScrollView];
        [fromScrollview layoutIfNeeded];
        [destinationController.mainScrollView layoutIfNeeded];
        
        for (ODSFileItem *item in [fromScrollview sortedItems]) {
            OUIDocumentPickerItemView *fromPreview = [fromScrollview itemViewForItem:item];
            
            if (!fromPreview)
                continue;
            
            UIView *snapshot = [fromPreview snapshotViewAfterScreenUpdates:NO];
            snapshot.frame = [fromPreview convertRect:fromPreview.bounds toView:transitionContext.containerView];
            [transitionContext.containerView insertSubview:snapshot aboveSubview:shield];
            [snapshots addObject:snapshot];
        }
        [sourceView removeFromSuperview];
    }];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    [UIView animateWithDuration:duration/2.0 delay:0 options:0 animations:^{
        shield.alpha = 0.0;
        for (UIView *snapshot in snapshots)
            snapshot.alpha = 0.0;
    } completion:^(BOOL finished) {
    }];
    
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        OUIDocumentPickerScrollView *toScrollview = [destinationController mainScrollView];
        
        [toScrollview layoutIfNeeded];
        CGRect finalFrame = [toScrollview convertRect:[toScrollview frameForItem:folder] toView:transitionContext.containerView];
        NSUInteger locationIndex = 0;

        for (UIView *snapshot in snapshots) {
            CGRect subFrame = CGRectInset(finalFrame, 1, 1);
            subFrame.size.width /= 3;
            subFrame.size.height /= 3;
            subFrame.origin.x = CGRectGetMinX(finalFrame) + CGRectGetWidth(subFrame) * (locationIndex % 3);
            subFrame.origin.y = CGRectGetMinY(finalFrame) + CGRectGetHeight(subFrame) * (locationIndex / 3);
            subFrame = CGRectInset(subFrame, 8, 8);
            snapshot.frame = subFrame;
            locationIndex = (locationIndex + 1) % 9;
        }
    } completion:^(BOOL finished) {
        [shield removeFromSuperview];
        [snapshots makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [transitionContext completeTransition:finished];
    }];
    
}

- (void)_doDissolve:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    UIView *destinationView = [[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey] view];
    UIView *sourceView = [[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] view];
    CGRect fromFrame = sourceView.frame;
    
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        destinationView.alpha = 0.0;
        [transitionContext.containerView insertSubview:destinationView aboveSubview:sourceView];
    }];
    
    [UIView animateWithDuration:duration animations:^{
        destinationView.alpha = 1.0;
    } completion:^(BOOL finished) {
        [transitionContext completeTransition:finished];
    }];
}

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerViewController *sourceController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OUIDocumentPickerViewController *destinationController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];

    if (destinationController.folderItem && [sourceController.filteredItems containsObject:destinationController.folderItem])
        return [self animateOpenTransition:transitionContext forItem:destinationController.folderItem];
    else if (sourceController.folderItem && [destinationController.filteredItems containsObject:sourceController.folderItem])
        return [self animateCloseTransition:transitionContext forItem:sourceController.folderItem];
    else
        return [self _doDissolve:transitionContext];
}

@end
