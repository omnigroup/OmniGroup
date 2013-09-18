// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentHomeScreenAnimator.h"

#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>
#import <OmniUIDocument/OUIDocumentPickerHomeScreenCell.h>
#import <OmniUIDocument/OUIDocumentPickerItemView.h>
#import <OmniUIDocument/OUIDocumentPreviewGenerator.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSFolderItem.h>
#import <OmniQuartz/CALayer-OQExtensions.h>

RCS_ID("$Id$")

@implementation OUIDocumentHomeScreenAnimator

+ (instancetype)sharedAnimator;
{
    static OUIDocumentHomeScreenAnimator *instance = nil;
    
    if (!instance)
        instance = [[self alloc] init];
    return instance;
}

- (NSTimeInterval)transitionDuration:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    return 0.6;
}

// the difference between the first tile finishing (at duration - variance) and last tile finishing (at duration)
#define DURATION_VARIANCE 0.15

- (void)animateTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    [OUIDocumentPreviewGenerator disablePreviewsForAnimation];
    
    if ([[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey] isKindOfClass:[OUIDocumentPickerHomeScreenViewController class]])
        return [self animateForwardTransition:transitionContext];
    else
        return [self animateBackwardTransition:transitionContext];
}

- (void)animationEnded:(BOOL) transitionCompleted;
{
    [OUIDocumentPreviewGenerator enablePreviewsForAnimation];
}

- (UIImageView *)_generateImageViewForContentsOfView:(UIView *)view;
{
    CGSize size = view.bounds.size;
    CGFloat scale = [[UIScreen mainScreen] scale];
    size.width *= scale;
    size.height *= scale;
    UIGraphicsBeginImageContext(size);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextConcatCTM(ctx, CGAffineTransformMakeScale(scale, scale));
    [view.layer renderInContextIgnoringCache:ctx];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    UIImageView *result = [[UIImageView alloc] initWithFrame:view.frame];
    [result setImage:image];
    return result;
}

