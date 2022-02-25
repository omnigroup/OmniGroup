// Copyright 2013-2022 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIServerAccountsViewController.h>

@import OmniFileExchange;

#import <OmniUIDocument/OmniUIDocument-Swift.h>
#import <OmniUIDocument/OmniUIDocumentAppearance.h>

#import "OUIAddCloudAccountViewController.h"
#import "OUIDocumentSyncActivityObserver.h"

@import UniformTypeIdentifiers;

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

static NSString *const ServerAccountCellReuseIdentifier = @"OUIServerAccounts.Account";
static NSString *const AddCloudAccountReuseIdentifier = @"OUIServerAccounts.AddAccount";

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

@interface _OUIServerAccountsActionHolder : UIResponder
+ (_OUIServerAccountsActionHolder *)actionHolderWithBlock:(void (^)(id sender))actionBlock;
@property (nonatomic, copy) void (^actionBlock)(id sender);
- (IBAction)_action:(id)sender;
@end

@interface _OUIServerAccountsViewControllerFolderPicker: NSObject
+ (void)pickFolderInViewController:(UIViewController *)viewController withCompletionBlock:(void (^)(NSURL * _Nullable))completionBlock;
@end


#pragma mark - View Controller

@implementation OUIServerAccountsViewController
{
    OUIDocumentSyncActivityObserver *_observer;
    NSArray <OFXServerAccount *> *_orderedServerAccounts;
    BOOL _isForBrowsing;
}

+ (NSString *)localizedDisplayNameForBrowsing:(BOOL)isForBrowsing;
{
    if (isForBrowsing) {
        return NSLocalizedStringFromTableInBundle(@"View OmniPresence Documents", @"OmniUIDocument", OMNI_BUNDLE, @"Screen title for viewing OmniPresence documents");
    } else {
        return NSLocalizedStringFromTableInBundle(@"Configure OmniPresence Syncing", @"OmniUIDocument", OMNI_BUNDLE, @"Screen title for configuring OmniPresence accounts");
    }
}

- (instancetype)initWithAgentActivity:(OFXAgentActivity *)agentActivity forBrowsing:(BOOL)isForBrowsing;
{
    self = [super initWithStyle:isForBrowsing ? UITableViewStylePlain : UITableViewStyleGrouped];
    if (self == nil)
        return nil;
    
    _isForBrowsing = isForBrowsing;
    _observer = [[OUIDocumentSyncActivityObserver alloc] initWithAgentActivity:agentActivity];
    
    __weak OUIServerAccountsViewController *weakSelf = self;
    _observer.accountsUpdated = ^(NSArray<OFXServerAccount *> * _Nonnull updatedAccounts, NSArray<OFXServerAccount *> * _Nonnull addedAccounts, NSArray<OFXServerAccount *> * _Nonnull removedAccounts) {
        [weakSelf _accountsUpdated:updatedAccounts addedAccounts:addedAccounts removedAccounts:removedAccounts];
    };
    
    _observer.accountChanged = ^(OFXServerAccount *account){
        [weakSelf _accountChanged:account];
    };
    
    _orderedServerAccounts = [_observer.orderedServerAccounts copy];
    
    self.navigationItem.title = [[self class] localizedDisplayNameForBrowsing:isForBrowsing];
        
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(_done:)];
    
    UITableView *tableView = self.tableView;
    tableView.separatorInset = UIEdgeInsetsZero;
    
    return self;
}

#pragma mark - UIViewController subclass

