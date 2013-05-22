// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUICloudAccountListViewController.h"

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniUI/OUIAlert.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIMainViewController.h>

#import "OUIAddCloudAccountViewController.h"
#import "OUIServerAccountSetupViewController.h"
#import "OUIDocumentAppController-Internal.h"

RCS_ID("$Id$");

enum {
    CloudSyncAccountListSection,
    ImportExportAccountListSection,
    SectionCount,
};

@protocol BlahBlahBlah
- (NSURL *)localDocumentURL;
@end

@interface OUICloudAccountListViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation OUICloudAccountListViewController
{
    UITableView *_accountListTableView;
    UITableView *_addAccountTableView;

    NSArray *_cloudSyncAccounts;
    NSArray *_importExportAccounts;
}

- (void)dealloc;
{
    _accountListTableView.delegate = nil;
    _accountListTableView.dataSource = nil;
}

#pragma mark - UIViewController

- (void)loadView;
{
    OBPRECONDITION(_accountListTableView == nil);
    OBPRECONDITION(_addAccountTableView == nil);
    
    _accountListTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 500) style:UITableViewStyleGrouped];
    _accountListTableView.delegate = self;
    _accountListTableView.dataSource = self;
    _accountListTableView.scrollEnabled = YES;
    _accountListTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _accountListTableView.backgroundColor = [UIColor clearColor];
    _accountListTableView.backgroundView = nil;

    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Cloud Setup", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud setup modal sheet title");

    _addAccountTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 500, 320, 100) style:UITableViewStyleGrouped];
    _addAccountTableView.delegate = self;
    _addAccountTableView.dataSource = self;
    _addAccountTableView.scrollEnabled = NO;
    _addAccountTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    _addAccountTableView.backgroundColor = [UIColor clearColor];
    _addAccountTableView.backgroundView = nil;
    // OUITableViewAdjustHeightToFitContents(_addAccountTableView);

    UIView *topLevelView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 600)];
    [topLevelView addSubview:_accountListTableView];
    [topLevelView addSubview:_addAccountTableView];

    self.view = topLevelView;

    [self _updateToolbarButtons];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    [self setEditing:NO animated:NO];
    [_addAccountTableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:NO];
    
    [self _reloadAccounts];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    [super setEditing:editing animated:animated];
    
    if (self.isViewLoaded)
        [_accountListTableView setEditing:editing animated:animated];

    [self _updateToolbarButtons];
}
#pragma mark -
#pragma mark UITableView dataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    if (tableView != _accountListTableView)
        return 1;

    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (table != _accountListTableView)
        return 1;

    switch (section) {
        case CloudSyncAccountListSection:
            if (_cloudSyncAccounts.count == 0)
                return 0;
            else
                return _cloudSyncAccounts.count + 1; // An extra row for the "Use Cellular Data" switch
        case ImportExportAccountListSection:
            return [_importExportAccounts count];
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return 0;
    }
}

- (OFXServerAccount *)_accountForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case CloudSyncAccountListSection:
            return [_cloudSyncAccounts objectAtIndex:indexPath.row];
        case ImportExportAccountListSection:
            return [_importExportAccounts objectAtIndex:indexPath.row];
        default:
            return nil;
    }
}

