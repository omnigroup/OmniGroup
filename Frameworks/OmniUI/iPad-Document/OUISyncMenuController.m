// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUISyncMenuController.h"

#import <MobileCoreServices/MobileCoreServices.h>
#import <OmniDAV/ODAVFileInfo.h>
#import <OmniDocumentStore/ODSFileItem.h>
#import <OmniDocumentStore/ODSStore.h>
#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIBarButtonItem.h>
#import <OmniUI/UITableView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>

#import "OUICloudSetupViewController.h"
#import "OUIExportOptionsController.h"
#import "OUIWebDAVSyncListController.h"
#import "OUIServerAccountSetupViewController.h"
#import "OUIRestoreSampleDocumentListController.h"
#import "OUISheetNavigationController.h"

RCS_ID("$Id$")

@interface OUISyncMenuController (/*Private*/) <UIPopoverControllerDelegate, UIActionSheetDelegate, UITableViewDelegate, UITableViewDataSource>
@end

enum {
    AccountsSection,
    CloudSetupSection,
    ResetSampleDocumentSection,
    SectionCount,
};

@implementation OUISyncMenuController
{
    UITableView *_tableView;
    UIPopoverController *_menuPopoverController;
    UINavigationController *_menuNavigationController;
    OUISheetNavigationController *_sheetNavigationController;
    NSArray *_accounts;
    NSArray *_accountTypes;
    BOOL _isExporting;
}

+ (void)displayAsSheetInViewController:(UIViewController *)viewController;
{
    OUISyncMenuController *controller = [[OUISyncMenuController alloc] initForExporting:YES];
    [controller _displayAsSheetInViewController:viewController];
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- initForExporting:(BOOL)exporting;
{
    if (!(self = [super init]))
        return nil;
    
    _isExporting = exporting;
    
    NSMutableArray *accountTypes = [NSMutableArray arrayWithArray:[OFXServerAccountType accountTypes]];
    [accountTypes removeObject:[OFXServerAccountType accountTypeWithIdentifier:OFXiTunesLocalDocumentsServerAccountTypeIdentifier]]; // Can't add/remove this account type
    _accountTypes = [accountTypes copy];
    
    return self;
}

- (void)dealloc;
{
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (void)showMenuFromBarItem:(UIBarButtonItem *)barItem;
{
    OBPRECONDITION(_sheetNavigationController == nil);
    
    [self _reloadAccountsAndAdjustSize];
    
    self.preferredContentSize = self.view.frame.size; // Make sure we set this before creating our popover

    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Import Document\u2026", @"OmniUIDocument", OMNI_BUNDLE, @"Import document title");
    
    [self _updateToolbarButtons];
    
    if (!_menuNavigationController) {
        _menuNavigationController = [[UINavigationController alloc] initWithRootViewController:self];
        _menuNavigationController.navigationBarHidden = NO;
    }
    if (!_menuPopoverController) {
        _menuPopoverController = [[UIPopoverController alloc] initWithContentViewController:_menuNavigationController];
        _menuPopoverController.delegate = self;
    }
    
    [[OUIAppController controller] presentPopover:_menuPopoverController fromBarButtonItem:barItem permittedArrowDirections:UIPopoverArrowDirectionUp animated:YES];
}

@synthesize isExporting = _isExporting;

#pragma mark - UIViewController subclass

- (void)loadView;
{
    OBPRECONDITION(_tableView == nil);

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 0) style:UITableViewStyleGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.scrollEnabled = NO;

    self.view = _tableView;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];

    [self.view sizeToFit];
}

- (BOOL)shouldAutorotate;
{
    return YES;
}

