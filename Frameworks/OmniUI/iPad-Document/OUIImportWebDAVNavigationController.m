// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIImportWebDAVNavigationController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>

#import "OUIImportWebDAVAccountListViewController.h"
#import "OUIWebDAVSyncListController.h"

RCS_ID("$Id$")

@interface OUIImportWebDAVNavigationController ()

@property (nonatomic, strong) NSArray *validImportAccounts;

@end

@implementation OUIImportWebDAVNavigationController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {

        self.modalPresentationStyle = UIModalPresentationFormSheet;
        self.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

        self.validImportAccounts = [OFXServerAccountRegistry defaultAccountRegistry].validImportExportAccounts;
        
        NSMutableArray *viewControllers = [NSMutableArray array];
        
        OUIImportWebDAVAccountListViewController *importWebDAVAccountListViewController = [[OUIImportWebDAVAccountListViewController alloc] init];
        __weak OUIImportWebDAVNavigationController *weakSelf = self;
        importWebDAVAccountListViewController.didSelectAccountAction = ^(OFXServerAccount *account) {
            NSError *error = nil;
            OUIWebDAVSyncListController *webDAVListController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:account exporting:NO error:&error];
            
            if (!webDAVListController) {
                return;
            }
            
            [weakSelf pushViewController:webDAVListController animated:YES];
        };
        [viewControllers addObject:importWebDAVAccountListViewController];

        if ([self.validImportAccounts count] == 1) {
            OFXServerAccount *account = self.validImportAccounts[0];

            NSError *error = nil;
            OUIWebDAVSyncListController *webDAVListController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:account exporting:NO error:&error];
            
            if (!webDAVListController) {
                return nil;
            }
            
            [viewControllers addObject:webDAVListController];
        }
        
        [self setViewControllers:viewControllers animated:NO];
    }
    return self;
}

@end
