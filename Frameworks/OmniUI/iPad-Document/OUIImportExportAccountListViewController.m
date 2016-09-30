// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIImportExportAccountListViewController.h"

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIEmptyOverlayView.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIServerAccountSetupViewController.h>

#import "OUIAddCloudAccountViewController.h"
#import "OUIDocumentAppController-Internal.h"

RCS_ID("$Id$");

#pragma mark - Table view sections

typedef NS_ENUM(NSUInteger, TableViewSections)
{
    AccountsListSection,
    AddAccountSection,
};

@implementation OUIImportExportAccountListViewController
{
    NSMutableArray *_accounts;
    BOOL _isExporting;
}

static NSString *const AccountCellReuseIdentifier = @"account";
static NSString *const AddAccountReuseIdentifier = @"addAccount";

#pragma mark - UIViewController

- (instancetype)initForExporting:(BOOL)isExporting;
{
    if (!(self = [super initWithStyle:UITableViewStyleGrouped]))
        return nil;
    
    _accounts = [NSMutableArray new];
    _isExporting = isExporting;
    
    self.modalPresentationStyle = UIModalPresentationFormSheet;
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancelButtonAction:)];
    self.navigationItem.leftItemsSupplementBackButton = NO;
    
    self.clearsSelectionOnViewWillAppear = YES;
    self.tableView.alwaysBounceVertical = NO;
    
    return self;
}

- (void)viewDidLoad;
{
    self.tableView.allowsSelectionDuringEditing = YES;

    self.navigationItem.title = self.title;
    
    [super viewDidLoad];
}

- (void)setTitle:(NSString *)title;
{
    [super setTitle:title];
    self.navigationItem.title = self.title;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    [self setEditing:NO animated:NO];
    
    [self _reloadAccounts];
}

#pragma mark -
#pragma mark UITableView dataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    if (_accounts.count > 0)
        return 2;
    else
        return 0;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    switch ((TableViewSections)section) {
        case AccountsListSection:
            return _accounts.count;
        case AddAccountSection:
            return 1;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch ((TableViewSections)indexPath.section) {
        case AccountsListSection: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AccountCellReuseIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:AccountCellReuseIdentifier];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            
            OFXServerAccount *account = _accounts[indexPath.row];
            cell.textLabel.text = account.displayName;
            cell.detailTextLabel.text = account.accountDetailsString;
            
            // Only allow editing an account's details when we're being used to choose an account, not to create one. (Editing an account can affect whether they would have appeared in the original picker list, which can be confusing.)
            cell.accessoryType = UITableViewCellAccessoryDetailButton;
            
            return cell;
        }
        case AddAccountSection: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AddAccountReuseIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:AccountCellReuseIdentifier];
                
                cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Add an Account", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Setup button title to convert an existing account");;
                cell.imageView.image = [UIImage imageNamed:@"OUIGreenPlusButton" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
            }

            return cell;
        }
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section == AccountsListSection);
    [self _editServerAccount:_accounts[indexPath.row]];
}

#pragma mark - UITableViewDelegate

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if ([[OUIAppController controller] showFeatureDisabledForRetailDemoAlertFromViewController:self])
        return nil;
    
    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch ((TableViewSections)indexPath.section) {
        case AccountsListSection:
            if (self.editing)
                [self _editServerAccount:_accounts[indexPath.row]];
            else
                if (_finished)
                    _finished(_accounts[indexPath.row]);
            break;
        case AddAccountSection: {
            OBASSERT(indexPath.row == 0);
            [self _addServerAccount];
            break;
        }
    }
}

// We use this, instead of -tableView:canEditRowAtIndexPath: since this lets the left edge of the non-editable Add Account rows move with existing accounts rather than staying outdented and thus tearing the edge of the table view.
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch ((TableViewSections)indexPath.section) {
        case AccountsListSection:
            return UITableViewCellEditingStyleDelete;
        case AddAccountSection:
            return UITableViewCellEditingStyleNone;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBASSERT(tableView == self.tableView);
    OBPRECONDITION(indexPath.section == AccountsListSection);
    
    NSUInteger accountIndex = indexPath.row;
    OFXServerAccount *account = _accounts[accountIndex];
    
    [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:account withCancelAction:NULL discardAction:^{
        // This marks the account for removal and starts the process of stopping syncing on it. Once that happens, it will automatically be removed from the filesystem.
        [account prepareForRemoval];

        OBASSERT(tableView.numberOfSections == 2);
        
        [tableView beginUpdates];
        [_accounts removeObjectAtIndex:accountIndex];
        if (_accounts.count == 0) {
            [tableView deleteSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)] withRowAnimation:UITableViewRowAnimationFade];
            [self setEditing:NO animated:YES];
        } else {
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        }
        [tableView endUpdates];
    }];
}

#pragma mark - Private

- (void)_cancelButtonAction:(id)sender;
{
    if (_finished)
        _finished(nil);
}

- (void)_reloadAccounts;
{
    OFXServerAccountRegistry *accountRegistry = [OFXServerAccountRegistry defaultAccountRegistry];
    OFXServerAccountType *iTunesAccountType = [OFXServerAccountType accountTypeWithIdentifier:OFXiTunesLocalDocumentsServerAccountTypeIdentifier];

    [_accounts removeAllObjects];
    
    for (OFXServerAccount *account in [accountRegistry.allAccounts sortedArrayUsingSelector:@selector(compareServerAccount:)]) {
        if (account.type == iTunesAccountType)
            continue;
        if (account.hasBeenPreparedForRemoval)
            continue;
        if (account.usageMode == OFXServerAccountUsageModeImportExport)
            [_accounts addObject:account];
    }
    
    UITableView *tableView = self.tableView;
    [tableView reloadData];
    
    if (_accounts.count == 0) {
        NSString *message;
        
        if (_isExporting)
            message = NSLocalizedStringFromTableInBundle(@"No accounts are configured for exporting.", @"OmniUIDocument", OMNI_BUNDLE, @"Export message for empty table view");
        else
            message = NSLocalizedStringFromTableInBundle(@"No accounts are configured for importing.", @"OmniUIDocument", OMNI_BUNDLE, @"Import message for empty table view");
        
        NSString *buttonTitle = NSLocalizedStringFromTableInBundle(@"Add an Account", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Setup button title to add a new account");
        OUIEmptyOverlayView *emptyOverlay = [OUIEmptyOverlayView overlayViewWithMessage:message buttonTitle:buttonTitle action:^{
            [self _addServerAccount];
        }];
        
        tableView.backgroundView = emptyOverlay;
    } else {
        tableView.backgroundView = nil;
    }
}

- (void)_addServerAccount;
{
    OUIAddCloudAccountViewController *addController = [[OUIAddCloudAccountViewController alloc] initWithUsageMode:OFXServerAccountUsageModeImportExport];
    addController.finished = ^(OFXServerAccount *newAccountOrNil){
        [self.navigationController popToViewController:self animated:YES];
    };
    [self.navigationController pushViewController:addController animated:YES];
}

- (void)_editServerAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION(account);
    
    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAccount:account];
    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil){
        [self.navigationController popToViewController:self animated:YES];
        if (vc.account.usageMode == OFXServerAccountUsageModeCloudSync) {
            [[OUIDocumentAppController controller] _selectScopeWithAccount:vc.account completionHandler:NULL];
            [[[[OUIDocumentAppController controller] documentPicker] selectedScopeViewController] updateTitle];
        }
    };
    
    [self showViewController:setup sender:nil];
}

@end