- (void)viewDidLoad;
{
    UITableView *tableView = self.tableView;
    tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return _isForBrowsing ? 1 : SectionCount;
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
    
    static dispatch_once_t onceToken;
    static UIImage *accountIconImage;
    static UIImage *accountSetupImage;
    static UIImage *accountFolderImage;
    dispatch_once(&onceToken, ^{
        accountIconImage = [[UIImage imageNamed:@"OmniPresenceAccountIcon" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        accountSetupImage = [[UIImage imageNamed:@"OmniPresenceAccountInfo" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        accountFolderImage = [[UIImage imageNamed:@"OUIMenuItemFolder" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    
    cell.textLabel.text = account.displayName;
    id <OUIDocumentServerAccountSyncAccountStatus> syncAccountStatus = [OUIDocumentServerAccountFileListViewFactory syncAccountStatusWithServerAccount:account observer:_observer];
    BOOL hasErrorStatus = syncAccountStatus.hasErrorStatus;
    NSString *syncStatusText = syncAccountStatus.statusText;
    if (hasErrorStatus && syncStatusText != nil) {
        cell.detailTextLabel.text = syncStatusText;
        cell.detailTextLabel.textColor = UIColor.systemRedColor;
    } else {
        NSMutableArray <NSString *> *metadataStrings = [NSMutableArray array];
        OFXAccountActivity *accountActivity = [_observer accountActivityForServerAccount:account];
        if (accountActivity != nil) {
            NSSet <OFXFileMetadata *> *metadataItems = accountActivity.registrationTable.values;

            [metadataStrings addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%d items", @"OmniUIDocument", OMNI_BUNDLE, @"home screen detail label"), (int)metadataItems.count]];

            if ([metadataItems count] > 0) {
                NSUInteger totalSize = 0;
                for (OFXFileMetadata *item in metadataItems) {
                    totalSize += item.fileSize;
                }

                [metadataStrings addObject:[NSByteCountFormatter stringFromByteCount:totalSize countStyle:NSByteCountFormatterCountStyleFile]];
            }
        }

        if (syncStatusText != nil)
            [metadataStrings addObject:syncStatusText];
        NSString *statusText = [metadataStrings componentsJoinedByString:@" • "];
        cell.detailTextLabel.text = statusText;
        cell.detailTextLabel.textColor = nil;
    }

    cell.imageView.image = accountIconImage;
    cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = nil;
    cell.tintAdjustmentMode = UIViewTintAdjustmentModeAutomatic;

    if (!_isForBrowsing)
        return;

    __weak OUIServerAccountsViewController *weakSelf = self;
    _OUIServerAccountsActionHolder *editAction = [_OUIServerAccountsActionHolder actionHolderWithBlock:^(id sender) {
        OUIServerAccountsViewController *strongSelf = weakSelf;
        if (strongSelf == nil)
            return;
        if ([strongSelf _showFolderForAccount:account]) {
            [strongSelf _done:nil];
        }
    }];

    objc_setAssociatedObject(cell, @"accessoryViewTargetActionHolder", editAction, OBJC_ASSOCIATION_RETAIN); // Make sure this action holder sticks around until we reuse the cell for something else
    cell.accessoryView = [UIButton systemButtonWithImage:accountFolderImage target:editAction action:@selector(_action:)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    switch (indexPath.section) {
        case AccountsListSection: {
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ServerAccountCellReuseIdentifier];
            if (!cell)
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ServerAccountCellReuseIdentifier];

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
    OUIServerAccountSetupViewController *setupController = [[OUIServerAccountSetupViewController alloc] initWithAgentActivity:_observer.agentActivity account:account];
    setupController.finished = ^(id viewController, NSError *error) { };
    [self showViewController:setupController sender:sender];
}

- (void)_openFileListForAccount:(OFXServerAccount *)account sender:(id)sender;
{
    [self _showFolderForAccount:account];
    OUIDocumentSyncActivityObserver *observer = [[OUIDocumentSyncActivityObserver alloc] initWithAgentActivity:_observer.agentActivity];
    UIViewController *fileListViewController = [OUIDocumentServerAccountFileListViewFactory fileListViewControllerWithServerAccount:account observer:observer];
    [self showViewController:fileListViewController sender:sender];
}

- (BOOL)_showFolderForAccount:(OFXServerAccount *)account;
{
    OUIDocumentSceneDelegate *sceneDelegate = self.tableView.sceneDelegate;

    // We can't reveal the account's documents if the local documents folder is missing.
    if ([account.lastError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXLocalAccountDocumentsDirectoryMissing] ||
        [account.lastError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXCannotResolveLocalDocumentsURL]) {
        [self _editAccountSettings:account sender:self.tableView];
        return NO;
    } else {
        [sceneDelegate openFolderForServerAccount:account];
        return YES;
    }
}

- (void)_recoverLocalDocumentsDirectoryForAccount:(OFXServerAccount *)account;
{
    [_OUIServerAccountsViewControllerFolderPicker pickFolderInViewController:self withCompletionBlock:^(NSURL * _Nullable folderURL) {
#ifdef DEBUG_kc
        NSLog(@"DEBUG: Picked %@", [folderURL absoluteString]);
#endif
        [account recoverLostLocalDocumentsURL:folderURL];
        [account clearError];
        [_observer.agentActivity.agent sync:NULL];
    }];
}

- (void)_showAccount:(OFXServerAccount *)account;
{
    // We can't browse the account's documents if the local documents folder is missing.
    if (_isForBrowsing) {
        if ([account.lastError hasUnderlyingErrorDomain:OFXErrorDomain code:OFXLocalAccountDocumentsDirectoryMissing]) {
            [self _recoverLocalDocumentsDirectoryForAccount:account];
        } else {
            [self _openFileListForAccount:account sender:self.tableView];
        }
    } else {
        [self _editAccountSettings:account sender:self.tableView];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.section) {
        case AccountsListSection: {
            OFXServerAccount *account = _orderedServerAccounts[indexPath.row];
            [self _showAccount:account];
            break;
        }

        case SetupSection:
            OBPRECONDITION(indexPath.row == AddCloudAccountRow);

            if ([[OUIAppController controller] showFeatureDisabledForRetailDemoAlertFromViewController:self]) {
                // Early out if we are currently in retail demo mode.
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }

            OUIAddCloudAccountViewController *addController = [[OUIAddCloudAccountViewController alloc] initWithAgentActivity:_observer.agentActivity usageMode:OFXServerAccountUsageModeCloudSync];
            addController.finished = ^(OFXServerAccount *newAccountOrNil) {
                [self.navigationController popToViewController:self animated:YES];
                if (newAccountOrNil != nil) {
                    [self.sceneDelegate openFolderForServerAccount:newAccountOrNil];
                }
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

- (void)_accountsUpdated:(NSArray <OFXServerAccount *> *)updatedAccounts addedAccounts:(NSArray <OFXServerAccount *> *)addedAccounts removedAccounts:(NSArray <OFXServerAccount *> *)removedAccounts;
{
    UITableView *tableView = self.tableView;
    [tableView beginUpdates];
    
    for (OFXServerAccount *account in removedAccounts) {
        NSUInteger indexToDelete = [_orderedServerAccounts indexOfObject:account];
        if (indexToDelete == NSNotFound)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to delete an account that isn't in our table view data source!" userInfo:@{@"account" : account}];
        
        [tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:indexToDelete inSection:AccountsListSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    
    _orderedServerAccounts = [updatedAccounts copy];
    
    for (OFXServerAccount *account in addedAccounts) {
        NSUInteger indexToAdd = [_orderedServerAccounts indexOfObject:account];
        if (indexToAdd == NSNotFound)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to add an account that isn't in our table view data source!" userInfo:@{@"account" : account}];
        
        [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:indexToAdd inSection:AccountsListSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    
    [tableView endUpdates];
}

- (void)_accountChanged:(OFXServerAccount *)account;
{
    NSUInteger accountIndex = [_orderedServerAccounts indexOfObject:account];
    if (accountIndex != NSNotFound) {
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:accountIndex inSection:AccountsListSection]];
        if (cell) {
            [self _updateCell:cell forServerAccount:account];
        }
    }
}

- (void)_done:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation _OUIServerAccountsActionHolder

+ (_OUIServerAccountsActionHolder *)actionHolderWithBlock:(void (^)(id sender))actionBlock;
{
    _OUIServerAccountsActionHolder *actionHolder = [[_OUIServerAccountsActionHolder alloc] init];
    actionHolder.actionBlock = actionBlock;
    return actionHolder;
}

- (IBAction)_action:(id)sender;
{
    self.actionBlock(sender);
}

@end

@interface _OUIServerAccountsViewControllerFolderPicker () <UIDocumentPickerDelegate>
@property (nonatomic, copy) void (^completionBlock)(NSURL * _Nullable);
@end

@implementation _OUIServerAccountsViewControllerFolderPicker

static NSMutableArray *activeInstances;

+ (void)initialize;
{
    OBINITIALIZE;

    activeInstances = [[NSMutableArray alloc] init];
}

+ (void)pickFolderInViewController:(UIViewController *)viewController withCompletionBlock:(void (^)(NSURL * _Nullable))completionBlock;
{
    _OUIServerAccountsViewControllerFolderPicker *delegate = [[self alloc] init];
    delegate.completionBlock = completionBlock;
    [activeInstances addObject:delegate];

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
    picker.delegate = delegate;
    picker.directoryURL = OFUserDocumentsDirectoryURL();
    picker.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    [viewController presentViewController:picker animated:YES completion:^{}];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray <NSURL *>*)urls API_AVAILABLE(ios(11.0));
{
    self.completionBlock(urls.firstObject);
    controller.delegate = nil;
    [activeInstances removeObject:self];
}

@end
