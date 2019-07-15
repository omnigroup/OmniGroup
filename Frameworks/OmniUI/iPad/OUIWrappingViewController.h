// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIViewController.h>

/*! A simple view controller that just wraps another view controller, which takes the full bounds of its containerView. */
@interface OUIWrappingViewController : UIViewController

@property (nonatomic, weak) UIViewController *wrappedViewController;

#pragma mark Subclass methods

/*! A descendant of the receiver's view that should contain the wrappedViewController's view.
 *
 *  Subclasses can return a view from this property that should contain the wrappedViewController's view. OUIWrappingViewController will set up the wrappedViewController's view to fill the bounds of the containerView. The subclass is responsible for positioning the containerView. */
@property (nonatomic, weak) IBOutlet UIView *containerView;

@end
