// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUIDocument/OUIDocumentPickerHomeScreenViewController.h>

#import <OmniDocumentStore/ODSStore.h>
#import <OmniDocumentStore/ODSScope.h>
#import <OmniDocumentStore/ODSFilter.h>
#import <OmniFoundation/OFBinding.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniUI/OUIActivityIndicator.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniUIDocument/OUIDocumentPicker.h>
#import <OmniUIDocument/OUIDocumentPickerViewController.h>
#import <OmniUIDocument/OUIDocumentAppController.h>
#import <OmniFileExchange/OFXAgent.h>
#import <OmniFileExchange/OFXDocumentStoreScope.h>
#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>

#import "OUIDocumentParameters.h"
#import "OUIAddCloudAccountViewController.h"
#import "OUIServerAccountSetupViewController.h"
#import "OUIDocumentHomeScreenAnimator.h"
#import "OUIDocumentPickerAdaptableContainerViewController.h"
#import "OUIDocumentPicker-Internal.h"
#import <OmniUIDocument/OmniUIDocumentAppearance.h>
#import <OmniUIDocument/OUIDocumentPickerFilter.h>

RCS_ID("$Id$")

#pragma mark - Table view sections

typedef NS_ENUM(NSInteger, HomeScreenSections) {
    AccountsListSection,
    EditModeSection,
    SectionCount,
};

typedef NS_ENUM(NSInteger, EditModeSectionRows) {
    AddCloudAccountRow,
    ToggleBackgroundCellularSyncRow,
    EditModeSectionRowCount,
};

#pragma mark - Cells

NSString *const HomeScreenCellReuseIdentifier = @"documentPickerHomeScreenCell";
NSString *const AddCloudAccountReuseIdentifier = @"addCloudAccount";
NSString *const ToggleBackgroundCellarSyncReuseIdentifier = @"toggleBackgroundCellularSync";

#pragma mark - KVO Contexts

static void *ScopeCellLabelObservationContext = &ScopeCellLabelObservationContext; // Keys that don't affect ordering; just need to be pushed to cells
static void *ScopeOrderingObservationContext = &ScopeOrderingObservationContext; // Keys that can affect ordering or number of items in locations list

#pragma mark - Helper data types

@interface _OUIDocumentPickerObservedFilterRecord : NSObject
@property (copy, nonatomic) NSString *localizedMatchingObjectsDescription;
@property (retain, nonatomic) ODSFilter *filter;
@end

@implementation _OUIDocumentPickerObservedFilterRecord
@end

#pragma mark - View Controller

@implementation OUIDocumentPickerHomeScreenViewController
{
    BOOL _finishedLoading;
    NSMutableArray *_orderedScopes;
    NSMapTable *_observedFilterRecordsByScope;
}

- (instancetype)initWithDocumentPicker:(OUIDocumentPicker *)documentPicker;
{
    if (!(self = [super initWithStyle:UITableViewStyleGrouped]))
        return nil;
    
    if (!documentPicker)
        OBRejectInvalidCall(self, _cmd, @"documentPicker must not be nil");
    
    _observedFilterRecordsByScope = [NSMapTable strongToStrongObjectsMapTable];
    
    _documentPicker = documentPicker;
    [_documentPicker.documentStore addObserver:self forKeyPath:OFValidateKeyPath(_documentPicker.documentStore, scopes) options:0 context:ScopeOrderingObservationContext];
    [self _startObservingScope:_documentPicker.documentStore.trashScope];
    
    self.navigationItem.title = NSLocalizedStringFromTableInBundle(@"Locations", @"OmniUIDocument", OMNI_BUNDLE, @"top level doc picker title");
    
    self.navigationItem.rightBarButtonItems = @[self.editButtonItem, [[OUIAppController controller] newAppMenuBarButtonItem]];
    
    UITableView *tableView = self.tableView;
    tableView.separatorInset = UIEdgeInsetsZero;
    tableView.allowsSelectionDuringEditing = YES;
    
    return self;
}

