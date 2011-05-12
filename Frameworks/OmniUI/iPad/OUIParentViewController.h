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
 Utility superclass for remembering children view controllers and informing them of their visibility.
 UIViewController doesn't really support this out of the box and frankly discourages it, but being able to compose views is a pretty basic idea...
 */

typedef enum {
    OUIViewControllerVisibilityHidden,
    OUIViewControllerVisibilityAppearing,
    OUIViewControllerVisibilityVisible,
    OUIViewControllerVisibilityDisappearing,
} OUIViewControllerVisibility;

@interface OUIParentViewController : UIViewController
{
@private
    OUIViewControllerVisibility _visibility;
    BOOL _lastChangeAnimated;
    NSMutableArray *_children;
}

@property(readonly,nonatomic) OUIViewControllerVisibility visibility;

- (void)addChildViewController:(UIViewController *)child animated:(BOOL)animated;
- (void)removeChildViewController:(UIViewController *)child animated:(BOOL)animated;
- (BOOL)isChildViewController:(UIViewController *)child;

@end
