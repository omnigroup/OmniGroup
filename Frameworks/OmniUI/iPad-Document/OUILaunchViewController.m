// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUILaunchViewController.h"

RCS_ID("$Id$");

/*
 This is only shown right when the app is launching. This lets us use OUIMainViewController's layout for innerViewControllers before we know if we want to go to the document picker or open a document.
 Without this, the Default.png image would be shown and we'd pop to a view w/o a toolbar (but with our background shadow for the toolbar) and then a toolbar would pop back atop it. Ugly!
 We don't want to unconditionally load the document picker on launch since if we are going to load a document, firing up the loading of the previews is wasted effort.
 */

@implementation OUILaunchViewController
{
    UIToolbar *_toolbar;
}


#pragma mark - View lifecycle

// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView
{
    UIView *view = [[UIView alloc] init];
    self.view = view;
    
    _toolbar = [[UIToolbar alloc] init];

    [_toolbar sizeToFit];
    _toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _toolbar.barStyle = UIBarStyleBlack;
}

- (BOOL)shouldAutorotate;
{
    // Return YES for supported orientations
    return YES;
}

#pragma mark -
#pragma mark UIViewController (OUIMainViewControllerExtensions)

- (UIToolbar *)toolbarForMainViewController;
{
    if (!_toolbar)
        [self view]; // create it
    OBASSERT(_toolbar);
    return _toolbar;
}

- (BOOL)isEditingViewController;
{
    return NO;
}

@end
