// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "NSTableView-OAColumnConfigurationExtensions.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "OAApplication.h"


RCS_ID("$Id$")

@interface NSTableView (OAColumnConfigurationPrivate)
- (void)_setupColumnsAndMenu;
- (void)_addItemWithTableColumn:(NSTableColumn *)column toMenu:(NSMenu *)menu;
- (NSMenuItem *)_menuItemForTableColumn:(NSTableColumn *)column;
- (void)_toggleColumn:(id)sender;
- (void)_updateMenuItemState;
- (void)_autosizeColumn:(NSTableColumn *)tableColumn;
@end

@interface NSTableView (OAColumnConfigurationDelegateDataSourceCoverMethods)
- (BOOL)_columnConfigurationEnabled;
- (NSArray *)_defaultColumnIdentifiers;
- (NSString *)_menuStringForColumn:(NSTableColumn *)column;
- (BOOL)_shouldAllowTogglingColumn:(NSTableColumn *)column;
- (BOOL)_allowsAutoresizing;
- (BOOL)_shouldAddMenuSeparatorAfterColumn:(NSTableColumn *)column;
- (void)_willActivateColumn:(NSTableColumn *)column;
- (void)_didActivateColumn:(NSTableColumn *)column;
- (void)_willDeactivateColumn:(NSTableColumn *)column;
- (void)_didDeactivateColumn:(NSTableColumn *)column;
@end

@implementation NSOutlineView (OAColumnConfigurationExtensions)

// timo - 9/15/2003 - OBReplaceMethodImplementationWithSelector() will only replace the method implementation on the class which was passed.  Subclasses of NSTableView, such as NSOutlineView, also need to have their -reloadData and -setDataSource: implementations replaced in order to get configurable table columns.

static IMP originalOutlineSetDataSource;
static IMP originalOutlineReloadData;

+ (void)didLoad;
{
    originalOutlineSetDataSource = OBReplaceMethodImplementationWithSelector(self, @selector(setDataSource:), @selector(_configurableColumnReplacementSetDataSource:));
    originalOutlineReloadData = OBReplaceMethodImplementationWithSelector(self, @selector(reloadData), @selector(_configurableColumnReplacementReloadData));
}

// NSOutlineView method replacements

- (void)_configurableColumnReplacementSetDataSource:(id)dataSource;
{
    originalOutlineSetDataSource(self, _cmd, dataSource);
    [self _setupColumnsAndMenu];
}

- (void)_configurableColumnReplacementReloadData;
{
    originalOutlineReloadData(self, _cmd);
    [self _updateMenuItemState];
}

@end


@implementation NSTableView (OAColumnConfigurationExtensions)

static IMP originalSetDataSource;
static IMP originalReloadData;
static IMP originalTableColumnWithIdentifier;

+ (void)didLoad;
{
    originalSetDataSource = OBReplaceMethodImplementationWithSelector(self, @selector(setDataSource:), @selector(_configurableColumnReplacementSetDataSource:));
    originalReloadData = OBReplaceMethodImplementationWithSelector(self, @selector(reloadData), @selector(_configurableColumnReplacementReloadData));
    originalTableColumnWithIdentifier = OBReplaceMethodImplementationWithSelector(self, @selector(tableColumnWithIdentifier:), @selector(_replacementTableColumnWithIdentifier:));
}


// NSTableView method replacements

- (void)_configurableColumnReplacementSetDataSource:(id)dataSource;
{
    originalSetDataSource(self, _cmd, dataSource);
    [self _setupColumnsAndMenu];
}

- (void)_configurableColumnReplacementReloadData;
{
    originalReloadData(self, _cmd);
    [self _updateMenuItemState];
}

