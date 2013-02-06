// Copyright 2010-2013 The Omni Group. All rights reserved.
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

// The view controller who presented us as a modal.
@property (nonatomic, readonly) UIViewController *modalParentViewController;

@property (nonatomic, readonly) OUIViewControllerState OUI_viewControllerState;

@property (nonatomic, readonly) BOOL OUI_isDismissingViewControllerAnimated;

// Will present the view controller immediately if we currently do not have a child presented view controller.
// If we have a child presented view controller, viewController will be presented as soon as the current child is dismissed.
- (void)enqueuePresentViewController:(UIViewController *)viewController animated:(BOOL)animated completion:(void (^)(void))completion;

@end