- (void)dealloc;
{
    [OFPreference removeObserver:self forPreference:[OFXAgent cellularSyncEnabledPreference]];
    
    [self _stopObservingScope:_documentPicker.documentStore.trashScope];
    
    for (OFXDocumentStoreScope *scope in _orderedScopes)
        if (!scope.isTrash)
            [self _stopObservingScope:scope];
    
    [_documentPicker.documentStore removeObserver:self forKeyPath:OFValidateKeyPath(_documentPicker.documentStore, scopes) context:ScopeOrderingObservationContext];
    
    OBPOSTCONDITION(_observedFilterRecordsByScope.count == 0, "Failed to unregister for some scope filters!");
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
{
    if (context == ScopeOrderingObservationContext) {
        [self _updateOrderedScopes];
    } else if (context == ScopeCellLabelObservationContext) {
        ODSScope *scope;
        if ([object isKindOfClass:[ODSFilter class]])
            scope = ((ODSFilter *)object).scope;
        else
            scope = OB_CHECKED_CAST(ODSScope, object);
        
        // The scope might have been removed because it hit 0 items; if so, we can't update its cell anymore
        NSUInteger scopeIndex = [_orderedScopes indexOfObject:scope];
        if (scopeIndex != NSNotFound) {
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:[_orderedScopes indexOfObject:scope] inSection:AccountsListSection]];
        
            if (cell)
                [self _updateCell:cell forScope:scope];
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
    
    [OFPreference addObserver:self selector:@selector(_cellularSyncPreferenceChanged:) forPreference:[OFXAgent cellularSyncEnabledPreference]];
    
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated;
{
    [super viewDidAppear:animated];
    [[OUIDocumentPickerViewController scopePreference] setStringValue:@""];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:NO];
}

- (void)setEditing:(BOOL)editing;
{
    if ([[OUIAppController controller] showFeatureDisabledForRetailDemoAlert])
        return;
    
    [super setEditing:editing];
    if (self.isViewLoaded)
        [self.tableView reloadData];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
{
    if ([[OUIAppController controller] showFeatureDisabledForRetailDemoAlert])
        return;
    
    BOOL wasEditing = self.editing;
    
    [super setEditing:editing animated:animated];
    
    if (wasEditing == editing || !self.isViewLoaded)
        return;
    
    UITableView *tableView = self.tableView;
    if (editing)
        [tableView insertSections:[NSIndexSet indexSetWithIndex:EditModeSection] withRowAnimation:UITableViewRowAnimationFade];
    else
        [tableView deleteSections:[NSIndexSet indexSetWithIndex:EditModeSection] withRowAnimation:UITableViewRowAnimationFade];
    
    // We need to reload the rows that can't be edited, rather than just call -_updateCell:forScope:, because changing the tintAdjustmentMode is not animatable.
    NSMutableArray *indexPaths = [NSMutableArray new];
    for (NSUInteger i = 0; i < _orderedScopes.count; i++) {
        if (!_canEditScope([self _scopeAtIndex:i]))
            [indexPaths addObject:[NSIndexPath indexPathForRow:i inSection:AccountsListSection]];
    }
    
    [tableView reloadRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
    
    [self.documentPicker enableAppMenuBarButtonItem:!editing];
}

#pragma mark - API

- (NSArray *)additionalScopeItems;
{
    return [NSArray array];
}

- (void)additionalScopeItemsDidChange;
{
    [self _updateOrderedScopes];
}

- (NSArray *)orderedScopeItems;
{
    return _orderedScopes;
}

- (void)_startObservingScope:(ODSScope *)scope;
{
    OBASSERT([_observedFilterRecordsByScope objectForKey:scope] == nil, "Forgot to unregister observers for filters of scope %@", scope);
    
    NSArray *docPickerFilters = [_documentPicker availableFiltersForScope:scope];
    if (docPickerFilters.count == 0) {
        [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) options:0 context:ScopeCellLabelObservationContext];
    } else {
        NSMutableArray *observedFilters = [NSMutableArray new];
        for (OUIDocumentPickerFilter *docPickerFilter in docPickerFilters) {
            ODSFilter *filter = [[ODSFilter alloc] initWithFileItemsInScope:scope];
            filter.filterPredicate = docPickerFilter.predicate;
            [filter addObserver:self forKeyPath:OFValidateKeyPath(filter, filteredItems) options:0 context:ScopeCellLabelObservationContext];
            
            _OUIDocumentPickerObservedFilterRecord *record = [_OUIDocumentPickerObservedFilterRecord new];
            record.localizedMatchingObjectsDescription = docPickerFilter.localizedMatchingObjectsDescription;
            record.filter = filter;
            [observedFilters addObject:record];
        }
        
        [_observedFilterRecordsByScope setObject:observedFilters forKey:scope];
    }
    
    if ([scope isKindOfClass:[OFXDocumentStoreScope class]])
        [scope addObserver:self forKeyPath:OFValidateKeyPath((OFXDocumentStoreScope *)scope, account.nickname) options:0 context:ScopeCellLabelObservationContext];
    
    if (scope.isTrash)
        [scope addObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) options:0 context:ScopeOrderingObservationContext];
}

- (void)_stopObservingScope:(ODSScope *)scope;
{
    NSArray *observedFilters = [_observedFilterRecordsByScope objectForKey:scope];
    if (!observedFilters) {
        [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) context:ScopeCellLabelObservationContext];
    } else {
        OBASSERT(observedFilters.count > 0);
        for (_OUIDocumentPickerObservedFilterRecord *record in observedFilters)
            [record.filter removeObserver:self forKeyPath:OFValidateKeyPath(record.filter, filteredItems) context:ScopeCellLabelObservationContext];
        
        [_observedFilterRecordsByScope removeObjectForKey:scope];
    }
    
    if ([scope isKindOfClass:[OFXDocumentStoreScope class]])
        [scope removeObserver:self forKeyPath:OFValidateKeyPath((OFXDocumentStoreScope *)scope, account.nickname) context:ScopeCellLabelObservationContext];
    
    if (scope.isTrash)
        [scope removeObserver:self forKeyPath:OFValidateKeyPath(scope, fileItems) context:ScopeOrderingObservationContext];
}