- (void)viewWillAppear:(BOOL)animated;
{
    [super viewWillAppear:animated];
    [self setEditing:NO animated:NO];
    [self _reloadAccountsAndAdjustSize];
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
    NSInteger sectionCount = SectionCount;
    
    if (_isExporting)
        sectionCount--; // No ResetSampleDocumentSection when exporting

    return sectionCount;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section;
{
    if (section == AccountsSection)
        return [_accounts count];

    if (section == CloudSetupSection) {
        if ([OFXAgent hasDefaultSyncPathExtensions])
            return 1;
        return 0;
    }
    
    if (section == ResetSampleDocumentSection)
        return 1;

    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == CloudSetupSection) {
        static NSString *cloudSetupReuseIdentifier = @"cloudSetupReuseIdentifier";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cloudSetupReuseIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cloudSetupReuseIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        }
        
        cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Cloud Setup...", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title");
        cell.imageView.image = [UIImage imageNamed:@"OUIMenuItemCloudSetUp"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        
        return cell;
    }
    
    if (indexPath.section == ResetSampleDocumentSection) {
        static NSString *reuseIdentifier = @"ResetSampleDocument";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
        }

        cell.textLabel.text = [[OUIDocumentAppController controller] sampleDocumentsDirectoryTitle];
        
        return cell;
    }
    
    static NSString * const reuseIdentifier = @"ExistingServer";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
        cell.editingAccessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    }
    
    NSInteger accountIndex = indexPath.row;
    OFXServerAccount *account = [_accounts objectAtIndex:accountIndex];
    cell.textLabel.text = _isExporting ? account.exportTitle : account.importTitle;
    cell.detailTextLabel.text = account.accountDetailsString;
    
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
    OBPRECONDITION(self.editing == NO); // Tapping rows doesn't select them in edit mode
    
    OUIAppController *controller = [OUIAppController controller];
    [controller dismissPopover:_menuPopoverController animated:YES];
    
    if (indexPath.section == CloudSetupSection) {
        
        // Don't allow cloud setup in retail demo builds.
        if ([controller isRunningRetailDemo]) {
            [controller showFeatureDisabledForRetailDemoAlert];
        }
        else {
            OUICloudSetupViewController *setup = [[OUICloudSetupViewController alloc] init];
            UIViewController *presentingViewController = self.presentingViewController;
            
            if (_isExporting) {
                [presentingViewController dismissViewControllerAnimated:YES completion:^{
                    [presentingViewController presentViewController:setup animated:YES completion:nil];
                }];
            }
            else {
                [presentingViewController presentViewController:setup animated:YES completion:nil];
            }
        }
        return;
    }

    if (indexPath.section == ResetSampleDocumentSection) {
        [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        [[OUIAppController controller] restoreSampleDocuments:nil];
        return;
    }

    // We can't do the editing of existing accounts here -- while in edit mode, rows aren't selectable
    NSInteger accountIndex = indexPath.row;
    if ((NSUInteger)accountIndex >= [_accounts count]) {
        NSUInteger accountTypeIndex = accountIndex - [_accounts count];
        OBASSERT(accountTypeIndex < [_accountTypes count]);
        OFXServerAccountType *accountType = [_accountTypes objectAtIndex:accountTypeIndex];
        [self _editServerAccount:nil ofType:accountType];
    } else {
        OFXServerAccount *account = [_accounts objectAtIndex:accountIndex];
        [self _connectUsingAccount:account inNewSheet:NO];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(self.editing);
    
    if (indexPath.section == ResetSampleDocumentSection) {
        OBASSERT_NOT_REACHED("Should have no accessory button in edit mode");
        return;
    }
    
    // Edit settings on an existing server?
    NSInteger accountIndex = indexPath.row;
    if ((NSUInteger)accountIndex < [_accounts count]) {
        [[OUIAppController controller] dismissPopover:_menuPopoverController animated:YES];

        OFXServerAccount *account = [_accounts objectAtIndex:accountIndex];
        [self _editServerAccount:account ofType:account.type];
    }
}

// We use this, instead of -tableView:canEditRowAtIndexPath: since this lets the left edge of the non-editable Add Account rows move with existing accounts rather than staying outdented and thus tearing the edge of the table view.
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == ResetSampleDocumentSection) {
        return UITableViewCellEditingStyleNone;
    }

    NSInteger accountIndex = indexPath.row;
    if ((NSUInteger)accountIndex >= [_accounts count]) {
        return UITableViewCellEditingStyleNone; // One of the 'add' rows
    }
    
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section != AccountsSection) {
        OBASSERT_NOT_REACHED("Shouldn't be able to edit this row");
        return;
    }
    
    NSInteger accountIndex = indexPath.row;
    if ((NSUInteger)accountIndex >= [_accounts count]) {
        OBASSERT_NOT_REACHED("Shouldn't be able to edit this row");
        return;
    }
    
    OFXServerAccount *account = [_accounts objectAtIndex:accountIndex];
    [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:account withCancelAction:NULL discardAction:^{
        [account prepareForRemoval];

        NSMutableArray *accounts = [_accounts mutableCopy];
        NSUInteger accountIndex = [accounts indexOfObjectIdenticalTo:account];
        [accounts removeObject:account];
        _accounts = [accounts copy];

        [_tableView beginUpdates];
        [_tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:accountIndex inSection:AccountsSection]] withRowAnimation:UITableViewRowAnimationFade];
        [_tableView endUpdates];


        // Edit editing mode if this was the last editable object
        if ([_accounts count] == 0) {
            [self setEditing:NO animated:YES];
            [self _updateToolbarButtons];
        }
    }];
}

#pragma mark - UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    _menuPopoverController.delegate = nil;
    _menuPopoverController = nil;
    
    _menuNavigationController = nil;

    // Don't keep the popover controller alive needlessly.
    [[OUIAppController controller] forgetPossiblyVisiblePopoverIfAlreadyHidden];
}

#pragma mark - Private