- (NSTableColumn *)_replacementTableColumnWithIdentifier:(id)identifier;
{
    // We want this method to search both active and inactive columns (OOM depends upon this).  Neither the configuration menu nor the tableColumns array is guaranteed to have all the items (the configuration menu will have all but those that cannot be configured and the tableColumns will have only the active columns).  This is one place where our strategy of not adding an ivar for 'all table columns' is wearing thin.
    NSArray *items;
    unsigned int itemIndex;
    NSMenuItem *item;
    id column;

    if (![self _columnConfigurationEnabled])
        return originalTableColumnWithIdentifier(self, _cmd, identifier);
                
    // First check the configuration menu
    items = [[self columnsMenu] itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex:itemIndex];
        column = [item representedObject];
        if (![column isKindOfClass:[NSTableColumn class]])
            continue;
            
        if ([[column identifier] isEqual:identifier])
            return column;
    }

    // Then check the table view (since it might have unconfigurable columns)
    items = [self tableColumns];
    itemIndex = [items count];
    while (itemIndex--) {
        column = [items objectAtIndex:itemIndex];
        if ([[column identifier] isEqual:identifier])
            return column;
    }
    
    return nil;
}


// New API

- (NSMenu *) columnsMenu;
{
    OBPRECONDITION([self _columnConfigurationEnabled]);
    
    return [[self headerView] menu];
}

- (NSArray *)inactiveTableColumns;
{
    NSMutableArray *inactiveTableColumns;
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    NSTableColumn  *column;

    OBPRECONDITION([self _columnConfigurationEnabled]);
    
    inactiveTableColumns = [NSMutableArray array];
    items = [[self columnsMenu] itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex:itemIndex];
        column = [item representedObject];

        if (column == nil)
            continue;
            
        if (![self isTableColumnActive:column])
            [inactiveTableColumns addObject:column];
    }

    return inactiveTableColumns;
}

- (void)activateTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;

    OBPRECONDITION([self _columnConfigurationEnabled]);
    
    if ([[self tableColumns] containsObjectIdenticalTo:column])
        return; // Already active

    [self _willActivateColumn:column];
        
    item = [self _menuItemForTableColumn:column];
    [item setState:YES];
    
    [self addTableColumn:column];

    [self _didActivateColumn:column];
}

- (void)deactivateTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;

    OBPRECONDITION([self _columnConfigurationEnabled]);
    
    if (![[self tableColumns] containsObjectIdenticalTo:column])
        return; // Already inactive

    [self _willDeactivateColumn:column];
        
    item = [self _menuItemForTableColumn:column];
    [item setState:NO];
    
    [self removeTableColumn:column];

    [self _didDeactivateColumn:column];
}

- (void)toggleTableColumn:(NSTableColumn *)column;
{
    OBPRECONDITION([self _columnConfigurationEnabled]);
    OBPRECONDITION(column);
    OBPRECONDITION([self _menuItemForTableColumn:column]);
    
    if ([self isTableColumnActive:column])
        [self deactivateTableColumn:column];
    else
        [self activateTableColumn:column];
    
    [self tile];
    if ([self columnAutoresizingStyle] != NSTableViewNoColumnAutoresizing) {
        [self sizeToFit];
    }
}

- (BOOL)isTableColumnActive:(NSTableColumn *)column;
{
    OBPRECONDITION([self _columnConfigurationEnabled]);
    
    return [[self tableColumns] containsObject:column];
}

- (void)autosizeColumn:(id)sender;
{
    if (![self _allowsAutoresizing])
        return;
        
    NSTableHeaderView *headerView = [self headerView];
    NSPoint clickPoint = [headerView convertPoint:[[NSApp currentEvent] locationInWindow] fromView:nil];
    int clickedColumn = [headerView columnAtPoint:clickPoint];
    if (clickedColumn >= 0)
        [self _autosizeColumn:[[self tableColumns] objectAtIndex:clickedColumn]];
}

- (void)autosizeAllColumns:(id)sender;
{
    if (![self _allowsAutoresizing])
        return;

    NSArray *tableColumns = [self tableColumns];
    unsigned int columnCount = [tableColumns count], columnIndex;
    for (columnIndex = 0; columnIndex < columnCount; columnIndex++) {
        [self _autosizeColumn:[tableColumns objectAtIndex:columnIndex]];
    }
}

