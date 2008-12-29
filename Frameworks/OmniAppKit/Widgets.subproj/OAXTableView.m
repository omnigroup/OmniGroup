// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAXTableView.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSTableView-OAExtensions.h"
#import "OATypeAheadSelectionHelper.h"

RCS_ID("$Id$")

@interface OAXTableView (PrivateAPI)
- (void)_commonInit;
- (void)_setupColumnsAndMenu;
- (void)_addMenuItemWithTableColumn:(NSTableColumn *)column;
- (NSMenuItem *)_menuItemForTableColumn:(NSTableColumn *)column;
- (void)_toggleColumn:(id)sender;
- (void)_buildTooltips;
@end

@interface OAXTableView (DelegateDataSourceCoverMethods)
- (NSArray *)_defaultColumnIdentifiers;
- (NSString *)_menuStringForColumn:(NSTableColumn *)column;
- (BOOL)_shouldAllowTogglingColumn:(NSTableColumn *)column;
- (BOOL)_shouldAddMenuSeparatorAfterColumn:(NSTableColumn *)column;
- (void)_willActivateColumn:(NSTableColumn *)column;
- (void)_didActivateColumn:(NSTableColumn *)column;
- (void)_willDeactivateColumn:(NSTableColumn *)column;
- (void)_didDeactivateColumn:(NSTableColumn *)column;
- (BOOL)_shouldEditNextItemWhenEditingEnds;
@end

/*"
Note that this class cannot have a 'deactivateTableColumns' ivar to store the inactive columns.  The problem with that is that if NSTableView's column position/size saving code is turned on, it will blow away table columns that aren't listed in the default.  This can lead to out-of-sync problems.

Also note that this class doesn't subclass -addTableColumn:and -removeTableColumn to update the menu. But it should.
"*/

@implementation OAXTableView

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;

    [self _commonInit];

    return self;
}

- (void)dealloc;
{
    [columnsMenu release];
    [super dealloc];
}


// NSView subclass

- initWithFrame:(NSRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    [self _commonInit];
    
    return self;
}

- (void)resetCursorRects;
{
    [self _buildTooltips];
}


// NSTableView subclass

// We want this method to search both active and inactive columns (OOM depends upon this).  Neither the configuration menu nor the tableColumns array is guaranteed to have all the items (the configuration menu will have all but those that cannot be configured and the tableColumns will have only the active columns).  This is one place where our strategy of not adding an ivar for 'all table columns' is wearing thin.
- (NSTableColumn *)tableColumnWithIdentifier:(id)identifier;
{
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    NSTableColumn  *column;
    
    // First check the configuration menu
    items = [columnsMenu itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex:itemIndex];
        column = [item representedObject];

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

- (void)setDataSource:(id)dataSource;
{
    [super setDataSource:dataSource];
    
    // The new dataSource may want to return different strings
    [self _setupColumnsAndMenu];
    [self _buildTooltips];
}

- (void)reloadData;
{
    NSArray *menuItems;
    unsigned int itemIndex;
    
    [super reloadData];
    
    menuItems = [columnsMenu itemArray];
    for (itemIndex = 0; itemIndex < [menuItems count]; itemIndex++) {
        NSMenuItem *item;
        NSTableColumn *column;
        
        item = [menuItems objectAtIndex:itemIndex];
        column = [item representedObject];
        [[self _menuItemForTableColumn:column] setState:[self isTableColumnActive:column]];
    }

    //[typeAheadHelper rebuildTypeAheadSearchCache];
    [self _buildTooltips];
}

- (void)noteNumberOfRowsChanged;
{
    [super noteNumberOfRowsChanged];
    //[typeAheadHelper rebuildTypeAheadSearchCache];
    [self _buildTooltips];
}

- (void)textDidEndEditing:(NSNotification *)notification;
{
    if (![self _shouldEditNextItemWhenEditingEnds] && [[[notification userInfo] objectForKey:@"NSTextMovement"] intValue] == NSReturnTextMovement) {
        // This is ugly, but just about the only way to do it. NSTableView is determined to select and edit something else, even the text field that it just finished editing, unless we mislead it about what key was pressed to end editing.
        NSMutableDictionary *newUserInfo;
        NSNotification *newNotification;

        newUserInfo = [NSMutableDictionary dictionaryWithDictionary:[notification userInfo]];
        [newUserInfo setObject:[NSNumber numberWithInt:NSIllegalTextMovement] forKey:@"NSTextMovement"];
        newNotification = [NSNotification notificationWithName:[notification name] object:[notification object] userInfo:newUserInfo];
        [super textDidEndEditing:newNotification];

        // For some reason we lose firstResponder status when when we do the above.
        [[self window] makeFirstResponder:self];
    } else {
        [super textDidEndEditing:notification];
    }
}


//  NSToolTipOwner

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data;
{
    return [_dataSource tableView:self tooltipForRow:[self rowAtPoint:point] column:[self columnAtPoint:point]];
}


// New API

- (NSMenu *) columnsMenu;
{
    return columnsMenu;
}

- (NSArray *)inactiveTableColumns;
{
    NSMutableArray *inactiveTableColumns;
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    NSTableColumn  *column;
    
    inactiveTableColumns = [NSMutableArray array];
    items = [columnsMenu itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex:itemIndex];
        column = [item representedObject];

        if (![self isTableColumnActive:column])
            [inactiveTableColumns addObject:column];
    }

    return inactiveTableColumns;
}