- (void)_cancel:(id)sender;
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)_displayAsSheetInViewController:(UIViewController *)viewController;
{
    OBPRECONDITION(self.navigationController == nil);
    OBPRECONDITION(_sheetNavigationController == nil);
    
    self.navigationItem.leftBarButtonItem = [[OUIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(_cancel:)];
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Export", @"OmniUIDocument", OMNI_BUNDLE, @"export options title");
    
    // This retain cycle gets cleared when the sheet is dismissed in -_popViewControllerInSheet
    _sheetNavigationController = [[OUISheetNavigationController alloc] initWithRootViewController:self];
    _sheetNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
    _sheetNavigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;

    [viewController presentViewController:_sheetNavigationController animated:YES completion:nil];
}

- (void)_pushViewControllerInSheet:(UIViewController *)viewController inNewSheet:(BOOL)inNewSheet;
{
    [[OUIAppController controller] dismissPopover:_menuPopoverController animated:YES];
    
    if (!_sheetNavigationController) {
        _sheetNavigationController = [[OUISheetNavigationController alloc] initWithRootViewController:viewController];
        _sheetNavigationController.modalPresentationStyle = UIModalPresentationFormSheet;
        _sheetNavigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        [viewController presentViewController:_sheetNavigationController animated:YES completion:nil];
    } else {
        if (inNewSheet) {
            // This path exists so that we can get rid of the keyboard shown from the previous sheet. If we instead replace the top view controller or push a new controller, the keyboard would hang out, covering up part of the file listing.
            OUISheetNavigationController *sheetController = _sheetNavigationController;
            _sheetNavigationController = nil;
            [sheetController dismissModalViewControllerAnimated:YES andPresentModalViewControllerInSheet:viewController animated:YES];
        } else
            [_sheetNavigationController pushViewController:viewController animated:YES];
    }
}

- (void)_popViewControllerInSheet;
{
    OBPRECONDITION(_sheetNavigationController);
    
    if (_sheetNavigationController.topViewController == [[_sheetNavigationController viewControllers] objectAtIndex:0]) {
        UINavigationController *previousSheet = _sheetNavigationController;
        _sheetNavigationController = nil;
        [previousSheet dismissViewControllerAnimated:YES completion:nil];
    } else {
        [_sheetNavigationController popViewControllerAnimated:YES];
    }
}

- (void)_reloadAccountsAndAdjustSize;
{
    [self view]; // Make sure our view is loaded
    OBASSERT(_tableView);
    
    OFXServerAccountRegistry *accountRegistry = [OFXServerAccountRegistry defaultAccountRegistry];
    NSMutableArray *accounts = [NSMutableArray arrayWithArray:accountRegistry.validImportExportAccounts];

    // No importing from iTunes (though iWork does by having a split between their interchange and operating document formats).
    if (!_isExporting) {
        OFXServerAccountType *iTunesAccountType = [OFXServerAccountType accountTypeWithIdentifier:OFXiTunesLocalDocumentsServerAccountTypeIdentifier];
        [accounts removeObjectsInArray:[accountRegistry accountsWithType:iTunesAccountType]];
    }
    
    [accounts sortUsingSelector:@selector(compareServerAccount:)];

    _accounts = [accounts copy];
    
    [_tableView reloadData];
    OUITableViewAdjustHeightToFitContents(_tableView);
    
    [self _updateToolbarButtons];
}

- (void)_editServerAccount:(OFXServerAccount *)account ofType:(OFXServerAccountType *)accountType;
{
    OBPRECONDITION(accountType);
    OBPRECONDITION(!account || account.type == accountType);
    
    // Add new account or edit existing one.
    OUIServerAccountSetupViewController *setup = [[OUIServerAccountSetupViewController alloc] initWithAccount:account ofType:accountType];
    setup.finished = ^(OUIServerAccountSetupViewController *vc, NSError *errorOrNil){
        if (errorOrNil)
            [self _popViewControllerInSheet];
        else {
            // Push the new view controller and pop the account setup view controller
            [self _connectUsingAccount:vc.account inNewSheet:YES];
        }
    };
    
    [self _pushViewControllerInSheet:setup inNewSheet:NO];
}

- (void)_connectUsingAccount:(OFXServerAccount *)account inNewSheet:(BOOL)inNewSheet;
{
    UIViewController *viewController;
    if (_isExporting)
        viewController = [[OUIExportOptionsController alloc] initWithServerAccount:account exportType:OUIExportOptionsExport];
    else {
        __autoreleasing NSError *error = nil;
        if (!(viewController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:account exporting:NO error:&error])) {
            OUI_PRESENT_ERROR(error);
            return;
        }
    }

    [self _pushViewControllerInSheet:viewController inNewSheet:inNewSheet];
}

- (void)_updateToolbarButtons;
{
    [self.editButtonItem setEnabled:[_accounts count] > 0];
}

@end
