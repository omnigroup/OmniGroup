// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIViewController.h>

@interface UIViewController (OUIExtensions)

+ (void)installOUIExtensions;

@property (nonatomic, readonly) UIViewController *modalParentViewController;

// Will present the view controller immediately if we currently do not have a child modal view controller.
// If we have a child modal view controller, viewController will be presented as soon as the current child is dismissed.
- (void)enqueueModalViewController:(UIViewController *)viewController presentAnimated:(BOOL)animated;

@end
