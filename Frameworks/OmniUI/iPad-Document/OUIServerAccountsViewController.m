// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIServerAccountsViewController.h>

@import OmniFileExchange;

#import "OUIAddCloudAccountViewController.h"
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import <OmniUIDocument/OmniUIDocument-Swift.h>

RCS_ID("$Id$")

#pragma mark - Table view sections

typedef NS_ENUM(NSInteger, HomeScreenSections) {
    AccountsListSection,
    SetupSection,
    SectionCount,
};

typedef NS_ENUM(NSInteger, SetupSectionRows) {
    AddCloudAccountRow,
    SetupSectionRowCount,
};

#pragma mark - Cells

static NSString *const HomeScreenCellReuseIdentifier = @"documentPickerHomeScreenCell";
static NSString *const AddCloudAccountReuseIdentifier = @"documentPickerAddCloudAccount";

#pragma mark - KVO Contexts

static void *AccountCellLabelObservationContext = &AccountCellLabelObservationContext; // Keys that don't affect ordering; just need to be pushed to cells
static void *ServerAccountsObservationContext = &ServerAccountsObservationContext;

#pragma mark - Helper data types

@interface _OUIServerAccountsButtonishTableViewCell : UITableViewCell
@end

@implementation _OUIServerAccountsButtonishTableViewCell

- (void)tintColorDidChange;
{
    self.textLabel.textColor = [self tintColor];
    [super tintColorDidChange];
}

@end

#pragma mark - View Controller

@implementation OUIServerAccountsViewController
{
    OFXAgentActivity *_agentActivity;
    
    NSArray <OFXServerAccount *> *_orderedServerAccounts;
    NSMapTable <OFXServerAccount *, OFXAccountActivity *> *_observedAccountActivityByAccount;
}

+ (NSString *)localizedDisplayName;
{
    return NSLocalizedStringFromTableInBundle(@"OmniPresence Accounts", @"OmniUIDocument", OMNI_BUNDLE, @"Manage OmniPresence accounts settings title");
}

+ (NSString *)localizedDisplayDetailText;
{
    return NSLocalizedStringFromTableInBundle(@"Migrate OmniPresence accounts to other storage locations", @"OmniUIDocument", OMNI_BUNDLE, @"Manage OmniPresence accounts settings detail text");
}

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity;
{
    if (!(self = [super initWithStyle:UITableViewStyleGrouped]))
        return nil;
       
    _agentActivity = agentActivity;
    
    _observedAccountActivityByAccount = [NSMapTable strongToStrongObjectsMapTable];
    
    OFXServerAccountRegistry *accountRegistry = _agentActivity.agent.accountRegistry;
    [accountRegistry addObserver:self forKeyPath:OFValidateKeyPath(accountRegistry, allAccounts) options:NSKeyValueObservingOptionInitial context:ServerAccountsObservationContext];

    self.navigationItem.title = [[self class] localizedDisplayName];
        
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_done:)];
    
    UITableView *tableView = self.tableView;
    tableView.separatorInset = UIEdgeInsetsZero;
    
    return self;
}

- (void)dealloc;
{
    for (OFXServerAccount *account in _orderedServerAccounts) {
        [self _stopObservingServerAccount:account];
    }
    
    OFXServerAccountRegistry *accountRegistry = _agentActivity.agent.accountRegistry;
    [accountRegistry removeObserver:self forKeyPath:OFValidateKeyPath(accountRegistry, allAccounts) context:ServerAccountsObservationContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == ServerAccountsObservationContext) {
        [self _updateOrderedServerAccounts];
    } else if (context == AccountCellLabelObservationContext) {
        OFXServerAccount *account;
        NSUInteger accountIndex = [_orderedServerAccounts indexOfObject:object];
        if ([object isKindOfClass:[OFXServerAccount class]]) {
            account = object;
            accountIndex = [_orderedServerAccounts indexOfObject:account];
        } else if ([object isKindOfClass:[OFXRegistrationTable class]]) {
            account = [_orderedServerAccounts first:^BOOL(OFXServerAccount *candidate) {
                return [[_agentActivity activityForAccount:candidate] registrationTable] == object;
            }];
            accountIndex = [_orderedServerAccounts indexOfObject:account];
        }
        
        if (accountIndex != NSNotFound) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:accountIndex inSection:AccountsListSection]];
            if (cell) {
                [self _updateCell:cell forServerAccount:account];
            }
            accountIndex = [_orderedServerAccounts indexOfObject:account];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    UITableView *tableView = self.tableView;
    tableView.backgroundColor = [UIColor whiteColor];
    
    [super viewDidLoad];
}

- (void)willTransitionToTraitCollection:(UITraitCollection *)newCollection withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
{
    [super willTransitionToTraitCollection:newCollection withTransitionCoordinator:coordinator];
    
    // Dismiss any presented view controller if presented as a popover
    if (self.presentedViewController.popoverPresentationController != nil) {
        [self.presentedViewController dismissViewControllerAnimated:YES completion:^{
        }];
    }

}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator NS_AVAILABLE_IOS(8_0);
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - API

