// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIWrappingViewController.h>

@class OUIDocumentPickerHomeScreenViewController;

@interface OUIDocumentPickerAdaptableContainerViewController : OUIWrappingViewController

@property (readonly, weak, nonatomic) UIImageView *backgroundView;

- (NSArray *)popViewControllersForTransitionToCompactSizeClass; /*! The first element is the home screen view controller */
- (void)pushViewControllersForTransitionToRegularSizeClass:(NSArray *)viewControllersToAdd; /*! The first element should be the home screen view controller */
@end

@interface UIViewController (OUIDocumentPickerAdaptableContainerEmbeddedPresentation)
/*! Analogue to -showViewController:sender:, but tries to present the view controller outside of a containing OUIWrappingViewController.
 *
 *  First, sends -targetViewControllerForAction:sender: with the provided arguments. If the return value is the same as the receiver, sends -showViewController:sender: to itself. Otherwise, it sends -showUnembeddedViewController:sender: to the returned target.
 *
 *  OUIDocumentPickerAdaptableViewController overrides this method and reinterprets it to send -showViewController:sender to its parent view controller. */
- (void)showUnembeddedViewController:(UIViewController *)viewController sender:(id)sender;
@end
