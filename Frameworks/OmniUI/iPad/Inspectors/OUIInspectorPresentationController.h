// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIPresentationController.h>

@interface OUIInspectorPresentationController : UIPresentationController

- (void)presentedViewNowNeedsToGrowForKeyboardHeight:(CGFloat)keyboardHeight withAnimationDuration:(CGFloat)duration options:(UIViewAnimationOptions)options completion:(void (^)())completion;
- (void)updateForPresentingViewTransitionToSize:(CGSize)newSize;
@property (nonatomic, weak) UIView *gesturePassThroughView;

@end

@interface OUIInspectorOverlayAnimatedTransitioning : NSObject <UIViewControllerAnimatedTransitioning>
@property (nonatomic) BOOL isPresentation;
@end

@interface OUIInspectorOverlayTransitioningDelegate : NSObject <UIViewControllerTransitioningDelegate>
@end