- (void)_accountActivityForAccountChangedNotification:(NSNotification *)note;
{
    OFXServerAccount *account = OB_CHECKED_CAST(OFXServerAccount, note.object);
    OFXAccountActivity *accountActivity = [_agentActivity activityForAccount:account];
    [self _updateAccountActivity:accountActivity forServerAccount:account];
}

- (void)_updateAccountActivity:(OFXAccountActivity *)newAccountActivity forServerAccount:(OFXServerAccount *)account;
{
    OFXAccountActivity *oldAccountActivity = [_observedAccountActivityByAccount objectForKey:account];
    
    if (oldAccountActivity == newAccountActivity) {
        return;
    }
    if (oldAccountActivity) {
        OFXRegistrationTable *table = oldAccountActivity.registrationTable;
        [table removeObserver:self forKeyPath:OFValidateKeyPath(table, values) context:AccountCellLabelObservationContext];
        [_observedAccountActivityByAccount removeObjectForKey:account];
    }
    if (newAccountActivity) {
        [_observedAccountActivityByAccount setObject:newAccountActivity forKey:account];
        OFXRegistrationTable *table = newAccountActivity.registrationTable;
        [table addObserver:self forKeyPath:OFValidateKeyPath(table, values) options:0 context:AccountCellLabelObservationContext];
    }
}

- (void)_startObservingServerAccount:(OFXServerAccount *)account;
{
    OBASSERT([_observedAccountActivityByAccount objectForKey:account] == nil);
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_accountActivityForAccountChangedNotification:) name:OFXAgentActivityActivityForAccountDidChangeNotification object:account];

    OFXAccountActivity *accountActivity = [_agentActivity activityForAccount:account];
    [self _updateAccountActivity:accountActivity forServerAccount:account];
    
    [account addObserver:self forKeyPath:OFValidateKeyPath(account, displayName) options:0 context:AccountCellLabelObservationContext];
}

- (void)_stopObservingServerAccount:(OFXServerAccount *)account;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:OFXAgentActivityActivityForAccountDidChangeNotification object:account];

    [self _updateAccountActivity:nil forServerAccount:account];

    [account removeObserver:self forKeyPath:OFValidateKeyPath(account, displayName) context:AccountCellLabelObservationContext];
}