- (void)_updateOrderedScopes;
{
    ODSStore *documentStore = _documentPicker.documentStore;
    NSMutableArray *scopesToRemove = [_orderedScopes mutableCopy];
    NSMutableArray *scopesToAdd = [documentStore.scopes mutableCopy];
    NSMutableArray *newOrderedScopes = [scopesToAdd mutableCopy];
    [newOrderedScopes sortUsingSelector:@selector(compareDocumentScope:)];

    [scopesToAdd addObjectsFromArray:[self additionalScopeItems]];

    ODSScope *trashScope = documentStore.trashScope;
    BOOL includeTrash = trashScope.fileItems.count > 0;
    
    OBASSERT([scopesToAdd containsObject:trashScope], "If we don't start out assuming we should add the trash scope, it won't get added!");
    if (!includeTrash) {
        // Since scopesToRemove is created by copying our _orderedScopes, it may already have the trash scope in it.
        if (!([scopesToRemove containsObject:trashScope]) && [_orderedScopes containsObject:trashScope])
            [scopesToRemove addObject:trashScope];
        
        [newOrderedScopes removeObject:trashScope];
        [scopesToAdd removeObject:trashScope];
    }
    
    [newOrderedScopes removeObject:_documentPicker.documentStore.templateScope];
    [scopesToAdd removeObject:_documentPicker.documentStore.templateScope];

    for (ODSScope *scope in scopesToAdd)
        [scopesToRemove removeObject:scope];

    for (ODSScope *scope in _orderedScopes)
        [scopesToAdd removeObject:scope];

    UITableView *tableView = self.tableView;
    [tableView beginUpdates];

    for (OFXDocumentStoreScope *scope in scopesToRemove) {
        if (scope != trashScope)
            [self _stopObservingScope:scope]; // -initWithDocumentStore: already observes the trash scope (so it can remove its row from the table when it's empty)
        
        NSUInteger indexToDelete = [_orderedScopes indexOfObject:scope];
        if (indexToDelete == NSNotFound)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to delete a scope that isn't in our table view data source!" userInfo:@{@"scope" : scope}];
        
        [tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:indexToDelete inSection:AccountsListSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    }

    _orderedScopes = newOrderedScopes;

    NSUInteger additionalInsertionIndex = _orderedScopes.count;
    if (includeTrash)
        additionalInsertionIndex--;
    [_orderedScopes replaceObjectsInRange:NSMakeRange(additionalInsertionIndex, 0) withObjectsFromArray:[self additionalScopeItems]];
    
    for (OFXDocumentStoreScope *scope in scopesToAdd) {
        if (scope != trashScope)
            [self _startObservingScope:scope]; // we need to keep observing the trash scope so we can add it back to the table if something gets deleted
        
        NSUInteger indexToAdd = [_orderedScopes indexOfObject:scope];
        if (indexToAdd == NSNotFound)
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Trying to add a scope that isn't in our table view data source!" userInfo:@{@"scope" : scope}];
        
        [tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:indexToAdd inSection:AccountsListSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
    }

    [tableView endUpdates];
}

- (void)finishedLoading;
{
    if (!_finishedLoading) {
        _finishedLoading = YES;
        [self _updateOrderedScopes];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
    if (!_finishedLoading)
        return 0;
    else if (self.editing)
        return SectionCount;
    else
        return SectionCount - 1;
}

static BOOL _scanForCellularInterface(void);

static BOOL _autoHasCellularInterface(void)
{
    static BOOL foundCellularInterface = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        foundCellularInterface = _scanForCellularInterface();
    });
    return foundCellularInterface;
}

static BOOL _hasCellularInterface(void)
{
    typedef NS_ENUM(NSUInteger, OUIDocumentPickerCellularInterfaceType) {
        OUIDocumentPickerHasCellularInterfaceAuto,
        OUIDocumentPickerHasCellularInterfaceAlways,
        OUIDocumentPickerHasCellularInterfaceNever,
    };
    static OFPreference *hasCellularInterfacePreference;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        OFEnumNameTable *enumeration = [[OFEnumNameTable alloc] initWithDefaultEnumValue:OUIDocumentPickerItemSortByDate];
        [enumeration setName:@"auto" forEnumValue:OUIDocumentPickerHasCellularInterfaceAuto];
        [enumeration setName:@"always" forEnumValue:OUIDocumentPickerHasCellularInterfaceAlways];
        [enumeration setName:@"never" forEnumValue:OUIDocumentPickerHasCellularInterfaceNever];
        hasCellularInterfacePreference = [OFPreference preferenceForKey:@"OUIDocumentPickerHasCellularInterface" enumeration:enumeration];
    });

    OUIDocumentPickerCellularInterfaceType cellType = [hasCellularInterfacePreference enumeratedValue];
    switch (cellType) {
        default:
        case OUIDocumentPickerHasCellularInterfaceAuto:
            return _autoHasCellularInterface();
        case OUIDocumentPickerHasCellularInterfaceAlways:
            return YES;
        case OUIDocumentPickerHasCellularInterfaceNever:
            return NO;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
    OBPRECONDITION(_finishedLoading, "Asked for the number of rows when we haven't loaded yet!");
    OBPRECONDITION(section == AccountsListSection || section == EditModeSection);
    OBASSERT_IF(!self.editing, section == AccountsListSection, "Asked for rows in the Add Account section when no such section should exist");
    
    if (section == AccountsListSection)
        return _orderedScopes.count;

    if (_hasCellularInterface())
        return EditModeSectionRowCount;
    else
        return EditModeSectionRowCount - 1;
}

