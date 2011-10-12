// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

typedef enum {
    OUIViewControllerStateOffscreen,
    OUIViewControllerStateDisappearing,
    OUIViewControllerStateAppearing,
    OUIViewControllerStateOnscreen
} OUIViewControllerState;

@interface UIViewController (OUIExtensions)

+ (void)installOUIViewControllerExtensions;

// The view controller who presented us as a modal. Needs a slight rework for iOS 5
@property (nonatomic, readonly) UIViewController *modalParentViewController;

@property (nonatomic, readonly) OUIViewControllerState OUI_viewControllerState;

@property (nonatomic, readonly) BOOL OUI_isDismissingModalViewControllerAnimated;

// Will present the view controller immediately if we currently do not have a child modal view controller.
// If we have a child modal view controller, viewController will be presented as soon as the current child is dismissed.
- (void)enqueuePresentModalViewController:(UIViewController *)viewController animated:(BOOL)animated;

- (BOOL)OUI_defaultShouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;

@end
