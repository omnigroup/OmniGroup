// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIPresentationController.h>

NS_ASSUME_NONNULL_BEGIN;

@protocol OUIInspectorPresentationControllerDismissalDelegate;

/**
 @param inspectorHeight Distance from bottom of screen that the inspector's view will cover. Useful to add bottom content inset to scroll views.
 */
typedef void (^OUIInspectorPresentationControllerAlongsidePresentationBlock)(CGFloat inspectorHeight);
typedef void (^OUIInspectorPresentationControllerTransitionBlock)(void);

#pragma mark - OUIInspectorPresentationController
@interface OUIInspectorPresentationController : UIPresentationController

@property(nullable, nonatomic, weak) id <OUIInspectorPresentationControllerDismissalDelegate> dismissalDelegate;

/**
 Clear view that covers the area where the presentingView is visable. One use-case might be to add a geture recignizer to this view to know when the presentingView is tapped.
 
 @note Presentations are model and taps are not normally passed through to the presentingView. This is a workaround to give a clean way of forwarding views back to the presentingView. 
 */
@property (nullable, nonatomic, readonly) UIView *seeThroughView;

// These all get set to nil at the end of -[UIPresentationController dismissalTransitionDidEnd:]

@property (nullable, nonatomic, copy) OUIInspectorPresentationControllerAlongsidePresentationBlock animationsToPerformAlongsidePresentation;
@property (nullable, nonatomic, copy) OUIInspectorPresentationControllerTransitionBlock presentInspectorCompletion;
// There are times were you can request an animated dismissal but are dismissed non-animated anyway. Most people expect these to get called even if we don't dismiss animated. These are now called during a transition coordinator if one exists or immediately after dimissal.
@property (nullable, nonatomic, copy) OUIInspectorPresentationControllerTransitionBlock animationsToPerformAlongsideDismissal;
@property (nullable, nonatomic, copy) OUIInspectorPresentationControllerTransitionBlock dismissInspectorCompletion;

@end

#pragma mark - OUIInspectorOverlayTransitioningDelegate
@interface OUIInspectorOverlayTransitioningDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end

#pragma mark - OUIInspectorPresentationControllerDelegate
@protocol OUIInspectorPresentationControllerDismissalDelegate <NSObject>

@optional
- (void)inspectorWillDismiss:(OUIInspectorPresentationController *)inspectorPresentationController;
- (void)inspectorDidDismiss:(OUIInspectorPresentationController *)inspectorPresentationController;

@end

NS_ASSUME_NONNULL_END;