- (ODSScope <ODSConcreteScope> *)_scopeAtIndex:(NSUInteger)index;
{
    return _orderedScopes[index];
}

static BOOL _canEditScope(ODSScope <ODSConcreteScope> *scope)
{
    return [scope isKindOfClass:[OFXDocumentStoreScope class]];
}

- (UITableViewCell *)selectedCell;
{
    [self.tableView layoutIfNeeded];
    return [self.tableView cellForRowAtIndexPath:self.tableView.indexPathForSelectedRow];
}

- (void)selectCellForScope:(ODSScope *)scope;
{
    [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:[_orderedScopes indexOfObjectIdenticalTo:scope] inSection:0] animated:YES scrollPosition:UITableViewScrollPositionMiddle];
}

- (void)_updateCell:(UITableViewCell *)cell forScope:(ODSScope *)scope;
{
    OBASSERT_NOTNULL(cell);
    
    static UIImage *localImage, *cloudImage, *trashImage;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cloudImage = [[UIImage imageNamed:@"OUIDocumentPickerCloudLocationIcon.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        localImage = [[UIImage imageNamed:@"OUIDocumentPickerLocalDocumentsLocationIcon.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        trashImage = [[UIImage imageNamed:@"OUIDocumentPickerTrashLocationIcon.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    });
    
    cell.textLabel.text = scope.displayName;
    
    NSArray *filterRecords = [_observedFilterRecordsByScope objectForKey:scope];
    if (filterRecords.count == 0) {
        cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%d items", @"OmniUIDocument", OMNI_BUNDLE, @"home screen detail label"), scope.fileItems.count];
    } else {
        NSMutableArray *counts = [NSMutableArray new];
        for (_OUIDocumentPickerObservedFilterRecord *record in filterRecords) {
            NSUInteger matchingCount = record.filter.filteredItems.count;
            if (matchingCount > 0)
                [counts addObject:[NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"%lu %@", @"OmniUIDocument", OMNI_BUNDLE, @"home screen detail format -- count and item description"), matchingCount, record.localizedMatchingObjectsDescription]];
        }
        
        static NSString *joiner;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            joiner = [NSString stringWithFormat:@" %@ ", [[OmniUIDocumentAppearance appearance] documentPickerHomeScreenItemCountSeparator]];
        });
        cell.detailTextLabel.text = [counts componentsJoinedByString:joiner];
    }
    
    if ([scope isKindOfClass:[OFXDocumentStoreScope class]]) {
        cell.imageView.image = cloudImage;
        cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.imageView.image = scope.isTrash ? trashImage : localImage;
        cell.editingAccessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = self.isEditing ? [UIColor lightGrayColor] : nil;
        cell.detailTextLabel.textColor = self.isEditing ? [UIColor lightGrayColor] : nil;
    }
    
    if (self.isEditing)
        cell.tintAdjustmentMode = _canEditScope(scope) ? UIViewTintAdjustmentModeAutomatic : UIViewTintAdjustmentModeDimmed;
    else
        cell.tintAdjustmentMode = UIViewTintAdjustmentModeAutomatic;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    OBPRECONDITION(indexPath.section == AccountsListSection || indexPath.section == EditModeSection);
    
    if (indexPath.section == AccountsListSection) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:HomeScreenCellReuseIdentifier];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:HomeScreenCellReuseIdentifier];

        [self _updateCell:cell forScope:[self _scopeAtIndex:indexPath.row]];
        
        return cell;
    } else if (indexPath.row == AddCloudAccountRow) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AddCloudAccountReuseIdentifier];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:AddCloudAccountReuseIdentifier];
        cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Add Cloud Account", @"OmniUIDocument", OMNI_BUNDLE, @"home screen button label");
        cell.textLabel.textColor = [tableView tintColor];
        return cell;
    } else if (indexPath.row == ToggleBackgroundCellularSyncRow) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ToggleBackgroundCellarSyncReuseIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ToggleBackgroundCellarSyncReuseIdentifier];
            UISwitch *cellularDataSwitch = [[UISwitch alloc] init];
            [cellularDataSwitch addTarget:self action:@selector(_takeUseCellularDataForBackgroundSyncFrom:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = cellularDataSwitch;
        }
        
        ((UISwitch *)cell.accessoryView).on = [OFXAgent isCellularSyncEnabled];
        cell.textLabel.text = NSLocalizedStringFromTableInBundle(@"Use Cellular Data", @"OmniUIDocument", OMNI_BUNDLE, @"Label for switch which controls whether cloud sync is allowed to use cellular data");
        
        return cell;
    }
    
    OBASSERT_NOT_REACHED("Unknown row!");
    return nil;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        ODSScope<ODSConcreteScope> *scope = [self _scopeAtIndex:indexPath.item];
        OBASSERT([scope respondsToSelector:@selector(account)]);

        OFXServerAccount *account = [(OFXDocumentStoreScope *)scope account];
        [[OUIDocumentAppController controller] warnAboutDiscardingUnsyncedEditsInAccount:account withCancelAction:NULL discardAction:^{
            // This marks the account for removal and starts the process of stopping syncing on it. Once that happens, it will automatically be removed from the filesystem.
            [account prepareForRemoval];
            OBASSERT(![_orderedScopes containsObject:scope]);
        }];
    }
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (indexPath.section == AccountsListSection)
        return [[OmniUIDocumentAppearance appearance] documentPickerLocationRowHeight];
    else
        return [[OmniUIDocumentAppearance appearance] documentPickerAddAccountRowHeight];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OBPRECONDITION(_finishedLoading);
    
    if (self.isEditing) {
        if (indexPath.section == AccountsListSection) {
            OFXDocumentStoreScope *scope = OB_CHECKED_CAST(OFXDocumentStoreScope, [self _scopeAtIndex:indexPath.row]);
            OFXServerAccount *account = scope.account;
            OUIServerAccountSetupViewController *setupController = [[OUIServerAccountSetupViewController alloc] initWithAccount:account];
            setupController.finished = ^(id account, NSError *error) { };
            [self showViewController:setupController sender:tableView];
        } else {
            OBPRECONDITION(indexPath.section == EditModeSection);
            OBPRECONDITION(indexPath.row == AddCloudAccountRow);
            
            OUIAddCloudAccountViewController *addController = [[OUIAddCloudAccountViewController alloc] initWithUsageMode:OFXServerAccountUsageModeCloudSync];
            addController.finished = ^(OFXServerAccount *newAccountOrNil) {
                [self.navigationController popToViewController:self animated:YES];
                
                if (newAccountOrNil) {
                    for (ODSScope *scope in _documentPicker.documentStore.scopes) {
                        if ([scope isKindOfClass:[OFXDocumentStoreScope class]] && ((OFXDocumentStoreScope*)scope).account == newAccountOrNil) {
                            [_documentPicker navigateToScope:scope animated:YES];
                            break;
                        }
                    }
                }
            };
            
            [self.navigationController pushViewController:addController animated:YES];
        }
    } else {
        ODSScope *scope = [self _scopeAtIndex:indexPath.item];

        OUIDocumentPickerFilter *filter ;
        OFPreference *filterPreference = [OUIDocumentPickerViewController filterPreference];
        [filterPreference setStringValue:filter.identifier];

        OUIDocumentPickerViewController *picker = [[OUIDocumentPickerViewController alloc] initWithDocumentPicker:_documentPicker scope:scope];
        [self showUnembeddedViewController:picker sender:self];
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return indexPath.section != EditModeSection;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath;
{
    return indexPath.section != EditModeSection && _canEditScope([self _scopeAtIndex:indexPath.row]);
}

- (void)tableView:(UITableView*)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // This method is a no-op because implementing it prevents UITableView from sending -setEditing:animated when the users swipes-to-delete.
}

