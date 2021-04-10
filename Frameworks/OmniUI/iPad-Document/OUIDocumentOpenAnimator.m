// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentOpenAnimator.h"

RCS_ID("$Id$")

@implementation OUIDocumentOpenAnimator
{
    UIDocumentBrowserTransitionController *_transitionController;
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

@end
