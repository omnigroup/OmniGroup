// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UINavigationController.h>


@interface OUISheetNavigationController : UINavigationController
{
@private
    UIViewController *_modalViewControllerSheet;
    BOOL _animateModalViewControllerSheet;
    NSString *_message;
    id _nonretainedTarget;
}

// cannot dismiss this view controller and present a different one until the animation has completed
- (void)dismissModalViewControllerAnimated:(BOOL)animated andPresentModalViewControllerInSheet:(UIViewController *)modalViewController animated:(BOOL)sheetAnimated;
- (void)dismissModalViewControllerAnimated:(BOOL)animated andSendMessage:(SEL)message toTarget:(id)target animated:(BOOL)sheetAnimated;
@end
