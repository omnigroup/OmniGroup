// Copyright 2010-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentOpenAnimator.h"

RCS_ID("$Id$")

@interface OUIPresentationController : UIPresentationController
@end

@implementation OUIPresentationController

// See <bug:///195652> (iOS-OmniOutliner Bug: Multi-window: pop-up keyboard only displays for one full screen window) for the obscure reasoning why this is useful to us.
- (BOOL)shouldRemovePresentersView;
{
    return YES;
}
@end

@implementation OUIDocumentOpenAnimator
{
    UIDocumentBrowserTransitionController *_transitionController;
    OUIPresentationController *_presentationController;
}

- initWithTransitionController:(UIDocumentBrowserTransitionController *)transitionController;
{
    self = [super init];
    
    _transitionController = transitionController;
    
    return self;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source;
{
    return _transitionController;
}

- (id <UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed;
{
    return _transitionController;
}

- (nullable UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(nullable UIViewController *)presenting sourceViewController:(UIViewController *)source;
{
    if (!_presentationController)
        _presentationController = [[OUIPresentationController alloc] initWithPresentedViewController:presented presentingViewController:presenting];
    return _presentationController;
}

@end