- (void)animateForwardTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerHomeScreenViewController *topController = (OUIDocumentPickerHomeScreenViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OUIDocumentPickerViewController *scopeController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    
    [topController selectCellForScope:scopeController.selectedScope];
    OUIDocumentPickerHomeScreenCell *homeCell = topController.selectedCell;
    
    UITableView *sourceView = (UITableView *)[topController view];
    UIView *destinationView = [scopeController view];
    CGRect fromFrame = sourceView.frame;
    
    UIView *shield = [topController.backgroundView snapshotViewAfterScreenUpdates:NO];
    NSMutableArray *snapshots = [NSMutableArray array];
    NSMutableArray *snapshotItems = [NSMutableArray array];
    NSMutableArray *previewSnapshots = [NSMutableArray array];
    NSMutableArray *otherScopeSnapshots = [NSMutableArray array];
    
    [UIView performWithoutAnimation:^{
        shield.alpha = 1.0;
        destinationView.frame = fromFrame;
        [scopeController.mainScrollView layoutIfNeeded];
        
        [transitionContext.containerView insertSubview:destinationView aboveSubview:sourceView];
        [transitionContext.containerView insertSubview:shield aboveSubview:destinationView];
        
        UIView *lastView = shield;
        for (UIView *cell in topController.collectionView.visibleCells) {
            if (cell == topController.selectedCell)
                continue;
            
            UIView *cellSnapshot = [cell snapshotViewAfterScreenUpdates:NO];
            cellSnapshot.frame = [sourceView convertRect:cell.frame toView:transitionContext.containerView];
            [otherScopeSnapshots addObject:cellSnapshot];
            [transitionContext.containerView insertSubview:cellSnapshot aboveSubview:lastView];
            lastView = cellSnapshot;
        }
        
        NSUInteger otherPreviewIndex = 0;
        
        for (ODSFileItem *item in scopeController.mainScrollView.sortedItems) {
            if (otherPreviewIndex >= 24)
                break;
            
            OUIDocumentPickerItemView *toPreview = [scopeController.mainScrollView itemViewForItem:item];
            
            UIView *snapshot = nil;
            NSUInteger previewIndex = NSNotFound;
            CGRect startFrame;
            UIView *previewSnapshot = nil;
            
            if (toPreview) {
                UIImageView *samplePreview = [homeCell.previewViews objectAtIndex:0];
                snapshot = [self _generateImageViewForContentsOfView:toPreview];
                snapshot.layer.borderColor = samplePreview.layer.borderColor;
                snapshot.layer.borderWidth = samplePreview.layer.borderWidth;
                previewIndex = [homeCell.itemsForPreviews indexOfObject:item];
                [snapshots addObject:snapshot];
                [snapshotItems addObject:item];
            }
            if (previewIndex == NSNotFound) {
                CGRect miniRect = [homeCell _rectForMiniTile:otherPreviewIndex++ inRect:homeCell.preview6.bounds];
                startFrame = [homeCell.preview6 convertRect:miniRect toView:transitionContext.containerView];
                previewSnapshot = [homeCell.preview6 resizableSnapshotViewFromRect:miniRect afterScreenUpdates:NO withCapInsets:(UIEdgeInsets){1,1,1,1}];
            } else {
                UIView *view = [homeCell.previewViews objectAtIndex:previewIndex];
                startFrame = [view convertRect:view.bounds toView:transitionContext.containerView];
                previewSnapshot = [view snapshotViewAfterScreenUpdates:NO];
            }
            if (snapshot) {
                snapshot.frame = startFrame;
                [transitionContext.containerView insertSubview:snapshot aboveSubview:lastView];
                lastView = snapshot;
            }
            
            previewSnapshot.frame = startFrame;
            [transitionContext.containerView insertSubview:previewSnapshot aboveSubview:lastView];
            [previewSnapshots addObject:previewSnapshot];
            lastView = previewSnapshot;
        }
    }];
    
    id finished = ^(BOOL finished) {
        [shield removeFromSuperview];
        [snapshots makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [previewSnapshots makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [otherScopeSnapshots makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [transitionContext completeTransition:finished];
    };
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    NSTimeInterval delayPerTile = DURATION_VARIANCE / snapshots.count;
    
    CGFloat selfY = [homeCell convertPoint:homeCell.bounds.origin toView:transitionContext.containerView].y;
    CGFloat distance = CGRectGetHeight(fromFrame);
    [UIView animateWithDuration:(duration/6) delay:0 options:0 animations:^{
        for (UIView *cellSnapshot in otherScopeSnapshots)
            cellSnapshot.alpha = 0.0;
    } completion:nil];
    [UIView animateWithDuration:(duration/3) delay:0 options:0 animations:^{
        for (UIView *cellSnapshot in otherScopeSnapshots) {
            CGRect newFrame = cellSnapshot.frame;
            if (newFrame.origin.y < selfY)
                newFrame.origin.y -= distance;
            else
                newFrame.origin.y += distance;
            cellSnapshot.frame = newFrame;
        }
    } completion:(snapshots.count ? nil : finished)];
    
    
    NSEnumerator *previewEnumerator = [previewSnapshots objectEnumerator];
    NSUInteger tileNumber = 0;
    NSUInteger lastTileNumber = previewSnapshots.count - 1;
    for (ODSFileItem *item in scopeController.mainScrollView.sortedItems) {
        CGRect newFrame = [scopeController.mainScrollView convertRect:[scopeController.mainScrollView frameForItem:item] toView:transitionContext.containerView];
        UIView *previewSnapshot = [previewEnumerator nextObject];
        
        NSUInteger index = [snapshotItems indexOfObjectIdenticalTo:item];
        UIView *snapshot = nil;
        NSTimeInterval delay = tileNumber * delayPerTile;
        
        if (index != NSNotFound || CGRectGetWidth(previewSnapshot.frame) >= 100.0) {
            snapshot = [snapshots objectAtIndex:index];
            
            [UIView animateWithDuration:(duration-DURATION_VARIANCE)/2 delay:delay options:0 animations:^{
                previewSnapshot.alpha = 0.0f;
            } completion:nil];
            [UIView animateWithDuration:(duration-DURATION_VARIANCE) delay:delay usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
                previewSnapshot.frame = newFrame;
                snapshot.frame = newFrame;
            } completion:(tileNumber == lastTileNumber ? finished : nil)];
        } else {
            // if we are a small white snapshot and we aren't going to a visible spot on screen, just fade
            [UIView animateWithDuration:(duration-DURATION_VARIANCE)/4 delay:0 options:0 animations:^{
                previewSnapshot.alpha = 0.0f;
            } completion:nil];
            
            if (tileNumber == lastTileNumber) {
                // if we're the last tile, we need to animate something with the right duration to do the completion block
                [UIView animateWithDuration:(duration-DURATION_VARIANCE) delay:delay options:0 animations:^{
                    CGRect frame = previewSnapshot.frame;
                    frame.origin.y += 1.0;
                    previewSnapshot.frame = frame;
                } completion:finished];
            }
        }
        tileNumber++;
    }
}

- (void)animateSimpleFadeIn:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerHomeScreenViewController *topController = (OUIDocumentPickerHomeScreenViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    OUIDocumentPickerViewController *scopeController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    UITableView *sourceView = (UITableView *)[scopeController view];
    UIView *destinationView = [topController view];
    CGRect fromFrame = sourceView.frame;
    
    UIView *shield = [scopeController.backgroundView snapshotViewAfterScreenUpdates:NO];
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        
        [[transitionContext containerView] insertSubview:destinationView aboveSubview:sourceView];
        [[transitionContext containerView] insertSubview:shield aboveSubview:destinationView];
    }];
    [UIView animateWithDuration:duration*2.0/3.0 delay:duration/3.0 options:0 animations:^{
        shield.alpha = 0.0;
    } completion:^(BOOL finished) {
        [sourceView removeFromSuperview];
        [shield removeFromSuperview];
        [transitionContext completeTransition:finished];
    }];
}


