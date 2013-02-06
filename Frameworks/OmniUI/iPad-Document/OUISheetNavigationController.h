// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UINavigationController.h>


@interface OUISheetNavigationController : UINavigationController

// cannot dismiss this view controller and present a different one until the animation has completed
- (void)dismissModalViewControllerAnimated:(BOOL)animated andPresentModalViewControllerInSheet:(UIViewController *)modalViewController animated:(BOOL)sheetAnimated;

@end