- (void)activateTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;
    
    if ([[self tableColumns] indexOfObjectIdenticalTo:column] != NSNotFound)
        // Already active
        return;

    [self _willActivateColumn:column];
        
    item = [self _menuItemForTableColumn:column];
    [item setState:YES];
    
    [self addTableColumn:column];

    [self _didActivateColumn:column];
}

- (void)deactivateTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;
    
    if ([[self tableColumns] indexOfObjectIdenticalTo:column] == NSNotFound)
        // Already inactive
        return;

    [self _willDeactivateColumn:column];
        
    item = [self _menuItemForTableColumn:column];
    [item setState:NO];
    
    [self removeTableColumn:column];

    [self _didDeactivateColumn:column];
}

- (void)toggleTableColumn:(NSTableColumn *)column;
{
    OBPRECONDITION(column);
    OBPRECONDITION([self _menuItemForTableColumn:column]);
    
    if ([self isTableColumnActive:column])
        [self deactivateTableColumn:column];
    else
        [self activateTableColumn:column];
    
    [self tile];
    if ([self autoresizesAllColumnsToFit]) {
        [self sizeToFit];
    }
}

- (BOOL)isTableColumnActive:(NSTableColumn *)column;
{
    return [[self tableColumns] indexOfObject:column] != NSNotFound;
}

@end


@implementation OAXTableView (PrivateAPI)

- (void)_commonInit;
{
    [self _setupColumnsAndMenu];
}

- (void)_setupColumnsAndMenu;
{
    NSEnumerator  *tableColumnEnum;
    NSTableColumn *tableColumn;
    NSArray *defaultColumnIdentifiers;
    
    [columnsMenu release];
    columnsMenu = nil;
    if (_dataSource == nil)
        return;

    columnsMenu = [[NSMenu alloc] initWithTitle:@"Configure Columns"];
        
    // Add menu items for all the columns.  For columns that aren't currently displayed, this will be where we store the pointer to the column.
    // Also deactivate any columns that aren't supposed to show up in the default configuration.
    tableColumnEnum = [[self tableColumns] objectEnumerator];
    defaultColumnIdentifiers = [self _defaultColumnIdentifiers];
    while ((tableColumn = [tableColumnEnum nextObject])) {
        [self _addMenuItemWithTableColumn:tableColumn];
        if (![defaultColumnIdentifiers containsObject:[tableColumn identifier]])
            [self deactivateTableColumn:tableColumn];
    }

    [[self headerView] setMenu:columnsMenu];
}

- (void)_addMenuItemWithTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;
    NSString *title = nil;
    
    // If we don't allow configuration, don't add the item to the menu
    if (![self _shouldAllowTogglingColumn:column])
        return;
    
    title = [self _menuStringForColumn:column];
    item = [[NSMenuItem alloc] initWithTitle:title action:@selector(_toggleColumn:) keyEquivalent:@""];
    [item setState:[self isTableColumnActive:column]];
    [item setRepresentedObject:column];
    [columnsMenu addItem:item];
    [item release];
    
    if ([self _shouldAddMenuSeparatorAfterColumn:column])
        [columnsMenu addItem:[NSMenuItem separatorItem]];
}

- (NSMenuItem *)_menuItemForTableColumn:(NSTableColumn *) column;
{
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    
    items = [columnsMenu itemArray];
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

- (void)_buildTooltips;
{
    NSRange rowRange, columnRange;
    int rowIndex, columnIndex;

    if (![_dataSource respondsToSelector:@selector(tableView:tooltipForRow:column:)])
        return;

    [self removeAllToolTips];
    rowRange = [self rowsInRect:[self visibleRect]];
    columnRange = [self columnsInRect:[self visibleRect]];
    for (columnIndex = columnRange.location; columnIndex < NSMaxRange(columnRange); columnIndex++) {
        for (rowIndex = rowRange.location; rowIndex < NSMaxRange(rowRange); rowIndex++) {
            if ([_dataSource tableView:self tooltipForRow:rowIndex column:columnIndex] != nil)
                [self addToolTipRect:[self frameOfCellAtColumn:columnIndex row:rowIndex] owner:self userData:NULL];
        }
    }
}

@end

@implementation OAXTableView (DelegateDataSourceCoverMethods)

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

- (BOOL)_shouldEditNextItemWhenEditingEnds;
{
    if ([_dataSource respondsToSelector:@selector(tableViewShouldEditNextItemWhenEditingEnds:)])
        return [_dataSource tableViewShouldEditNextItemWhenEditingEnds:self];
    else
        return YES;    
}


@end