- (void)animateBackwardTransition:(id <UIViewControllerContextTransitioning>)transitionContext;
{
    OUIDocumentPickerHomeScreenViewController *topController = (OUIDocumentPickerHomeScreenViewController *)[transitionContext viewControllerForKey:UITransitionContextToViewControllerKey];
    OUIDocumentPickerViewController *scopeController = (OUIDocumentPickerViewController *)[transitionContext viewControllerForKey:UITransitionContextFromViewControllerKey];
    OUIDocumentPickerHomeScreenCell *homeCell = topController.selectedCell;
    UIView *destinationView = [topController view];
    UIView *sourceView = [scopeController view];

    destinationView.tintColor = sourceView.window.tintColor; // set doc tint explicitly, otherwise snapshot will have default blue

    if (!homeCell)
        return [self animateSimpleFadeIn:transitionContext];
    
    NSTimeInterval duration = [self transitionDuration:transitionContext];
    CGRect fromFrame = sourceView.frame;
    
    UIView *shield = [scopeController.backgroundView snapshotViewAfterScreenUpdates:NO];
    UIView *selfShield = [scopeController.backgroundView resizableSnapshotViewFromRect:[homeCell convertRect:homeCell.bounds toView:topController.backgroundView] afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
    
    [topController.view layoutIfNeeded];
    
    UIView *topCover = [self _generateImageViewForContentsOfView:homeCell.coverView];
    
    NSMutableArray *otherViews = [NSMutableArray array];
    NSMutableArray *otherMiniRects = [NSMutableArray array];
    NSArray *allItems = scopeController.mainScrollView.sortedItems;
    
    [UIView performWithoutAnimation:^{
        destinationView.frame = fromFrame;
        
        [[transitionContext containerView] insertSubview:destinationView aboveSubview:sourceView];
        [[transitionContext containerView] insertSubview:shield aboveSubview:destinationView];
        
        selfShield.frame = [homeCell convertRect:homeCell.bounds toView:transitionContext.containerView];
        [[transitionContext containerView] insertSubview:selfShield aboveSubview:shield];
        
        NSUInteger extraTiles = 0;
        UIView *topmostView = selfShield;
        
        for (ODSItem *item in allItems) {
            OUIDocumentPickerItemView *itemView = [scopeController.mainScrollView itemViewForItem:item];
            
            UIView *mini;
            NSUInteger previewIndex = [homeCell.itemsForPreviews indexOfObjectIdenticalTo:item];
            if (previewIndex == NSNotFound) {
                if (!itemView)
                    continue;
                
                if (extraTiles > 24) {
                    mini = nil;
                } else {
                    mini = [homeCell.preview6 resizableSnapshotViewFromRect:[homeCell _rectForMiniTile:extraTiles inRect:homeCell.preview6.bounds] afterScreenUpdates:YES withCapInsets:(UIEdgeInsets){1,1,1,1}];
                    extraTiles++;
                }
            } else {
                UIImageView *previewView = [homeCell.previewViews objectAtIndex:previewIndex];
                mini = [[UIImageView alloc] initWithFrame:previewView.frame];
                mini.layer.borderColor = previewView.layer.borderColor;
                mini.layer.borderWidth = previewView.layer.borderWidth;
                [(UIImageView *)mini setImage:previewView.image];
            }
            CGRect newFrame = [scopeController.mainScrollView convertRect:[scopeController.mainScrollView frameForItem:item] toView:transitionContext.containerView];
            mini.frame = newFrame;
            
            if (mini) {
                [otherMiniRects addObject:mini];
                [transitionContext.containerView insertSubview:mini aboveSubview:topmostView];
                topmostView = mini;
            }
            
            if (itemView) {
                UIView *snapshot = [itemView snapshotViewAfterScreenUpdates:NO];
                snapshot.frame = newFrame;
                [otherViews addObject:snapshot];
                [[transitionContext containerView] insertSubview:snapshot aboveSubview:topmostView];
                topmostView = snapshot;
            } else {
                [otherViews addObject:[NSNull null]];
            }
        }
        
        topCover.frame = [homeCell convertRect:homeCell.coverView.frame toView:transitionContext.containerView];
        topCover.alpha = 0.0;
        [transitionContext.containerView insertSubview:topCover aboveSubview:topmostView];
    }];
    
    NSUInteger tileCount = otherMiniRects.count;
    NSUInteger lastTile = tileCount - 1;
    NSTimeInterval delayPerTile = DURATION_VARIANCE / tileCount;
    NSUInteger tileIndex = 0;
    
    id finished = ^(BOOL finished) {
        [sourceView removeFromSuperview];
        [shield removeFromSuperview];
        [selfShield removeFromSuperview];
        [topCover removeFromSuperview];
        for (UIView *view in otherViews)
            if (!OFISNULL(view))
                [view removeFromSuperview];
        [otherMiniRects makeObjectsPerformSelector:@selector(removeFromSuperview)];
        [transitionContext completeTransition:finished];
    };
    
    [UIView animateWithDuration:duration*3.0/4.0 delay:duration/4.0 options:0 animations:^{
        selfShield.alpha = 0.0;
    } completion:nil];

    [UIView animateWithDuration:duration*2.0/3.0 delay:duration/3.0 options:0 animations:^{
        topCover.alpha = 1.0;
        shield.alpha = 0.0;
    } completion:(tileCount ? nil : finished)];
    
    NSUInteger otherPreviewIndex = 0;
    CGRect otherRect = [homeCell.preview6 frame];
    NSEnumerator *otherEnumerator = [otherViews objectEnumerator];
    NSEnumerator *miniEnumerator = [otherMiniRects objectEnumerator];
    for (ODSItem *item in allItems) {
        CGRect destinationRect;
        NSUInteger previewIndex = [homeCell.itemsForPreviews indexOfObjectIdenticalTo:item];
        if (previewIndex == NSNotFound) {
            destinationRect = [homeCell convertRect:[homeCell _rectForMiniTile:otherPreviewIndex inRect:otherRect] toView:transitionContext.containerView];
            otherPreviewIndex++;
        } else {
            UIView *previewView = [homeCell.previewViews objectAtIndex:previewIndex];
            destinationRect = [previewView convertRect:previewView.bounds toView:transitionContext.containerView];
        }
        
        UIView *view = [otherEnumerator nextObject];
        CGFloat delay = (tileIndex*delayPerTile);
        if (OFISNULL(view)) {
            view = nil;
        } else {
            [UIView animateWithDuration:(duration-DURATION_VARIANCE)/2 delay:delay options:0 animations:^{
                view.alpha = 0.0f;
            } completion:nil];
        }
        [UIView animateWithDuration:(duration-DURATION_VARIANCE) delay:delay usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
            view.frame = destinationRect;
            UIView *mini = [miniEnumerator nextObject];
            mini.frame = destinationRect;
        } completion:(tileIndex == lastTile ? finished : nil)];
        tileIndex++;
    }
}

@end
