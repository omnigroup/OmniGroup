// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorNavigationController.h"

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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    OUIInspectorPane *firstPane = (OUIInspectorPane *)self.viewControllers.firstObject;
    OBASSERT([firstPane isKindOfClass:[OUIInspectorPane class]]);
    
    OUIInspector *inspector = firstPane.inspector;
    [inspector updateInspectedObjects];
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    // Clear the selection from all the panes we've pushed. The objects in question could go away at any time and there is no reason for us to be observing or holding onto them! Clear stuff in reverse order (tearing down the opposite of setup).
    for (OUIInspectorPane *pane in [self.viewControllers reverseObjectEnumerator]) {
        if ([pane isKindOfClass:[OUIInspectorPane class]]) { // not all view controllers are panes - the image picker isn't!
            pane.inspectedObjects = nil;
            [pane updateInterfaceFromInspectedObjects:OUIInspectorUpdateReasonDismissed];
        }
    }
}

// JCTODO: May need to update to handle new presentation setup.
- (void)keyboardWillShow:(NSNotification*)note
{
    if ([self _isCurrentlyPresentedWithCustomInspectorPresentation]) {
        // we might be in a partial height presentation and need to get taller
        OUIInspectorPresentationController *presentationController = (OUIInspectorPresentationController *)self.presentationController;
        NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
        NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
        NSValue *frame = note.userInfo[UIKeyboardFrameEndUserInfoKey];
        CGFloat height = [frame CGRectValue].size.height;
        UIViewAnimationOptions options = (curve.integerValue << 16) | UIViewAnimationOptionBeginFromCurrentState;  // http://macoscope.com/blog/working-with-keyboard-on-ios/  (Dec 20, 2013)
        __weak OUIInspectorNavigationController *weakSelf = self;
        if (!self.willDismissInspector){
            [presentationController presentedViewNowNeedsToGrowForKeyboardHeight:height withAnimationDuration:duration.floatValue options:options completion:^{
                OUIInspectorNavigationController *strongSelf = weakSelf;
                if (strongSelf) {
                    if ([strongSelf.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
                        [(OUIStackedSlicesInspectorPane*)strongSelf.topViewController updateContentInsetsForKeyboard];
                    }
                    [strongSelf adjustHeightOfGesturePassThroughView];
                }
            }];
        }
    } else {
        if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
            [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
        }
    }
}

- (void)adjustHeightOfGesturePassThroughView
{
    CGRect frameOfGesturePassThrough = self.gesturePassThroughView.frame;
    frameOfGesturePassThrough.size.height = self.view.window.frame.size.height - self.view.frame.size.height;
    self.gesturePassThroughView.frame = frameOfGesturePassThrough;
}

- (void)keyboardWillHide:(NSNotification*)note
{
    if ([self _isCurrentlyPresentedWithCustomInspectorPresentation]) {
        // we might have been in a partial height presentation and need to get shorter
        OUIInspectorPresentationController *presentationController = (OUIInspectorPresentationController *)self.presentationController;
        NSNumber *duration = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
        NSNumber *curve = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
        UIViewAnimationOptions options = (curve.integerValue << 16) | UIViewAnimationOptionBeginFromCurrentState;  // http://macoscope.com/blog/working-with-keyboard-on-ios/  (Dec 20, 2013)
        self.gesturePassThroughView.hidden = NO;
        __weak OUIInspectorNavigationController *weakSelf = self;
        [presentationController presentedViewNowNeedsToGrowForKeyboardHeight:0 withAnimationDuration:duration.integerValue options:options completion:^{
            OUIInspectorNavigationController *strongSelf = weakSelf;
            if (strongSelf) {
                if ([strongSelf.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
                    [(OUIStackedSlicesInspectorPane*)strongSelf.topViewController updateContentInsetsForKeyboard];
                    [strongSelf adjustHeightOfGesturePassThroughView];
                }
            }
        }];
    } else {
        if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
            [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
        }
    }
}

- (void)keyboardDidChangeFrame:(NSNotification*)note
{
    if ([self.topViewController isKindOfClass:[OUIStackedSlicesInspectorPane class]]) {
        [(OUIStackedSlicesInspectorPane*)self.topViewController updateContentInsetsForKeyboard];
    }
}

- (BOOL)_isCurrentlyPresentedWithCustomInspectorPresentation;
{
    UIViewController *mostDistantAncestor = [self.navigationController mostDistantAncestorViewController];
    BOOL isCurrentlyPresented = mostDistantAncestor.presentingViewController != nil;
    
    if (!isCurrentlyPresented) {
        return NO;
    }
    else {
        // View controllers seem to cache their presentationController/popoverPresentationController until the next time the presentation has been dismissed. Because of this, we guard the presentationController check until after we know the view controller is being presented.
        
        // By the time we get here, we know for sure we are currently being presented, so we just need to return wether we are using our custom presentation controller.
        return (mostDistantAncestor.modalPresentationStyle == UIModalPresentationCustom && [mostDistantAncestor.presentationController isKindOfClass:[OUIInspectorPresentationController class]]);
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