- (void)_takeCellularDataSettingFromSwitch:(UISwitch *)controlSwitch;
{
    [OFXAgent setCellularSyncEnabled:controlSwitch.isOn];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (tableView != _accountListTableView) {
        static NSString *reuseIdentifier = @"AddAccount";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
            cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Add an Account", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Setup button title to add a new account");
            cell.imageView.image = [UIImage imageNamed:@"OUIGreenPlusButton.png"];
        }

        return cell;
    }

    switch (indexPath.section) {
        case CloudSyncAccountListSection:
            if (indexPath.row == (signed)_cloudSyncAccounts.count) {
                static NSString * const switchIdentifier = @"OUICloudAccountListViewControllerUseCellularData";
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:switchIdentifier];
                if (!cell) {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchIdentifier];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;

                    UISwitch *accessorySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
                    [accessorySwitch addTarget:self action:@selector(_takeCellularDataSettingFromSwitch:) forControlEvents:UIControlEventValueChanged];
                    [accessorySwitch sizeToFit];
                    cell.accessoryView = accessorySwitch;
                }

                NSString *title = NSLocalizedStringFromTableInBundle(@"Use Cellular Data", @"OmniUIDocument", OMNI_BUNDLE, @"Label for switch which controls whether cloud sync is allowed to use cellular data");

                cell.textLabel.text = title;

                UISwitch *accessorySwitch = (UISwitch *)cell.accessoryView;
                [accessorySwitch setOn:[OFXAgent isCellularSyncEnabled]];

                return cell;
            }
            // NO BREAK
        case ImportExportAccountListSection: {
            static NSString * const reuseIdentifier = @"ExistingServer";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }

            OFXServerAccount *account = [self _accountForRowAtIndexPath:indexPath];
            cell.textLabel.text = account.displayName;
            cell.detailTextLabel.text = account.accountDetailsString;
            
            return cell;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return nil;
    }

}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    if (tableView != _accountListTableView)
        return nil;

    switch (section) {
        case CloudSyncAccountListSection:
            return NSLocalizedStringFromTableInBundle(@"OmniPresence Accounts", @"OmniUIDocument", OMNI_BUNDLE, @"Group label for Cloud Setup");
        case ImportExportAccountListSection:
            return NSLocalizedStringFromTableInBundle(@"Import/Export Accounts", @"OmniUIDocument", OMNI_BUNDLE, @"Group label for Cloud Setup");
        default:
            return nil;
    }
}

#pragma mark - UITableViewDelegate

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if ([[OUIAppController controller] isRunningRetailDemo]) {
        OBASSERT_NOT_REACHED("Probably shouldn't even get to this view controller in a retail demo");
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Feature not enabled for this demo", @"OmniUIDocument", OMNI_BUNDLE, @"disabled for demo") message:nil delegate:nil cancelButtonTitle:NSLocalizedStringFromTableInBundle(@"Done", @"OmniUIDocument", OMNI_BUNDLE, @"Done") otherButtonTitles:nil];
        [alert show];
        
        return nil;
    }
    
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(self.editing == NO); // Tapping rows doesn't select them in edit mode

    if (tableView != _accountListTableView) {
        OUIAddCloudAccountViewController *add = [[OUIAddCloudAccountViewController alloc] init];
        [self.navigationController pushViewController:add animated:YES];
        return;
    }

    switch (indexPath.section) {
        case CloudSyncAccountListSection: {
            if (indexPath.row == (signed)_cloudSyncAccounts.count) { // "Use Cellular Data" switch
                return;
            }
            // NO BREAK
        }
        case ImportExportAccountListSection: {
            OFXServerAccount *account = [self _accountForRowAtIndexPath:indexPath];
            [self _editServerAccount:account];
            break;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown section");
    }
}

// We use this, instead of -tableView:canEditRowAtIndexPath: since this lets the left edge of the non-editable Add Account rows move with existing accounts rather than staying outdented and thus tearing the edge of the table view.
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (tableView != _accountListTableView)
        return UITableViewCellEditingStyleNone;
    
    if (indexPath.section == CloudSyncAccountListSection && indexPath.row == (signed)_cloudSyncAccounts.count) { // "Use Cellular Data" switch
        return UITableViewCellEditingStyleNone;
    }

    return UITableViewCellEditingStyleDelete;
}

