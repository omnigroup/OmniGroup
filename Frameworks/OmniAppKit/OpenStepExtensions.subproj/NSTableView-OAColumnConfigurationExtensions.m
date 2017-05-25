// Copyright 1997-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSTableView-OAColumnConfigurationExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniBase/macros.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/OAApplication.h>


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

static void (*originalOutlineSetDataSource)(NSOutlineView *self, SEL _cmd, id <NSOutlineViewDataSource> dataSource);
static void (*originalOutlineReloadData)(NSOutlineView *self, SEL _cmd);

OBDidLoad(^{
    Class self = [NSOutlineView class];
    originalOutlineSetDataSource = (typeof(originalOutlineSetDataSource))OBReplaceMethodImplementationWithSelector(self, @selector(setDataSource:), @selector(_configurableColumnReplacementSetDataSource:));
    originalOutlineReloadData = (typeof(originalOutlineReloadData))OBReplaceMethodImplementationWithSelector(self, @selector(reloadData), @selector(_configurableColumnReplacementReloadData));
});

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

static void (*originalSetDataSource)(NSTableView *self, SEL _cmd, id <NSTableViewDataSource> dataSource);
static void (*originalReloadData)(NSTableView *self, SEL _cmd);
static NSTableColumn *(*originalTableColumnWithIdentifier)(NSTableView *self, SEL _cmd, NSString *identifier);

OBDidLoad(^{
    Class self = [NSTableView class];
    originalSetDataSource = (typeof(originalSetDataSource))OBReplaceMethodImplementationWithSelector(self, @selector(setDataSource:), @selector(_configurableColumnReplacementSetDataSource:));
    originalReloadData = (typeof(originalReloadData))OBReplaceMethodImplementationWithSelector(self, @selector(reloadData), @selector(_configurableColumnReplacementReloadData));
    originalTableColumnWithIdentifier = (typeof(originalTableColumnWithIdentifier))OBReplaceMethodImplementationWithSelector(self, @selector(tableColumnWithIdentifier:), @selector(_replacementTableColumnWithIdentifier:));
});


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
    if (![self _columnConfigurationEnabled])
        return originalTableColumnWithIdentifier(self, _cmd, identifier);
                
    // First check the configuration menu    
    for (NSMenuItem *item in [[self columnsMenu] itemArray]) {
        id column = [item representedObject];
        if (![column isKindOfClass:[NSTableColumn class]])
            continue;
            
        if ([[column identifier] isEqual:identifier])
            return column;
    }

    // Then check the table view (since it might have unconfigurable columns)
    for (id column in [self tableColumns]) {
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
    OBPRECONDITION([self _columnConfigurationEnabled]);
    
    NSMutableArray *inactiveTableColumns = [NSMutableArray array];
    
    for (NSMenuItem *item in [[self columnsMenu] itemArray]) {
        NSTableColumn  *column = [item representedObject];

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
    NSPoint clickPoint = [headerView convertPoint:[[[NSApplication sharedApplication] currentEvent] locationInWindow] fromView:nil];
    NSInteger clickedColumn = [headerView columnAtPoint:clickPoint];
    if (clickedColumn >= 0)
        [self _autosizeColumn:[[self tableColumns] objectAtIndex:clickedColumn]];
}

- (void)autosizeAllColumns:(id)sender;
{
    if (![self _allowsAutoresizing])
        return;

    for (NSTableColumn *column in [self tableColumns])
        [self _autosizeColumn:column];
}

@end


@implementation NSTableView (OAColumnConfigurationPrivate)

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

- (void)_setupColumnsAndMenu;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if (dataSource == nil || ![self _columnConfigurationEnabled])
        return;
    
    BOOL loadingAutosavedColumns = NO;
    if (self.autosaveTableColumns) {
        NSString *autosaveName = self.autosaveName;
        NSString *columnAutosaveName = [NSString stringWithFormat:@"NSTableView Columns %@", autosaveName];
        loadingAutosavedColumns = ([[NSUserDefaults standardUserDefaults] objectForKey:columnAutosaveName] != nil);
        self.autosaveTableColumns = NO; self.autosaveTableColumns = YES; // Load our saved column configuration
        if ([self _removeDuplicateColumns]) {
            self.autosaveName = nil; self.autosaveName = autosaveName; // Update our saved column configuration
        }
    }
        
    NSMenu *columnsMenu = [[NSMenu alloc] initWithTitle:@""];

    if ([self _allowsAutoresizing]) {
        NSBundle *bundle = [OAApplication bundle];
        NSMenuItem *menuItem;
        
        menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Auto Size Column", @"OmniAppKit", bundle, "autosize column contextual menu item") action:@selector(autosizeColumn:) keyEquivalent:@""];
        [menuItem setTarget:self];
        [columnsMenu addItem:menuItem];

        menuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedStringFromTableInBundle(@"Auto Size All Columns", @"OmniAppKit", bundle, "autosize all columns contextual menu item") action:@selector(autosizeAllColumns:) keyEquivalent:@""];
        [menuItem setTarget:self];
        [columnsMenu addItem:menuItem];

        [columnsMenu addItem:[NSMenuItem separatorItem]];
    }
    
    // Add menu items for all the columns.  For columns that aren't currently displayed, this will be where we store the pointer to the column.
    // Also deactivate any columns that aren't supposed to show up in the default configuration.
    NSArray *defaultColumnIdentifiers = [self _defaultColumnIdentifiers];
    NSMutableArray *deactivateColumns = [NSMutableArray array];
    for (NSTableColumn *tableColumn in self.tableColumns) {
        [self _addItemWithTableColumn:tableColumn toMenu:columnsMenu];
        if (!loadingAutosavedColumns && ![defaultColumnIdentifiers containsObject:tableColumn.identifier]) {
            [deactivateColumns addObject:tableColumn];
        }
    }

    for (NSTableColumn *tableColumn in deactivateColumns) {
        [self deactivateTableColumn:tableColumn];
    }

    [self sizeToFit];

    [[self headerView] setMenu:columnsMenu];
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
    
    if ([self _shouldAddMenuSeparatorAfterColumn:column])
        [menu addItem:[NSMenuItem separatorItem]];
}

