// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIAddCloudAccountViewController.h"

#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIMainViewController.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>

#import "OUIServerAccountSetupViewController.h"
#import "OUIDocumentAppController-Internal.h"

RCS_ID("$Id$");

@interface OUIAddCloudAccountViewController () <UITableViewDataSource, UITableViewDelegate>

@end

@implementation OUIAddCloudAccountViewController
{
    UITableView *_tableView;
    NSArray *_accountTypes;
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

#pragma mark - UIViewController subclass

- (void)loadView;
{
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.scrollEnabled = NO; // Hopefully will never have that many account types...
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.backgroundView = nil;

    self.view = _tableView;
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [self _reloadAccountTypes];
    
    OBASSERT(self.navigationController);
    if (self.navigationController.viewControllers[0] == self) {
        self.navigationItem.leftBarButtonItem = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    }
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Add Cloud Account", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud setup modal sheet title");
    
    [super viewWillAppear:animated];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    return [_accountTypes count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSUInteger accountTypeIndex = indexPath.row;
    OBASSERT(accountTypeIndex < [_accountTypes count]);
    OFXServerAccountType *accountType = [_accountTypes objectAtIndex:accountTypeIndex];
    
    // Add Account row
    static NSString *reuseIdentifier = @"AddAccount";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.textLabel.text = accountType.addAccountTitle;
        cell.detailTextLabel.text = accountType.addAccountDescription;
        cell.imageView.image = [UIImage imageNamed:@"OUIGreenPlusButton.png"];
    }
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if ([[OUIAppController controller] showFeatureDisabledForRetailDemoAlert])
        return nil;

    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    NSUInteger accountTypeIndex = indexPath.row;
    OBASSERT(accountTypeIndex < [_accountTypes count]);
    OFXServerAccountType *accountType = [_accountTypes objectAtIndex:accountTypeIndex];

    // Add new account
    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAccount:nil ofType:accountType];
    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil){
        OFXServerAccount *account = errorOrNil ? nil : vc.account;
        OBASSERT(account == nil || [[[OFXServerAccountRegistry defaultAccountRegistry] validCloudSyncAccounts] containsObject:account]);
        [[OUIDocumentAppController controller] _didAddSyncAccount:account];
    };
    
    [self.navigationController pushViewController:setup animated:YES];
}

#pragma mark - Private

- (void)_cancel:(id)sender;
{
    [[[OUIDocumentAppController controller] mainViewController] dismissViewControllerAnimated:YES completion:nil];
}

- (void)_reloadAccountTypes;
{
    
    NSMutableArray *accountTypes = [NSMutableArray arrayWithArray:[OFXServerAccountType accountTypes]];
    [accountTypes removeObject:[OFXServerAccountType accountTypeWithIdentifier:OFXiTunesLocalDocumentsServerAccountTypeIdentifier]]; // Can't add/remove this account type
    _accountTypes = [accountTypes copy];
    
    [_tableView reloadData];
}

@end