- (void)_updateOrderedServerAccounts;
{
    OFXServerAccountRegistry *accountRegistry = _agentActivity.agent.accountRegistry;
    NSMutableArray <OFXServerAccount *> *accountsToRemove = [_orderedServerAccounts mutableCopy];
    NSMutableArray <OFXServerAccount *> *accountsToAdd = [[NSMutableArray alloc] initWithArray: accountRegistry.allAccounts];
    
    NSMutableArray *newOrderedServerAccounts = [accountsToAdd mutableCopy];
    [newOrderedServerAccounts sortUsingComparator:^NSComparisonResult(OFXServerAccount *accountA, OFXServerAccount *accountB){
        return [accountA.displayName localizedStandardCompare:accountB.displayName];
    }];
    
    for (OFXServerAccount *account in accountsToAdd)
        [accountsToRemove removeObject:account];

    for (OFXServerAccount *account in _orderedServerAccounts)
        [accountsToAdd removeObject:account];

    UITableView *tableView = self.tableView;
    [tableView beginUpdates];

    for (OFXServerAccount *account in accountsToRemove) {
        [self _stopObservingServerAccount:account];
        
        NSUInteger indexToDelete = [_orderedServerAccounts indexOfObject:account];
        if (indexToDelete == NSNotFound)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to delete an account that isn't in our table view data source!" userInfo:@{@"account" : account}];
        
        [tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:indexToDelete inSection:AccountsListSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    }

    _orderedServerAccounts = [newOrderedServerAccounts copy];
    
    for (OFXServerAccount *account in accountsToAdd) {
        [self _startObservingServerAccount:account];
        
        NSUInteger indexToAdd = [_orderedServerAccounts indexOfObject:account];
        if (indexToAdd == NSNotFound)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to add an account that isn't in our table view data source!" userInfo:@{@"account" : account}];
        
        [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:indexToAdd inSection:AccountsListSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    }

    [tableView endUpdates];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return SectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    switch (section) {
        case AccountsListSection:
            return _orderedServerAccounts.count;
        case SetupSection:
            return SetupSectionRowCount;
    }

    OBASSERT_NOT_REACHED("Unknown section!");
    return 0;
}

- (void)editSettingsForAccount:(OFXServerAccount *)account;
{
    [self _editAccountSettings:account sender:self.tableView];
}

- (void)_updateCell:(UITableViewCell *)cell forServerAccount:(OFXServerAccount *)account;
{
    OBASSERT_NOTNULL(cell);
    
    static UIImage *cloudImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cloudImage = [[UIImage imageNamed:@"OUIDocumentPickerCloudLocationIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    
    cell.textLabel.text = account.displayName;

    OFXAccountActivity *accountActivity = [_observedAccountActivityByAccount objectForKey:account];
    if (accountActivity) {
        NSSet <OFXFileMetadata *> *metadataItems = accountActivity.registrationTable.values;
        NSMutableArray <NSString *> *metadataStrings = [NSMutableArray array];
        
        [metadataStrings addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%d items", @"OmniUIDocument", OMNI_BUNDLE, @"home screen detail label"), metadataItems.count]];
        
        if ([metadataItems count] > 0) {
            NSUInteger totalSize = 0;
            for (OFXFileMetadata *item in metadataItems) {
                totalSize += item.fileSize;
            }
            
            [metadataStrings addObject:[NSByteCountFormatter stringFromByteCount:totalSize countStyle:NSByteCountFormatterCountStyleFile]];
        }
        
        cell.detailTextLabel.text = [metadataStrings componentsJoinedByString:@" • "];
    } else {
        cell.detailTextLabel.text = @"";
    }

    cell.imageView.image = cloudImage;
    cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = nil;
    cell.detailTextLabel.textColor = nil;
    cell.tintAdjustmentMode = UIViewTintAdjustmentModeAutomatic;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case AccountsListSection: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:HomeScreenCellReuseIdentifier];
            if (!cell)
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:HomeScreenCellReuseIdentifier];

            OFXServerAccount *account = _orderedServerAccounts[indexPath.row];
            [self _updateCell:cell forServerAccount:account];

            return cell;
        }

        case SetupSection: {
            if (indexPath.row == AddCloudAccountRow) {
                _OUIServerAccountsButtonishTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AddCloudAccountReuseIdentifier];
                if (!cell)
                    cell = [[_OUIServerAccountsButtonishTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:AddCloudAccountReuseIdentifier];
                cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Add OmniPresence Account", @"OmniUIDocument", OMNI_BUNDLE, @"home screen button label");
                cell.textLabel.textColor = [self.view tintColor];
                return cell;
            }
        }
    }
    
    OBASSERT_NOT_REACHED("Unknown row!");
    return nil;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Explicitly disable deleting, because the user can delete the account from the account details, and we'd like a chance to offer a confirmation if there are unsynced edits.
    return UITableViewCellEditingStyleNone;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == AccountsListSection)
        return [[OmniUIDocumentAppearance appearance] serverAccountRowHeight];
    else
        return [[OmniUIDocumentAppearance appearance] serverAccountAddRowHeight];
}

- (void)_editAccountSettings:(OFXServerAccount *)account sender:(id)sender;
{
    OUIServerAccountSetupViewController *setupController = [[OUIServerAccountSetupViewController alloc] initWithAgentActivity:_agentActivity account:account];
    setupController.finished = ^(id viewController, NSError *error) { };
    [self showViewController:setupController sender:sender];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
    case AccountsListSection: {
        OFXServerAccount *account = _orderedServerAccounts[indexPath.row];
        [self _editAccountSettings:account sender:tableView];
        break;
    }
        
        case SetupSection:
            OBPRECONDITION(indexPath.row == AddCloudAccountRow);

            if ([[OUIAppController controller] showFeatureDisabledForRetailDemoAlertFromViewController:self]) {
                // Early out if we are currently in retail demo mode.
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }

        OUIAddCloudAccountViewController *addController = [[OUIAddCloudAccountViewController alloc] initWithAgentActivity:_agentActivity usageMode:OFXServerAccountUsageModeCloudSync];
            addController.finished = ^(OFXServerAccount *newAccountOrNil) {
                [self.navigationController popToViewController:self animated:YES];
            };

            [self.navigationController pushViewController:addController animated:YES];
            break;
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return indexPath.section == AccountsListSection;
}

- (void)tableView:(UITableView*)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // This method is a no-op because implementing it prevents UITableView from sending -setEditing:animated when the users swipes-to-delete.
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // This method is a no-op, but it's necessary because UITableView will send -setEditing:NO without it (even though it never sent the corresponding -setEditing:YES due to the above implementation of -tableView:willBeginEditingRowAtIndexPath:)
}

#pragma mark - OUIDisabledDemoFeatureAlerter

- (NSString *)featureDisabledForDemoAlertTitle
{
    return NSLocalizedStringFromTableInBundle(@"OmniPresence is disabled in this demo version.", @"OmniUIDocument", OMNI_BUNDLE, @"demo disabled title");
}

- (NSString *)featureDisabledForDemoAlertMessage
{
    return NSLocalizedStringFromTableInBundle(@"OmniPresence allows you to use our free sync service or any compatible WebDAV server to automatically share documents between your devices, or to keep copies of your documents in the cloud in case you need to restore your device.", @"OmniUIDocument", OMNI_BUNDLE, @"demo disabled message");
}

#pragma mark - Private

- (void)_done:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end
