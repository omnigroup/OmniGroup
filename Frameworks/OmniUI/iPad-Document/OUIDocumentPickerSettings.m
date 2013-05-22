// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIDocumentPickerSettings.h"

#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXDocumentStoreScope.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileStore/OFSDocumentStoreScope.h>
#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>
#import <OmniUIDocument/OUIDocumentPickerItemSort.h>
#import <OmniUI/UITableView-OUIExtensions.h>

#import "OUICloudSetupViewController.h"
#import "OUIWebDAVSyncListController.h"

RCS_ID("$Id$");

enum {
    SettingSectionLocalScope,
    SettingSectionCloudScope,
    SettingSectionImport,
    SettingSectionCloudSetup,
    SettingSectionCount,
};

@interface OUIDocumentPickerSettings () <UITableViewDataSource, UITableViewDelegate, UIPopoverControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic, strong) UINavigationController *navController;
@property (nonatomic, strong) UIViewController *rootViewController;
@property (nonatomic, strong) UITableView *locationsTableView;

@property (nonatomic, retain) NSArray *localDocumentScopes;
@property (nonatomic, retain) NSArray *cloudDocumentScopes;

@end

@implementation OUIDocumentPickerSettings
{
    UIPopoverController *_filterPopoverController;
    CGFloat _defaultSectionHeaderHeight;
    CGFloat _defaultSectionFooterHeight;
}

- (void)showFromView:(UIView *)view;
{
    OBStrongRetain(self); // Stay alive while our popover is up
    
    if ([[OUIAppController controller] dismissPopover:_filterPopoverController animated:YES]) {
        OBASSERT(_filterPopoverController == nil); // delegate method should have been called
        return;
    }
    
    self.rootViewController = [[UIViewController alloc] init];
    self.rootViewController.title = NSLocalizedStringFromTableInBundle(@"Browse", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title");

    self.locationsTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 0) style:UITableViewStyleGrouped];

    // Remember the default heights and set the fallbacks to zero (returning zero from the delegate uses these properties).
    _defaultSectionHeaderHeight = self.locationsTableView.sectionHeaderHeight;
    _defaultSectionFooterHeight = self.locationsTableView.sectionFooterHeight;
    self.locationsTableView.sectionHeaderHeight = 0;
    self.locationsTableView.sectionFooterHeight = 0;
    
    self.rootViewController.view = self.locationsTableView;
    
    self.locationsTableView.autoresizingMask = 0;
    self.locationsTableView.delegate = self;
    self.locationsTableView.dataSource = self;
    
    [self.locationsTableView reloadData];
    OUITableViewAdjustHeightToFitContents(self.locationsTableView);
    self.locationsTableView.scrollEnabled = NO;
    
    CGSize contentSize = CGSizeMake(320, self.locationsTableView.frame.size.height);
    [self.rootViewController setContentSizeForViewInPopover:contentSize];

    self.navController = [[UINavigationController alloc] initWithRootViewController:self.rootViewController];
    self.navController.delegate = self;
    _filterPopoverController = [[UIPopoverController alloc] initWithContentViewController:self.navController];
    _filterPopoverController.delegate = self;
    
    [[OUIAppController controller] presentPopover:_filterPopoverController fromRect:view.bounds inView:view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)dealloc;
{
    OBPRECONDITION(_filterPopoverController == nil); // We are retained while it is up...
}

- (void)setAvailableScopes:(NSArray *)availableScopes;
{
    _availableScopes = [availableScopes copy];
    
    NSPredicate *localScopePredicate = [NSPredicate predicateWithBlock:^BOOL(OFSDocumentStoreScope *evaluatedScope, NSDictionary *bindings) {
        return [evaluatedScope isKindOfClass:[OFSDocumentStoreLocalDirectoryScope class]];
    }];
    self.localDocumentScopes = [_availableScopes filteredArrayUsingPredicate:localScopePredicate];
    
    NSPredicate *nonLocalScopePredicate = [NSPredicate predicateWithBlock:^BOOL(OFSDocumentStoreScope *evaluatedScope, NSDictionary *bindings) {
        return ![evaluatedScope isKindOfClass:[OFSDocumentStoreLocalDirectoryScope class]];
    }];
    self.cloudDocumentScopes = [_availableScopes filteredArrayUsingPredicate:nonLocalScopePredicate];
}

