// Copyright 2014 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISplitViewController.h>

RCS_ID("$Id$")

@implementation OUISplitViewController

- (UIViewController *)childViewControllerForStatusBarHidden;
{
    return self.viewControllers.lastObject;
}

- (UIViewController *)childViewControllerForStatusBarStyle;
{
    return self.viewControllers.lastObject;
}

@end
