// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISheetNavigationController.h"

#import <OmniUI/OUIAppController.h>

RCS_ID("$Id$")
       
@implementation OUISheetNavigationController
{
    UIViewController *_modalViewControllerSheet;
    BOOL _animateModalViewControllerSheet;
}

- (void)viewDidDisappear:(BOOL)animated;
{
    [super viewDidDisappear:animated];
    
    if (_modalViewControllerSheet) {
        OUISheetNavigationController *navigationController = [[OUISheetNavigationController alloc] initWithRootViewController:_modalViewControllerSheet];
        navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        OUIAppController *appController = [OUIAppController controller];
        [appController.topViewController presentViewController:navigationController animated:_animateModalViewControllerSheet completion:nil];
        
        _modalViewControllerSheet = nil;
    }
}

- (void)dismissModalViewControllerAnimated:(BOOL)animated andPresentModalViewControllerInSheet:(UIViewController *)modalViewController animated:(BOOL)sheetAnimated;
{
    [self dismissViewControllerAnimated:animated completion:nil];
    
    _modalViewControllerSheet = modalViewController;
    
    _animateModalViewControllerSheet = sheetAnimated;
}

@end
