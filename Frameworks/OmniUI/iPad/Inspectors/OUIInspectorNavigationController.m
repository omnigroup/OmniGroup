// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorNavigationController.h"

#import <OmniUI/OmniUI-Swift.h>

RCS_ID("$Id$")


@implementation OUIInspectorNavigationController

- (UIViewController *)childViewControllerForStatusBarHidden;
{
    return nil;
}

// We really only want to hide the status bar if we're not in a popover, but the system doesn't even ask if we are being presented in a popover. So we can just return YES unconditionally here.
- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLoad{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_multiPaneControllerDidHidePane:) name:OUIMultiPaneControllerDidHidePaneNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    OUIInspectorPane *firstPane = (OUIInspectorPane *)self.viewControllers.firstObject;
    OBASSERT([firstPane isKindOfClass:[OUIInspectorPane class]]);
    
    OUIInspector *inspector = firstPane.inspector;
    [inspector forceUpdateInspectedObjects];
    
    [super viewWillAppear:animated];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    [self _cleanupInspectedObjects];
}

- (void)_multiPaneControllerDidHidePane:(NSNotification *)notification
{
    if (notification.object != self.topViewController.multiPaneController)
        return;

    NSNumber *paneLocationNumber = (NSNumber *)notification.userInfo[OUIMultiPaneControllerPaneLocationUserInfoKey];
    OUIMultiPaneLocation paneLocation = (OUIMultiPaneLocation)paneLocationNumber.integerValue;
    
    if (paneLocation == OUIMultiPaneLocationRight) {
        [self _cleanupInspectedObjects];
    }
}

- (void)_cleanupInspectedObjects {
    // Clear the selection from all the panes we've pushed. The objects in question could go away at any time and there is no reason for us to be observing or holding onto them! Clear stuff in reverse order (tearing down the opposite of setup).
    for (OUIInspectorPane *pane in [self.viewControllers reverseObjectEnumerator]) {
        if ([pane isKindOfClass:[OUIInspectorPane class]]) { // not all view controllers are panes - the image picker isn't!
            pane.inspectedObjects = nil;
            [pane updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDefault];
        }
    }
}

- (void)_keyboardWillShow:(NSNotification*)note {
    if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
        [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
    }
}

- (void)_keyboardWillHide:(NSNotification*)note
{
    if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
        [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
    }
}

- (void)_keyboardDidChangeFrame:(NSNotification*)note
{
    if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
        [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
    }
}

#pragma mark OUIInspectorPaneContaining
- (NSArray<OUIInspectorPane *> *)panes {
    return self.viewControllers;
}

- (void)popPaneAnimated:(BOOL)animated {
    [self popViewControllerAnimated:animated];
}

@end
