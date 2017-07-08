// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//

#import <OmniUI/OUIWrappingViewController.h>

#import <objc/runtime.h>

#import <OmniUI/OUIRotationLock.h>

RCS_ID("$Id$")

@implementation OUIWrappingViewController

#pragma mark - API

- (void)setWrappedViewController:(UIViewController *)wrappedViewController;
{
    BOOL viewLoaded = self.isViewLoaded;
    
    if (_wrappedViewController) {
        [_wrappedViewController willMoveToParentViewController:nil];
        if (viewLoaded)
            [_wrappedViewController.view removeFromSuperview];
        [_wrappedViewController removeFromParentViewController];
    }
    
    _wrappedViewController = wrappedViewController;
    
    if (_wrappedViewController) {
        [self addChildViewController:_wrappedViewController];
        if (viewLoaded)
            [self _addWrappedViewControllerView];
        [_wrappedViewController didMoveToParentViewController:self];
    }
}

- (void)_addWrappedViewControllerView;
{
    OBPRECONDITION(self.isViewLoaded, "Call to -_addWrappedViewControllerView forced loading the view; please try to wait until the view is already loaded to enable lazy loading");
    
    OBASSERT_NOTNULL(_wrappedViewController, "Called -_addWrappedViewControllerView without a wrappedViewController to add");
    UIView *wrappedView = _wrappedViewController.view;
    
    UIView *containerView = self.containerView;
    OBASSERT_NOTNULL(containerView, "-containerView returned nil; did you forget to connect an outlet?");
    
    wrappedView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:wrappedView];
    
    NSDictionary *viewDict = @{@"wrappedView" : wrappedView};
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[wrappedView]|" options:0 metrics:nil views:viewDict]];
    [NSLayoutConstraint activateConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[wrappedView]|" options:0 metrics:nil views:viewDict]];
    wrappedView.translatesAutoresizingMaskIntoConstraints = NO;
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    UIView *thisView = self.view;
    UIView *containerView = self.containerView;
    
    if (containerView != nil) {
        OBASSERT([containerView isDescendantOfView:thisView], "containerView should be a descendant of self.view");
    } else {
        containerView = [[UIView alloc] init];
        containerView.opaque = NO;
        containerView.backgroundColor = nil;
        containerView.frame = thisView.bounds;
        containerView.translatesAutoresizingMaskIntoConstraints = YES;
        containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [containerView setNeedsLayout];
        [thisView addSubview:containerView];
        _containerView = containerView;
    }
    
    if (_wrappedViewController != nil) {
        [self _addWrappedViewControllerView];
    }

    [super viewDidLoad];
}

- (UIViewController *)childViewControllerForStatusBarHidden;
{
    return self.wrappedViewController.childViewControllerForStatusBarHidden;
}

- (UIViewController *)childViewControllerForStatusBarStyle;
{
    return self.wrappedViewController.childViewControllerForStatusBarStyle;
}

- (BOOL)shouldAutorotate;
{
    NSUInteger rotationLockCount = [OUIRotationLock activeLocks].count;
    if (rotationLockCount > 0) {
        return NO;
    }
    else {
        return YES;
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle;
{
    return self.wrappedViewController.preferredStatusBarStyle;
}

@end
