// Copyright 2014-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISplitViewController.h>

@implementation OUISplitViewController
{
    UISplitViewControllerDisplayMode _actualPreferredDisplayMode;
}

- (UIViewController *)childViewControllerForStatusBarHidden;
{
    return self.viewControllers.lastObject;
}

- (UIViewController *)childViewControllerForStatusBarStyle;
{
    return self.viewControllers.lastObject;
}

// Fix for <bug:///109855> (Regression: Don't open the sidebar by default [hide sidebar]): Work around iOS bug with UISplitViewControllerDisplayModePrimaryHidden by setting the preferred mode to AllVisible until the view is just about to appear, and then finally setting it to the desired PrimaryHidden mode.

- (void)setPreferredDisplayMode:(UISplitViewControllerDisplayMode)preferredDisplayMode;
{
    _actualPreferredDisplayMode = preferredDisplayMode;
    if (preferredDisplayMode == UISplitViewControllerDisplayModeSecondaryOnly) {
        preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
    }
    [super setPreferredDisplayMode:preferredDisplayMode];
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    if (self.preferredDisplayMode != _actualPreferredDisplayMode) {
        [super setPreferredDisplayMode:_actualPreferredDisplayMode];
    }
}

@end
