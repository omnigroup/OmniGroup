// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@interface OUISegmentedViewController : UIViewController

- (void)oui_invalidate;

@property (nonatomic, copy) NSArray *viewControllers;

@property(nonatomic, assign) UIViewController *selectedViewController;
@property(nonatomic) NSUInteger selectedIndex;

/*!
 @discussion This is used to set the rightBarButtonItem in the navigationItem. Please do not use the navigation item directly. OUISegmentedViewController owns the titleView and the leftBarButtonItem and will clobber anything you set them to. This is why we provide the rightBarButtonItem property for you to use.
 */
@property (nonatomic, strong) UIBarButtonItem *leftBarButtonItem;

- (CGFloat)topLayoutLength;
- (void)setShouldShowDismissButton:(BOOL)shouldShow;
- (void)temporarilyHideDismissButton:(BOOL)hide;

@end

@interface UIViewController (OUISegmentedViewControllerExtras)

@property (nonatomic, readonly) OUISegmentedViewController *segmentedViewController;
@property (nonatomic, readonly) BOOL wantsHiddenNavigationBar;

@end
