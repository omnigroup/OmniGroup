// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISheetNavigationController.h"

#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$")
       
@implementation OUISheetNavigationController

- (void)viewDidDisappear:(BOOL)animated;
{
    if (_modalViewControllerSheet) {
        OUISheetNavigationController *navigationController = [[OUISheetNavigationController alloc] initWithRootViewController:_modalViewControllerSheet];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        OUIAppController *appController = [OUIAppController controller];
        [appController.topViewController presentModalViewController:navigationController animated:_animateModalViewControllerSheet];
        
        [navigationController release];
    } else if (_nonretainedTarget && _message && [_nonretainedTarget respondsToSelector:NSSelectorFromString(_message)]) {
        [_nonretainedTarget performSelector:NSSelectorFromString(_message)];
    }
}

- (void)dismissModalViewControllerAnimated:(BOOL)animated andPresentModalViewControllerInSheet:(UIViewController *)modalViewController animated:(BOOL)sheetAnimated;
{
    [self dismissModalViewControllerAnimated:animated];
    
    [_modalViewControllerSheet release];
    _modalViewControllerSheet = [modalViewController retain];
    
    _animateModalViewControllerSheet = sheetAnimated;
}

- (void)dismissModalViewControllerAnimated:(BOOL)animated andSendMessage:(SEL)message toTarget:(id)target animated:(BOOL)sheetAnimated;
{
    [self dismissModalViewControllerAnimated:animated];
    
    _nonretainedTarget = target;
    [_message release];
    _message = [NSStringFromSelector(message) retain];
    
    _animateModalViewControllerSheet = sheetAnimated;
}

- (void)viewDidUnload;
{
    [super viewDidUnload];
    
    [_modalViewControllerSheet release];
    _modalViewControllerSheet = nil;
    
    [_message release];
    _message = nil;
    
    _nonretainedTarget = nil;
}

- (void)dealloc;
{    
    [_modalViewControllerSheet release];
    _modalViewControllerSheet = nil;
    
    [_message release];
    _message = nil;
    
    _nonretainedTarget = nil;
    
    [super dealloc];
}


@end
