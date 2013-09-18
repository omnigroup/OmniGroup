// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUICloudSetupViewController.h"

#import <OmniFileExchange/OFXServerAccountRegistry.h>

#import "OUIAddCloudAccountViewController.h"
#import "OUICloudAccountListViewController.h"

RCS_ID("$Id$");

@implementation OUICloudSetupViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
{
    if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]))
        return nil;
    
    self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    self.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // If we have no accounts already, there is no point showing a list of them and an "add" row -- just start the add.
    UIViewController *topViewController;
    if ([[[OFXServerAccountRegistry defaultAccountRegistry] allAccounts] count] > 0) {
        topViewController = [[OUICloudAccountListViewController alloc] init];
    } else {
        topViewController = [[OUIAddCloudAccountViewController alloc] init];
    }
    
    [self setViewControllers:@[topViewController] animated:NO];
    
    return self;
}


#pragma mark - UIViewController subclass

- (BOOL)disablesAutomaticKeyboardDismissal;
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return NO;
    }
    
    return [super disablesAutomaticKeyboardDismissal];
}

@end