- (void)tableView:(UITableView *)tableView didEndEditingRowAtIndexPath:(NSIndexPath *)indexPath;
{
    // This method is a no-op, but it's necessary because UITableView will send -setEditing:NO without it (even though it never sent the corresponding -setEditing:YES due to the above implementation of -tableView:willBeginEditingRowAtIndexPath:)
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath;
{
    if (!self.isEditing)
        return YES;
    
    if (indexPath.section == AccountsListSection && !_canEditScope([self _scopeAtIndex:indexPath.row]))
        return NO;
    
    if (indexPath.section == EditModeSection && indexPath.row != AddCloudAccountRow)
        return NO;
    
    return YES;
}

#pragma mark - Actions from table view cells

- (void)_takeUseCellularDataForBackgroundSyncFrom:(id)sender;
{
    UISwitch *cellularDataSwitch = OB_CHECKED_CAST(UISwitch, sender);
    [OFXAgent setCellularSyncEnabled:cellularDataSwitch.on];
}

- (void)_cellularSyncPreferenceChanged:(NSNotification *)note;
{
    UITableViewCell *toggleCell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForItem:ToggleBackgroundCellularSyncRow inSection:EditModeSection]];
    
    if (toggleCell)
        ((UISwitch *)toggleCell.accessoryView).on = [OFXAgent isCellularSyncEnabled];
}