- (NSMenuItem *)_menuItemForTableColumn:(NSTableColumn *) column;
{
    for (NSMenuItem *item in [[self columnsMenu] itemArray])
        if (column == [item representedObject])
            return item;
    return nil;
}

- (void)_toggleColumn:(id)sender;
{
    NSMenuItem *item = (NSMenuItem *)sender;
    OBASSERT([item isKindOfClass:[NSMenuItem class]]);

    [self toggleTableColumn:[item representedObject]];
}

- (void)_updateMenuItemState;
{
    if (![self _columnConfigurationEnabled])
        return;
        
    for (NSMenuItem *item in [[self columnsMenu] itemArray]) {
        NSTableColumn *column = [item representedObject];
        [[self _menuItemForTableColumn:column] setState:[self isTableColumnActive:column]];
    }
}

- (void)_autosizeColumn:(NSTableColumn *)tableColumn;
{
    if (![self _allowsAutoresizing])
        return;
        
    BOOL isOutlineView = [self isKindOfClass:[NSOutlineView class]];
    NSCell *dataCell = [tableColumn dataCell];
    NSInteger numberOfRows = [self numberOfRows], rowIndex;
    CGFloat largestCellWidth = 0.0f;
    
    for (rowIndex = 0; rowIndex < numberOfRows; rowIndex++) {
        id objectValue;
        
        if (isOutlineView) {
            NSOutlineView *outlineView = (NSOutlineView *)self;
            objectValue = [outlineView.dataSource outlineView:outlineView objectValueForTableColumn:tableColumn byItem:[(NSOutlineView *)self itemAtRow:rowIndex]];
        } else {
            objectValue = [self.dataSource tableView:self objectValueForTableColumn:tableColumn row:rowIndex];
        }
        
        [dataCell setObjectValue:objectValue];
        NSSize cellSize = [dataCell cellSize];
        if (cellSize.width > largestCellWidth)
            largestCellWidth = cellSize.width;
    }
    
    largestCellWidth = CLAMP(largestCellWidth, [tableColumn minWidth], [tableColumn maxWidth]);
    [tableColumn setWidth:largestCellWidth];
}

@end

@implementation NSTableView (OAColumnConfigurationDelegateDataSourceCoverMethods)

- (BOOL)_columnConfigurationEnabled;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    return [dataSource respondsToSelector:@selector(tableViewDefaultColumnIdentifiers:)] && [dataSource tableViewDefaultColumnIdentifiers:self] != nil;
}

- (NSArray *)_defaultColumnIdentifiers;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableViewDefaultColumnIdentifiers:)]) {
        NSArray *identifiers = [dataSource tableViewDefaultColumnIdentifiers:self];
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
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:menuStringForColumn:)])
        return [dataSource tableView:self menuStringForColumn:column];
    else
        return [[column headerCell] stringValue];
}

- (BOOL)_shouldAllowTogglingColumn:(NSTableColumn *)column;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:shouldAllowTogglingColumn:)])
        return [dataSource tableView:self shouldAllowTogglingColumn:column];
    else
        return YES;
}

- (BOOL)_allowsAutoresizing;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableViewAllowsColumnAutosizing:)])
        return [dataSource tableViewAllowsColumnAutosizing:self];
    else
        return NO;
}

- (BOOL)_shouldAddMenuSeparatorAfterColumn:(NSTableColumn *)column;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:shouldAddMenuSeparatorAfterColumn:)])
        return [dataSource tableView:self shouldAddMenuSeparatorAfterColumn:column];
    else
        return NO;
}

- (void)_willActivateColumn:(NSTableColumn *)column;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:willActivateColumn:)])
        [dataSource tableView:self willActivateColumn:column];
}

- (void)_didActivateColumn:(NSTableColumn *)column;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:didActivateColumn:)])
        [dataSource tableView:self didActivateColumn:column];
}

- (void)_willDeactivateColumn:(NSTableColumn *)column;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:willDeactivateColumn:)])
        [dataSource tableView:self willDeactivateColumn:column];
}

- (void)_didDeactivateColumn:(NSTableColumn *)column;
{
    id <OATableViewColumnConfigurationDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:didDeactivateColumn:)])
        [dataSource tableView:self didDeactivateColumn:column];
}

@end