#pragma mark - UITableViewDataSource protocol

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    return SettingSectionCount;
}

- (NSInteger)tableView:(UITableView *)aTableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case SettingSectionLocalScope:
            return [self.localDocumentScopes count];
        case SettingSectionCloudScope:
            return [self.cloudDocumentScopes count];
        case SettingSectionImport:
            return [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] count];
            
        case SettingSectionCloudSetup:
            if ([OFXAgent hasDefaultSyncPathExtensions])
                return 1;
            return 0;
            
        default:
            OBASSERT_NOT_REACHED("Unknown setting section");
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    static NSString * const CellIdentifier = @"FilterCellIdentifier";
    
    // Dequeue or create a cell of the appropriate type.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }

    NSInteger row = indexPath.row;
    
    switch (indexPath.section) {
        case SettingSectionLocalScope:
        case SettingSectionCloudScope: {
            OUIDocumentAppController *appController = (OUIDocumentAppController *)[(UIApplication *)[UIApplication sharedApplication] delegate];
            OFSDocumentStoreScope *scope = (indexPath.section == SettingSectionLocalScope) ? [self.localDocumentScopes objectAtIndex:row] : [self.cloudDocumentScopes objectAtIndex:row];
            cell.textLabel.text = scope.displayName;
            cell.imageView.image = [UIImage imageNamed:scope.settingsImageName];
            cell.accessoryType = (appController.documentPicker.selectedScope == scope) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            break;
        }
            
        case SettingSectionImport: {
            OFXServerAccount *account = [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] objectAtIndex:row];
            cell.textLabel.text = account.displayName;
            cell.imageView.image = [UIImage imageNamed:@"OUIGenericWebDAV"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
        
        case SettingSectionCloudSetup: {
            cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Cloud Setup...", @"OmniUIDocument", OMNI_BUNDLE, @"App menu item title");
            cell.imageView.image = [UIImage imageNamed:@"OUIMenuItemCloudSetUp"];
            cell.accessoryType = UITableViewCellAccessoryNone;
            break;
        }
            
            
        default:
            OBASSERT_NOT_REACHED("Unknown setting section");
            return 0;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
    NSInteger numberOfRowsInSection = [self tableView:tableView numberOfRowsInSection:section];
    
    switch (section) {
        case SettingSectionLocalScope:
        case SettingSectionCloudSetup:
            return nil;
            
        case SettingSectionCloudScope:
            if (numberOfRowsInSection == 0) {
                return nil;
            }
            else {
                return NSLocalizedStringFromTableInBundle(@"OmniPresence Folders", @"OmniUIDocument", OMNI_BUNDLE, @"OmniPresence section title");
            }
        case SettingSectionImport:
            if (numberOfRowsInSection == 0) {
                return nil;
            }
            else {
                return NSLocalizedStringFromTableInBundle(@"Import", @"OmniUIDocument", OMNI_BUNDLE, @"Import section title");
            }
            
        default:
            OBASSERT_NOT_REACHED("Unknown setting section");
            return nil;
    }
}

#pragma mark - UITableViewDelegate protocol

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OUIDocumentPickerSettings *strongSelf = self;

    NSInteger section = indexPath.section;
    NSInteger row = indexPath.row;
    
    switch (section) {
        case SettingSectionLocalScope:
        case SettingSectionCloudScope: {
            OUIDocumentAppController *appController = (OUIDocumentAppController *)[(UIApplication *)[UIApplication sharedApplication] delegate];
            OFSDocumentStoreScope *scope = (section == SettingSectionLocalScope) ? [self.localDocumentScopes objectAtIndex:row] : [self.cloudDocumentScopes objectAtIndex:row];
            appController.documentPicker.selectedScope = scope;
            if ([scope isKindOfClass:[OFXDocumentStoreScope class]]) {
                OFXDocumentStoreScope *syncingScope = (OFXDocumentStoreScope *)scope;
                if (syncingScope.account.lastError != nil) {
                    [appController presentSyncError:syncingScope.account.lastError retryBlock:^{
                        [syncingScope.syncAgent sync:^{}];
                    }];
                }
            }
            
            NSUInteger rowsInSection = [strongSelf tableView:aTableView numberOfRowsInSection:section];
            for (NSUInteger rowIndex = 0; rowIndex < rowsInSection; rowIndex++) {
                UITableViewCell *cell = [aTableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:rowIndex inSection:section]];
                cell.accessoryType = (row == rowIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
            }
            
            [_filterPopoverController dismissPopoverAnimated:YES];
            _filterPopoverController = nil;
            
            break;
        }
        case SettingSectionImport: {
            OFXServerAccount *account = [[[OFXServerAccountRegistry defaultAccountRegistry] validImportExportAccounts] objectAtIndex:row];
            
            NSError *error = nil;
            OUIWebDAVSyncListController *webDAVListController = [[OUIWebDAVSyncListController alloc] initWithServerAccount:account exporting:NO error:&error];
            webDAVListController.title = account.displayName;
            webDAVListController.contentSizeForViewInPopover = (CGSize){ .width = 320, .height = 480 };
            
            if (!webDAVListController) {
                OUI_PRESENT_ERROR(error);
                break;
            }
            
            [self.navController pushViewController:webDAVListController animated:YES];
            break;
        }
        case SettingSectionCloudSetup: {
            OUICloudSetupViewController *setup = [[OUICloudSetupViewController alloc] init];
            OUIAppController *controller = [OUIAppController controller];
            [controller.topViewController presentViewController:setup animated:YES completion:nil];
            
            [_filterPopoverController dismissPopoverAnimated:YES];
            _filterPopoverController = nil;

            break;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown settion section");
            break;
    }        
}

// Pack the table view so that empty sections don't leave extra padding
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section;
{
    BOOL isEmptySection = ([self tableView:tableView numberOfRowsInSection:section] == 0);
    BOOL isEmptyTitle = [NSString isEmptyString:[self tableView:tableView titleForHeaderInSection:section]];
    
    if (isEmptySection) {
        return 0;
    }
    else if (!isEmptyTitle) {
        // Earlier, when we build the tablevew, we ask it for it's sectionHeaderHeight which returns 10. This height does not take into account that we may have a section which has an actual title. I can't find a way to ask the tableview what it's height would be in that circumstance. I believe the default with title is 44pt so that's what I'm using.
        return 44.0;
    }
    else {
        return _defaultSectionHeaderHeight;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section;
{
    if (section == SettingSectionCount - 1)
        return _defaultSectionFooterHeight;
    return 0;
}

#pragma mark - UIPopoverControllerDelegate

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController;
{
    _filterPopoverController = nil;
    
    // We are done!
    OBStrongRelease(self);
}

#pragma mark - UINavigationControllerDelegate
- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    if (viewController == self.rootViewController) {
        NSIndexPath *selectedIndexPath = [self.locationsTableView indexPathForSelectedRow];
        [self.locationsTableView deselectRowAtIndexPath:selectedIndexPath animated:YES];
    }
}
@end

#import <OmniFileStore/OFSDocumentStoreLocalDirectoryScope.h>

@implementation OFSDocumentStoreScope (OUIDocumentPickerSettings)
- (NSString *)settingsImageName;
{
    OBASSERT_NOT_REACHED("No default settings image defined for scopes");
    return nil;
}
@end

@implementation OFSDocumentStoreLocalDirectoryScope (OUIDocumentPickerSettings)
- (NSString *)settingsImageName;
{
    if (self.isTrash)
        return @"OUIDocumentStoreScope-Trash.png";
    else
        return @"OUIDocumentStoreScope-Local.png";
}
@end

@implementation OFXDocumentStoreScope (OUIDocumentPickerSettings)
- (NSString *)settingsImageName;
{
    if (self.account.lastError != nil)
        return @"OUIPresenceDocuments-Error.png";

    return @"OUIDocumentStoreScope-Presence.png";
}
@end
