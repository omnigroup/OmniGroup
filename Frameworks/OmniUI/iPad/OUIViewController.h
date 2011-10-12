// Copyright 2011 The Omni Group.  All rights reserved.
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
{
@private
    OUIViewControllerVisibility _visibility;
    BOOL _lastChangeAnimated;
    UIViewController *_unretained_parent; 
        // This is not redundant with parentViewController from UIViewController. UIViewController sets parentViewController in addChildViewController: BEFORE calling willMoveToParentViewController. We don't set _unretained_parent until the end of didMoveToParentViewController, so we can check for (a) consistency of the parent across the calls and (b) make sure we move through having no parent before getting a new parent.
@package
    UIViewController *_unretained_prospective_parent;
}

@property(readonly,nonatomic) OUIViewControllerVisibility visibility;

- (BOOL)isChildViewController:(UIViewController *)child;

@end
