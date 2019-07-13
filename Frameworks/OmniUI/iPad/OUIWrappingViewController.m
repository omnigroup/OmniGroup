// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
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
    
    UIViewController *existingWrappedViewController = _wrappedViewController;
    if (existingWrappedViewController != nil) {
        [existingWrappedViewController willMoveToParentViewController:nil];
        if (viewLoaded)
            [existingWrappedViewController.view removeFromSuperview];
        [existingWrappedViewController removeFromParentViewController];
    }
    
    _wrappedViewController = wrappedViewController;
    
    if (wrappedViewController != nil) {
        [self addChildViewController:wrappedViewController];
        if (viewLoaded)
            [self _addWrappedViewControllerView];
        [wrappedViewController didMoveToParentViewController:self];
    }
}

- (void)_addWrappedViewControllerView;
{
    OBPRECONDITION(self.isViewLoaded, "Call to -_addWrappedViewControllerView forced loading the view; please try to wait until the view is already loaded to enable lazy loading");
    
    UIViewController *wrappedViewController = _wrappedViewController;
    OBASSERT_NOTNULL(wrappedViewController, "Called -_addWrappedViewControllerView without a wrappedViewController to add");
    UIView *wrappedView = wrappedViewController.view;
    
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
    UIViewController *wrappedViewController = self.wrappedViewController;
    
    return wrappedViewController.childViewControllerForStatusBarHidden ?: wrappedViewController;
}

- (UIViewController *)childViewControllerForStatusBarStyle;
{
    UIViewController *wrappedViewController = self.wrappedViewController;
    
    return wrappedViewController.childViewControllerForStatusBarHidden ?: wrappedViewController;
}

- (BOOL)shouldAutorotate;
{
    UIViewController *wrappedViewController = self.wrappedViewController;
    
    if (wrappedViewController != nil && !wrappedViewController.shouldAutorotate) {
        return NO;
    }
    
    if (OUIRotationLock.hasActiveLocks) {
        return NO;
    }
    
    return super.shouldAutorotate;
}

@end

