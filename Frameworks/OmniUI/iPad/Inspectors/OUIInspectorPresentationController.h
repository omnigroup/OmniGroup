// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIPresentationController.h>

#pragma mark - OUIInspectorPresentationController
@interface OUIInspectorPresentationController : UIPresentationController

- (void)presentedViewNowNeedsToGrowForKeyboardHeight:(CGFloat)keyboardHeight withAnimationDuration:(CGFloat)duration options:(UIViewAnimationOptions)options completion:(void (^)())completion;
- (void)updateForPresentingViewTransitionToSize:(CGSize)newSize;
@property (nonatomic, weak) UIView *gesturePassThroughView;

/// These all get set to nil during -[UIPresentationController dismissalTransitionDidEnd:]
@property (copy, nonatomic) void (^presentInspectorCompletion)(id<UIViewControllerTransitionCoordinatorContext> context);
@property (copy, nonatomic) void (^animationsToPerformAlongsidePresentation)(id<UIViewControllerTransitionCoordinatorContext> context);
@property (copy, nonatomic) void (^dismissInspectorCompletion)(id<UIViewControllerTransitionCoordinatorContext> context);
/// There are times were you can request an animated dismissal but are dismissed non-animated anyway. Most people expect these to get called even if we don't dismiss animated. These are now called during a transition coordinator if one exists or immediately after dimissal.
@property (copy, nonatomic) void (^animationsToPerformAlongsideDismissal)(id<UIViewControllerTransitionCoordinatorContext> context);


@end

#pragma mark - OUIInspectorOverlayTransitioningDelegate
@interface OUIInspectorOverlayTransitioningDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end
