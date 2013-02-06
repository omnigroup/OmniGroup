// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUICloudAccountListViewController.h"

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIMainViewController.h>

#import "OUIAddCloudAccountViewController.h"
#import "OUIServerAccountSetupViewController.h"

RCS_ID("$Id$");

enum {
    AccountListSection,
    AddAccountSection,
    SectionCount,
};

@interface OUICloudAccountListViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation OUICloudAccountListViewController
{
    UITableView *_tableView;

    NSArray *_accounts;
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

#pragma mark - UIViewController

- (void)loadView;
{
    OBPRECONDITION(_tableView == nil);
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 0) style:UITableViewStyleGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.scrollEnabled = NO; // OBFinishPorting - What if you have a huge number of accounts?
    
    self.navigationItem.leftBarButtonItem = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_done:)];
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Cloud Setup", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud setup modal sheet title");

    self.view = _tableView;
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    [self setEditing:NO animated:NO];
    
    [self _reloadAccounts];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    [super setEditing:editing animated:animated];
    
    if (self.isViewLoaded) {
        UITableView *tableView = (UITableView *)self.view;
        [tableView setEditing:editing animated:animated];
    }
}
#pragma mark -
#pragma mark UITableView dataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    switch (section) {
        case AccountListSection:
            return [_accounts count];
        case AddAccountSection:
            return 1;
        default:
            OBASSERT_NOT_REACHED("Unknown section");
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case AccountListSection: {
            static NSString * const reuseIdentifier = @"ExistingServer";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            
            OFXServerAccount *account = [_accounts objectAtIndex:indexPath.row];
            cell.textLabel.text = account.displayName;
            cell.detailTextLabel.text = account.accountDetailsString;
            
            return cell;
        }
        case AddAccountSection: {
            static NSString *reuseIdentifier = @"AddAccount";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
                cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Add an Account", @"OmniUIDocument", OMNI_BUNDLE, @"Cloud Setup button title to add a new account");
                cell.imageView.image = [UIImage imageNamed:@"OUIGreenPlusButton.png"];
            }
            
            return cell;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown section");
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
    
    switch (indexPath.section) {
        case AccountListSection: {
            OFXServerAccount *account = [_accounts objectAtIndex:indexPath.row];
            [self _editServerAccount:account];
            break;
        }
        case AddAccountSection: {
            OUIAddCloudAccountViewController *add = [[OUIAddCloudAccountViewController alloc] init];
            [self.navigationController pushViewController:add animated:YES];
            break;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown section");
    }
}

// We use this, instead of -tableView:canEditRowAtIndexPath: since this lets the left edge of the non-editable Add Account rows move with existing accounts rather than staying outdented and thus tearing the edge of the table view.
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == AddAccountSection)
        return UITableViewCellEditingStyleNone;
    
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == AccountListSection) {
        NSInteger accountIndex = indexPath.row;

        OFXServerAccount *account = [_accounts objectAtIndex:accountIndex];
        
        // This marks the account for removal and starts the process of stopping syncing on it. Once that happens, it will automatically be removed from the filesystem.
        [account prepareForRemoval];
    
        NSMutableArray *accounts = [_accounts mutableCopy];
        [accounts removeObject:account];
        _accounts = [accounts copy];
        
        [_tableView beginUpdates];
        [_tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
        [_tableView endUpdates];
    
        // Edit editing mode if this was the last editable object
        if ([_accounts count] == 0) {
            OBFinishPortingLater("Can we swap to the 'add account' view controller at this point?");
            [self setEditing:NO animated:YES];
            [self _updateToolbarButtons];
        }
    }
}

#pragma mark - Private

- (void)_done:(id)sender;
{
    [[[OUIDocumentAppController controller] mainViewController] dismissViewControllerAnimated:YES completion:nil];
}

- (void)_reloadAccounts;
{
    [self view]; // Make sure our view is loaded
    OBASSERT(_tableView);
    
    OFXServerAccountRegistry *accountRegistry = [OFXServerAccountRegistry defaultAccountRegistry];
    OFXServerAccountType *iTunesAccountType = [OFXServerAccountType accountTypeWithIdentifier:OFXiTunesLocalDocumentsServerAccountTypeIdentifier];

    NSArray *accounts = [accountRegistry.allAccounts select:^BOOL(OFXServerAccount *account) {
        if (account.type == iTunesAccountType)
            return NO;
        if (account.hasBeenPreparedForRemoval)
            return NO;
        return YES;
    }];
    
    _accounts = [accounts copy];
    
    [_tableView reloadData];
    OUITableViewAdjustHeightToFitContents(_tableView);
    
    [self _updateToolbarButtons];
}

- (void)_editServerAccount:(OFXServerAccount *)account;
{
    OBPRECONDITION(account);
    
    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAccount:account ofType:account.type];
    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil){
        if (errorOrNil) {
            [self.navigationController popViewControllerAnimated:YES];
        } else {
            // New account successfully added -- close the Cloud Setup sheet
            [self.navigationController popViewControllerAnimated:YES];
        }
    };
    
    [self.navigationController pushViewController:setup animated:YES];
}

- (void)_updateToolbarButtons;
{
    [self.editButtonItem setEnabled:[_accounts count] > 0];
}

@end