@end


@implementation NSTableView (OAColumnConfigurationPrivate)

- (void)_setupColumnsAndMenu;
{
    if (_dataSource == nil || ![self _columnConfigurationEnabled])
        return;
    
    BOOL loadingAutosavedColumns = NO;
    if ([self autosaveTableColumns]) {
        NSString *autosaveName;
        NSString *columnAutosaveName;
        
        autosaveName = [self autosaveName];
        columnAutosaveName = [NSString stringWithFormat:@"NSTableView Columns %@", autosaveName];
        loadingAutosavedColumns = ([[NSUserDefaults standardUserDefaults] objectForKey:columnAutosaveName] != nil);
    }
        
    NSMenu *columnsMenu = [[NSMenu alloc] initWithTitle:@"Configure Columns"];

    if ([self _allowsAutoresizing]) {
        NSBundle *bundle = [OAApplication bundle];
        NSMenuItem *menuItem;
        
        menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Auto Size Column", @"OmniAppKit", bundle, "autosize column contextual menu item") action:@selector(autosizeColumn:) keyEquivalent:@""];
        [menuItem setTarget:self];
        [columnsMenu addItem:menuItem];
        [menuItem release];
    
        menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Auto Size All Columns", @"OmniAppKit", bundle, "autosize all columns contextual menu item") action:@selector(autosizeAllColumns:) keyEquivalent:@""];
        [menuItem setTarget:self];
        [columnsMenu addItem:menuItem];
        [menuItem release];
        
        [columnsMenu addItem:[NSMenuItem separatorItem]];
    }
    
    // Add menu items for all the columns.  For columns that aren't currently displayed, this will be where we store the pointer to the column.
    // Also deactivate any columns that aren't supposed to show up in the default configuration.
    NSArray *defaultColumnIdentifiers = [self _defaultColumnIdentifiers];
    
    for (NSTableColumn *tableColumn in [NSArray arrayWithArray:self.tableColumns]) { // avoid mutation while enumeration exception
        [self _addItemWithTableColumn:tableColumn toMenu:columnsMenu];
        if (!loadingAutosavedColumns && ![defaultColumnIdentifiers containsObject:[tableColumn identifier]])
            [self deactivateTableColumn:tableColumn];
    }
    
    [self sizeToFit];
        
    [[self headerView] setMenu:columnsMenu];
    [columnsMenu release];
}

- (void)_addItemWithTableColumn:(NSTableColumn *)column toMenu:(NSMenu *)menu;
{
    NSMenuItem *item;
    NSString *title = nil;
    
    // If we don't allow configuration, don't add the item to the menu
    if (![self _shouldAllowTogglingColumn:column])
        return;
    
    title = [self _menuStringForColumn:column];
    item = [[NSMenuItem alloc] initWithTitle:title action:@selector(_toggleColumn:) keyEquivalent:@""];
    [item setTarget:self];
    [item setState:[self isTableColumnActive:column]];
    [item setRepresentedObject:column];
    [menu addItem:item];
    [item release];
    
    if ([self _shouldAddMenuSeparatorAfterColumn:column])
        [menu addItem:[NSMenuItem separatorItem]];
}

- (NSMenuItem *)_menuItemForTableColumn:(NSTableColumn *) column;
{
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    
    items = [[self columnsMenu] itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex:itemIndex];
        if (column == [item representedObject])
            return item;
    }

    return nil;
}

- (void)_toggleColumn:(id)sender;
{
    NSMenuItem *item;
    
    item = (NSMenuItem *)sender;
    OBASSERT([item isKindOfClass:[NSMenuItem class]]);

    [self toggleTableColumn:[item representedObject]];
}

