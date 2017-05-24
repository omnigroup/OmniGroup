// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAConfigurableColumnTableView.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/NSWindow-OAExtensions.h>

RCS_ID("$Id$")

@interface NSTableView (PrivateParts)
- (void)_writePersistentTableColumns;
@end

/*"
Note that this class cannot have a 'deactivateTableColumns' ivar to store the inactive columns.  The problem with that is that if NSTableView's column position/size saving code is turned on, it will blow away table columns that aren't listed in the default.  This can lead to out-of-sync problems.

Also note that this class doesn't subclass -addTableColumn: and -removeTableColumn to update the popup.
"*/

@implementation OAConfigurableColumnTableView
{
    BOOL _disableAutosaveOnResize;
}

//
// NSObject subclass
//

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;

    _disableAutosaveOnResize = YES;
    [self _commonInit];

    return self;
}

//
// NSView subclass
//

- initWithFrame:(NSRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    [self _commonInit];
    
    return self;
}

//
// NSTableView subclass
//

// We want this method to search both active and inactive columns (OOM depends upon this).  Neither the configuration menu nor the tableColumns array is guaranteed to have all the items (the configuration menu will have all but those that cannot be configured and the tableColumns will have only the active columns).  This is on place where our strategy of not adding an ivar for 'all table columsn' is wearing thin.
- (NSTableColumn *)tableColumnWithIdentifier:(id)identifier;
{
    // First check the configuration menu
    for (NSMenuItem *item in [configurationMenu itemArray]) {
        NSTableColumn  *column = [item representedObject];
        if ([[column identifier] isEqual: identifier])
            return column;
    }

    // Then check the table view (since it might have unconfigurable columns)
    for (NSTableColumn *column in [self tableColumns]) {
        if ([[column identifier] isEqual: identifier])
            return column;
    }
    
    return nil;
}

- (void)setDataSource:(id <NSTableViewDataSource>)dataSource;
{
    [super setDataSource: dataSource];
    
    confDataSourceFlags.menuString     = [dataSource respondsToSelector: @selector(configurableColumnTableView:menuStringForColumn:)];
    confDataSourceFlags.addSeparator   = [dataSource respondsToSelector: @selector(configurableColumnTableView:shouldAddSeparatorAfterColumn:)];
    confDataSourceFlags.allowToggle    = [dataSource respondsToSelector: @selector(configurableColumnTableView:shouldAllowTogglingColumn:)];
    confDataSourceFlags.willActivate   = [dataSource respondsToSelector: @selector(configurableColumnTableView:willActivateColumn:)];
    confDataSourceFlags.didActivate    = [dataSource respondsToSelector: @selector(configurableColumnTableView:didActivateColumn:)];
    confDataSourceFlags.willDeactivate = [dataSource respondsToSelector: @selector(configurableColumnTableView:willDeactivateColumn:)];
    confDataSourceFlags.didDeactivate  = [dataSource respondsToSelector: @selector(configurableColumnTableView:didDeactivateColumn:)];

    // The new delegate may want to return different string
    [self _buildConfigurationMenu];
}

//
// New API
//

- (NSMenu *)configurationMenu;
{
    return configurationMenu;
}

- (void)activateTableColumn:(NSTableColumn *)column;
{
    if (!column.hidden)
        return; // Already active

    if (confDataSourceFlags.willActivate)
        [(id)[self dataSource] configurableColumnTableView: self willActivateColumn: column];
        
    NSMenuItem *item = [self _itemForTableColumn: column];
    item.state = YES;
    column.hidden = NO;

    [self _OA_saveTableColumns];

    if (confDataSourceFlags.didActivate)
        [(id)[self dataSource] configurableColumnTableView: self didActivateColumn: column];
}

- (void)deactivateTableColumn:(NSTableColumn *)column;
{
    if (column.hidden)
        return; // Already inactive

    if (confDataSourceFlags.willDeactivate)
        [(id)[self dataSource] configurableColumnTableView: self willDeactivateColumn: column];
        
    NSMenuItem *item = [self _itemForTableColumn: column];
    item.state = NO;
    column.hidden = YES;
    
    [self _OA_saveTableColumns];

    if (confDataSourceFlags.didDeactivate)
        [(id)[self dataSource] configurableColumnTableView: self didDeactivateColumn: column];
}

- (void)toggleTableColumn:(NSTableColumn *)column;
{
    OBPRECONDITION(column);
    OBPRECONDITION([self _itemForTableColumn: column]);
    
    if ([self isTableColumnActive:column])
        [self deactivateTableColumn:column];
    else
        [self activateTableColumn:column];
    
    [self tile];
    [self sizeToFit]; // We don't need to check the -columnAutoresizingStyle, because -sizeToFit honors it
}

- (BOOL)isTableColumnActive:(NSTableColumn *)column;
{
    return !column.hidden;
}