- (NSMutableArray *)_mutableCopyOfAccountsForSection:(NSUInteger)section;
{
    switch (section) {
        case CloudSyncAccountListSection:
            return [_cloudSyncAccounts mutableCopy];
        case ImportExportAccountListSection:
            return [_importExportAccounts mutableCopy];
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return nil;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == CloudSyncAccountListSection && indexPath.row == (signed)_cloudSyncAccounts.count)
        return; // Don't touch the "Use Cellular Data" switch
    NSMutableArray *accounts = [self _mutableCopyOfAccountsForSection:indexPath.section];
    NSInteger accountIndex = indexPath.row;

    OFXServerAccount *account = [accounts objectAtIndex:accountIndex];
    [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:account withCancelAction:NULL discardAction:^{
        // This marks the account for removal and starts the process of stopping syncing on it. Once that happens, it will automatically be removed from the filesystem.
        [account prepareForRemoval];

        NSUInteger section = indexPath.section;
        NSMutableArray *accounts = [self _mutableCopyOfAccountsForSection:section];
        NSUInteger accountIndex = [accounts indexOfObjectIdenticalTo:account];
        if (accountIndex == NSNotFound)
            return; // Already removed?

        [accounts removeObjectAtIndex:accountIndex];
        switch (section) {
            case CloudSyncAccountListSection:
                _cloudSyncAccounts = accounts;
                break;
            case ImportExportAccountListSection:
                _importExportAccounts = accounts;
                break;
            default:
                OBASSERT_NOT_REACHED("We already short-circuit above if we're not in one of these two sections");
        }

        [_accountListTableView beginUpdates];
        if (section == CloudSyncAccountListSection && [_cloudSyncAccounts count] == 0) // If we've deleted our last cloud sync account, we need to also delete our "Use Cellular Data" row
            [_accountListTableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:1 inSection:CloudSyncAccountListSection]] withRowAnimation:UITableViewRowAnimationFade];
        [_accountListTableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:accountIndex inSection:section]] withRowAnimation:UITableViewRowAnimationFade];
        [_accountListTableView endUpdates];

        // Edit editing mode if this was the last editable object
        if (_cloudSyncAccounts.count + _importExportAccounts.count == 0) {
            [self setEditing:NO animated:YES];
            [self _updateToolbarButtons];

            // Swap to the 'add account' view controller
            OUIAddCloudAccountViewController *add = [[OUIAddCloudAccountViewController alloc] init];
            [self.navigationController setViewControllers:@[add] animated:YES];
        }
    }];
}

#pragma mark - Private

- (void)_done:(id)sender;
{
    [[[OUIDocumentAppController controller] mainViewController] dismissViewControllerAnimated:YES completion:nil];
}

- (void)_reloadAccounts;
{
    [self view]; // Make sure our view is loaded
    OBASSERT(_accountListTableView);
    
    OFXServerAccountRegistry *accountRegistry = [OFXServerAccountRegistry defaultAccountRegistry];
    OFXServerAccountType *iTunesAccountType = [OFXServerAccountType accountTypeWithIdentifier:OFXiTunesLocalDocumentsServerAccountTypeIdentifier];

    NSMutableArray *cloudSyncAccounts = [NSMutableArray array];
    NSMutableArray *importExportAccounts = [NSMutableArray array];
    for (OFXServerAccount *account in [accountRegistry.allAccounts sortedArrayUsingSelector:@selector(compareServerAccount:)]) {
        if (account.type == iTunesAccountType)
            continue;
        if (account.hasBeenPreparedForRemoval)
            continue;
        if (account.isCloudSyncEnabled)
            [cloudSyncAccounts addObject:account];
        else
            [importExportAccounts addObject:account];
    }
    
    _cloudSyncAccounts = [cloudSyncAccounts copy];
    _importExportAccounts = [importExportAccounts copy];
    
    [_accountListTableView reloadData];
    // OUITableViewAdjustHeightToFitContents(_accountListTableView);
    
    [self _updateToolbarButtons];
}

- (void)_editServerAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION(account);
    
    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAccount:account ofType:account.type];
    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil){
        [self.navigationController popToViewController:self animated:YES];
        if (vc.account.isCloudSyncEnabled) {
            [[OUIDocumentAppController controller] _selectScopeWithAccount:vc.account completionHandler:NULL];
            [[[OUIDocumentAppController controller] documentPicker] updateTitle];
        }
    };
    
    [self.navigationController pushViewController:setup animated:YES];
}

- (void)_updateToolbarButtons;
{
    [self.editButtonItem setEnabled:_cloudSyncAccounts.count + _importExportAccounts.count > 0];
    if (self.editing)
        self.navigationItem.leftBarButtonItem = nil;
    else
        self.navigationItem.leftBarButtonItem = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_done:)];
}

@end