@end

#pragma mark - Animation Support

@implementation OUIDocumentPickerHomeScreenViewController (HomeScreenAnimatorSupport)

- (CGRect)frameOfCellForScope:(ODSScope *)scope inView:(UIView *)transitionContainerView;
{
    NSUInteger scopeIndex = [_orderedScopes indexOfObject:scope];
    OBASSERT(scopeIndex != NSNotFound);
    
    UITableView *tableView = self.tableView;
    CGRect cellFrame = [tableView rectForRowAtIndexPath:[NSIndexPath indexPathForRow:scopeIndex inSection:AccountsListSection]];
    return [transitionContainerView convertRect:cellFrame fromView:tableView];
}

@end

#import <sys/types.h>
#import <sys/socket.h>
#import <ifaddrs.h>
#import <net/if_dl.h>

// #import <net/if_types.h> // Not available in the iOS SDK, so we define IFT_CELLULAR by hand.  Fortunately, it's well-defined across systems: see RFC1573 and <http://www.iana.org/assignments/smi-numbers>.

#ifndef IFT_CELLULAR
#define	IFT_CELLULAR	0xff	/* Packet Data over Cellular */
#endif

static BOOL _scanForCellularInterface(void)
{
    struct ifaddrs *interfaceAddresses = NULL;
    const struct ifaddrs *interfaceCursor;

    if (getifaddrs(&interfaceAddresses) != 0)
        return YES; // If we're not sure, err on the side of caution

    BOOL foundCellularInterface = NO;
    for (interfaceCursor = interfaceAddresses; interfaceCursor != NULL; interfaceCursor = interfaceCursor->ifa_next) {
        if (interfaceCursor->ifa_addr == NULL)
            continue;

        sa_family_t interfaceFamily = interfaceCursor->ifa_addr->sa_family;
        if (interfaceFamily == AF_LINK) {
            struct sockaddr_dl *linkLevelAddress = (struct sockaddr_dl *)(interfaceCursor->ifa_addr);
            u_char interfaceType = linkLevelAddress->sdl_type;
            if (interfaceType == IFT_CELLULAR)
                foundCellularInterface = YES;

#ifdef DEBUG_kc
            NSString *name = [NSString stringWithUTF8String:interfaceCursor->ifa_name];
            u_short interfaceIndex = linkLevelAddress->sdl_index;
            NSLog(@"_scanForCellularInterface(): scanning link [%@], index=%u, type=0x%x", name, interfaceIndex, interfaceType);
#endif
        }
    }
    freeifaddrs(interfaceAddresses);
    return foundCellularInterface;
}
