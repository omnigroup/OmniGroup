// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@interface OUISegmentedViewController : UIViewController

@property (nonatomic, copy) NSArray *viewControllers;

@property(nonatomic, assign) UIViewController *selectedViewController;
@property(nonatomic) NSUInteger selectedIndex;

@end

@interface UIViewController (OUISegmentedViewControllerExtras)

@property (nonatomic, readonly) OUISegmentedViewController *segmentedViewController;
@property (nonatomic, readonly) BOOL wantsHiddenNavigationBar;

@end