- (void)reloadData;
{
    [super reloadData];
    
    for (NSMenuItem *item in [configurationMenu itemArray]) {
        NSTableColumn *column = [item representedObject];
        [[self _itemForTableColumn:column] setState:[self isTableColumnActive:column]];
    }
}

#pragma mark - OAConfigurableColumnTableView (PrivateAPI)

- (void)_commonInit;
{
    [self _buildConfigurationMenu];
}

- (BOOL)_removeDuplicateColumns;
{
    NSMutableSet *existingIdentifiers = [NSMutableSet set];
    NSMutableArray *duplicateColumns = [NSMutableArray array];
    for (NSTableColumn *tableColumn in self.tableColumns) {
        NSString *identifier = tableColumn.identifier;
        if ([existingIdentifiers containsObject:identifier]) {
            [duplicateColumns addObject:tableColumn];
            continue;
        }
        [existingIdentifiers addObject:identifier];
    }

    for (NSTableColumn *duplicateColumn in duplicateColumns) {
        [self removeTableColumn:duplicateColumn];
    }

    return duplicateColumns.count != 0;
}

- (void)_buildConfigurationMenu;
{
    configurationMenu = nil;
    
    id dataSource = [self dataSource];
    if (dataSource == nil)
        return;

    if (self.autosaveTableColumns) {
        [NSWindow beforeAnyDisplayIfNeededPerformBlock:^{
            if (self.dataSource == nil)
                return;

            self.autosaveTableColumns = NO; self.autosaveTableColumns = YES; // Load our saved column configuration
            if ([self _removeDuplicateColumns]) {
                [self _OA_saveTableColumns];
                [self _buildConfigurationMenu];
            }
        }];
    }

    configurationMenu = [[NSMenu alloc] initWithTitle: @""];
        
    // Add items for all the columns.  For columsn that aren't currently displayed, this will be where we store the pointer to the column.
    for (NSTableColumn *column in [self tableColumns])
        [self _addItemWithTableColumn:column dataSource:dataSource];
}

- (void)_addItemWithTableColumn:(NSTableColumn *)column dataSource: (id) dataSource;
{
    // If we don't allow configuration, don't add the item to the menu
    if (confDataSourceFlags.allowToggle && ![dataSource configurableColumnTableView:self shouldAllowTogglingColumn:column])
        return;
    
    NSString *title = nil;
    if (confDataSourceFlags.menuString)
        title = [dataSource configurableColumnTableView:self menuStringForColumn:column];
    if (!title)
        title = [[column headerCell] stringValue];
        
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(_toggleColumn:) keyEquivalent: @""];
    item.target = self;
    item.state = [self isTableColumnActive:column];
    item.representedObject = column;
    [configurationMenu addItem:item];
    
    if (confDataSourceFlags.addSeparator && [dataSource configurableColumnTableView:self shouldAddSeparatorAfterColumn:column])
        [configurationMenu addItem: [NSMenuItem separatorItem]];
}

- (NSMenuItem *)_itemForTableColumn:(NSTableColumn *)column;
{
    for (NSMenuItem *item in [configurationMenu itemArray])
        if (column == [item representedObject])
            return item;
    return nil;
}

- (void)_toggleColumn:(id)sender;
{
    NSMenuItem *item = OB_CHECKED_CAST(NSMenuItem, sender);
    [self toggleTableColumn:item.representedObject];
}

- (void)_OA_saveTableColumns;
{
    if (!self.autosaveTableColumns)
        return;

    NSString *autosaveName = self.autosaveName;
    if (autosaveName != nil) {
#if 1
        // workaround for rdar://4508650. [NSTableView {add,remove}TableColumn:] honor autosaveTableColumns.
        if ([self respondsToSelector:@selector(_writePersistentTableColumns)])
            [self _writePersistentTableColumns];
        else
            OBASSERT_NOT_REACHED("no _writePersistentTableColumns on NSTableView");
#else
        // Update our saved column configuration to trigger a save udpate
        self.autosaveName = nil;
        self.autosaveName = autosaveName;
        [[NSUserDefaults standardUserDefaults] synchronize];
#endif
    }
}

- (void)awakeFromNib;
{
    [super awakeFromNib];

    _disableAutosaveOnResize = NO;
}

- (void)sizeToFit;
{
    if (_disableAutosaveOnResize) {
        BOOL wasAutosaveEnabled = self.autosaveTableColumns;
        self.autosaveTableColumns = NO;
        [super sizeToFit];
        self.autosaveTableColumns = wasAutosaveEnabled;
    } else {
        [super sizeToFit];
    }
}

@end

@implementation OAConfigurableColumnTableHeaderView

- (NSMenu *)menuForEvent:(NSEvent *)event;
{
    OAConfigurableColumnTableView *tableView = OB_CHECKED_CAST(OAConfigurableColumnTableView, self.tableView);
    return [tableView configurationMenu];
}

@end
