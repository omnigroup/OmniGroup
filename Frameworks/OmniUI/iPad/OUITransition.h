// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>
#import <UIKit/UIViewController.h>
#import <UIKit/UINavigationController.h>
#import <UIKit/UIViewControllerTransitioning.h>

@interface OUITransition : NSObject <UIViewControllerAnimatedTransitioning>

@property (nonatomic, strong) UIViewController *fromViewController;
@property (nonatomic, strong) UIViewController *toViewController;
@property (nonatomic, assign) UINavigationControllerOperation operation;
@property (nonatomic, assign) NSTimeInterval duration;

- (CGRect)_visibleFrameForTransitionViewsInContext:(id<UIViewControllerContextTransitioning>)transitionContext;

// fromRect in fromController.view coords, toRect in toController.view coords
- (void)crossFadeFromRect:(CGRect)fromRect toRect:(CGRect)toRect inContext:(id<UIViewControllerContextTransitioning>)transitionContext;
- (void)fadeOutRect:(CGRect)fromRect inContext:(id<UIViewControllerContextTransitioning>)transitionContext;
- (void)fadeInRect:(CGRect)toRect inContext:(id<UIViewControllerContextTransitioning>)transitionContext;

@end
