// Copyright 2011-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

/*
 Utility superclass for tracking parent view controller, view controller visibility, and asserting that we're following the view containment protocols correctly.
*/

typedef enum {
    OUIViewControllerVisibilityHidden,
    OUIViewControllerVisibilityAppearing,
    OUIViewControllerVisibilityVisible,
    OUIViewControllerVisibilityDisappearing,
} OUIViewControllerVisibility;

@interface OUIViewController : UIViewController

// If set to to a non-empty rect, this rect will be applied to the view in -viewDidLoad. This can be a useful optimization for more complex view controllers that are about to be loaded into a parent view controller.
@property(nonatomic) CGRect initialFrame;

@property(readonly,nonatomic) OUIViewControllerVisibility visibility;

- (BOOL)isChildViewController:(UIViewController *)child;

@end