- (void)_updateMenuItemState;
{
    NSArray *menuItems;
    unsigned int itemIndex;

    if (![self _columnConfigurationEnabled])
        return;
        
    menuItems = [[self columnsMenu] itemArray];
    for (itemIndex = 0; itemIndex < [menuItems count]; itemIndex++) {
        NSMenuItem *item;
        NSTableColumn *column;

        item = [menuItems objectAtIndex:itemIndex];
        column = [item representedObject];
        [[self _menuItemForTableColumn:column] setState:[self isTableColumnActive:column]];
    }
}

- (void)_autosizeColumn:(NSTableColumn *)tableColumn;
{
    BOOL isOutlineView = [self isKindOfClass:[NSOutlineView class]];
    NSCell *dataCell = [tableColumn dataCell];
    unsigned int numberOfRows = [self numberOfRows], rowIndex;
    float largestCellWidth = 0.0;
    
    if (![self _allowsAutoresizing])
        return;
        
    for (rowIndex = 0; rowIndex < numberOfRows; rowIndex++) {
        id objectValue;
        
        if (isOutlineView)
            objectValue = [_delegate outlineView:(NSOutlineView *)self objectValueForTableColumn:tableColumn byItem:[(NSOutlineView *)self itemAtRow:rowIndex]];
        else
            objectValue = [_delegate tableView:self objectValueForTableColumn:tableColumn row:rowIndex];
        
        [dataCell setObjectValue:objectValue];
        NSSize cellSize = [dataCell cellSize];
        if (cellSize.width > largestCellWidth)
            largestCellWidth = cellSize.width;
    }
    
    largestCellWidth = MIN([tableColumn maxWidth], MAX([tableColumn minWidth], largestCellWidth));
    [tableColumn setWidth:largestCellWidth];
}

@end

@implementation NSTableView (OAColumnConfigurationDelegateDataSourceCoverMethods)

- (BOOL)_columnConfigurationEnabled;
{
    return [_dataSource respondsToSelector:@selector(tableViewDefaultColumnIdentifiers:)];
}

- (NSArray *)_defaultColumnIdentifiers;
{
    if ([_dataSource respondsToSelector:@selector(tableViewDefaultColumnIdentifiers:)]) {
        NSArray *identifiers;

        identifiers = [_dataSource tableViewDefaultColumnIdentifiers:self];
        if ([identifiers count] < 1)
            [NSException raise:NSInvalidArgumentException format:@"-tableViewDefaultColumnIdentifiers: must return at least one valid column identifier"];
        else
            return identifiers;
    } else {
        return [[self tableColumns] arrayByPerformingSelector:@selector(identifier)];
    }

    return nil; // not reached but it makes the compiler happy
}

- (NSString *)_menuStringForColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:menuStringForColumn:)])
        return [_dataSource tableView:self menuStringForColumn:column];
    else
        return [[column headerCell] stringValue];
}

- (BOOL)_shouldAllowTogglingColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:shouldAllowTogglingColumn:)])
        return [_dataSource tableView:self shouldAllowTogglingColumn:column];
    else
        return YES;
}

- (BOOL)_allowsAutoresizing;
{
    if ([_dataSource respondsToSelector:@selector(tableViewAllowsColumnAutosizing:)])
        return [_dataSource tableViewAllowsColumnAutosizing:self];
    else
        return NO;
}

- (BOOL)_shouldAddMenuSeparatorAfterColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:shouldAddMenuSeparatorAfterColumn:)])
        return [_dataSource tableView:self shouldAddMenuSeparatorAfterColumn:column];
    else
        return NO;
}

- (void)_willActivateColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:willActivateColumn:)])
        [_dataSource tableView:self willActivateColumn:column];
}

- (void)_didActivateColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:didActivateColumn:)])
        [_dataSource tableView:self didActivateColumn:column];
}

- (void)_willDeactivateColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:willDeactivateColumn:)])
        [_dataSource tableView:self willDeactivateColumn:column];
}

- (void)_didDeactivateColumn:(NSTableColumn *)column;
{
    if ([_dataSource respondsToSelector:@selector(tableView:didDeactivateColumn:)])
        [_dataSource tableView:self didDeactivateColumn:column];
}

@end
