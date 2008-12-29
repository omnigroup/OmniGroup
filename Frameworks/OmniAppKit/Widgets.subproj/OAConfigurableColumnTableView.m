// Copyright 1997-2006 Omni Development, Inc.  All rights reserved.
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

RCS_ID("$Id$")

@interface NSTableView (PrivateParts)
- (void)_writePersistentTableColumns;
@end


@interface OAConfigurableColumnTableView (PrivateAPI)
- (void)_commonInit;
- (void)_buildConfigurationMenu;
- (void)_addItemWithTableColumn:(NSTableColumn *)column dataSource: (id) dataSource;
- (NSMenuItem *)_itemForTableColumn: (NSTableColumn *) column;
- (void)_toggleColumn:(id)sender;
@end


/*"
Note that this class cannot have a 'deactivateTableColumns' ivar to store the inactive columns.  The problem with that is that if NSTableView's column position/size saving code is turned on, it will blow away table columns that aren't listed in the default.  This can lead to out-of-sync problems.

Also note that this class doesn't subclass -addTableColumn: and -removeTableColumn to update the popup.
"*/

@implementation OAConfigurableColumnTableView

//
// NSObject subclass
//

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;

    [self _commonInit];

    return self;
}

- (void)dealloc;
{
    [configurationMenu release];
    [super dealloc];
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

- (NSMenu *)menuForEvent:(NSEvent *)event;
{
    return configurationMenu;
}

//
// NSTableView subclass
//

// We want this method to search both active and inactive columns (OOM depends upon this).  Neither the configuration menu nor the tableColumns array is guaranteed to have all the items (the configuration menu will have all but those that cannot be configured and the tableColumns will have only the active columns).  This is on place where our strategy of not adding an ivar for 'all table columsn' is wearing thin.
- (NSTableColumn *)tableColumnWithIdentifier:(id)identifier;
{
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    NSTableColumn  *column;
    
    // First check the configuration menu
    items = [configurationMenu itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex: itemIndex];
        column = [item representedObject];

        if ([[column identifier] isEqual: identifier])
            return column;
    }

    // Then check the table view (since it might have unconfigurable columns)
    items = [self tableColumns];
    itemIndex = [items count];
    while (itemIndex--) {
        column = [items objectAtIndex: itemIndex];
        if ([[column identifier] isEqual: identifier])
            return column;
    }
    
    return nil;
}

- (void) setDataSource: (id) dataSource;
{
    [super setDataSource: dataSource];
    
    confDataSourceFlags.menuString     = [dataSource respondsToSelector: @selector(configurableColumnTableView:menuStringForColumn:)];
    confDataSourceFlags.addSeparator     = [dataSource respondsToSelector: @selector(configurableColumnTableView:shouldAddSeparatorAfterColumn:)];
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

- (NSMenu *) configurationMenu;
{
    return configurationMenu;
}

- (NSArray *)inactiveTableColumns;
{
    NSMutableArray *inactiveTableColumns;
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    NSTableColumn  *column;
    
    inactiveTableColumns = [NSMutableArray array];
    items = [configurationMenu itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex: itemIndex];
        column = [item representedObject];

        if (![self isTableColumnActive: column])
            [inactiveTableColumns addObject: column];
    }

    return inactiveTableColumns;
}

- (void)activateTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;
    
    if ([[self tableColumns] indexOfObjectIdenticalTo:column] != NSNotFound)
        // Already active
        return;

    if (confDataSourceFlags.willActivate)
        [(id)[self dataSource] configurableColumnTableView: self willActivateColumn: column];
        
    item = [self _itemForTableColumn: column];
    [item setState: YES];
    
    [self addTableColumn:column];
    
    // workaround for rdar://4508650. [NSTableView {add,remove}TableColumn:] honor autosaveTableColumns.
    if ([self autosaveTableColumns] && [self autosaveName] != nil) {
        if ([self respondsToSelector:@selector(_writePersistentTableColumns)])
            [self _writePersistentTableColumns];
        else
            OBASSERT_NOT_REACHED("no _writePersistentTableColumns on NSTableView");
    }
        
    if (confDataSourceFlags.didActivate)
        [(id)[self dataSource] configurableColumnTableView: self didActivateColumn: column];
}

- (void)deactivateTableColumn:(NSTableColumn *)column;
{
    NSMenuItem *item;
    
    if ([[self tableColumns] indexOfObjectIdenticalTo:column] == NSNotFound)
        // Already inactive
        return;

    if (confDataSourceFlags.willDeactivate)
        [(id)[self dataSource] configurableColumnTableView: self willDeactivateColumn: column];
        
    item = [self _itemForTableColumn: column];
    [item setState: NO];
    
    [self removeTableColumn:column];

    // workaround for rdar://4508650. [NSTableView {add,remove}TableColumn:] honor autosaveTableColumns.
    if ([self autosaveTableColumns] && [self autosaveName] != nil) {
        if ([self respondsToSelector:@selector(_writePersistentTableColumns)])
            [self _writePersistentTableColumns];
        else
            OBASSERT_NOT_REACHED("no _writePersistentTableColumns on NSTableView");
    }
        
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
    return [[self tableColumns] indexOfObject:column] != NSNotFound;
}

- (void)reloadData;
{
    NSArray *menuItems;
    unsigned int itemIndex;
    
    [super reloadData];
    
    menuItems = [configurationMenu itemArray];
    for (itemIndex = 0; itemIndex < [menuItems count]; itemIndex++) {
        NSMenuItem *item;
        NSTableColumn *column;
        
        item = [menuItems objectAtIndex:itemIndex];
        column = [item representedObject];
        [[self _itemForTableColumn:column] setState:[self isTableColumnActive:column]];
    }
}

@end


@implementation OAConfigurableColumnTableView (PrivateAPI)

- (void)_commonInit;
{
    [self _buildConfigurationMenu];
}

- (void)_buildConfigurationMenu;
{
    NSEnumerator  *tableColumnEnum;
    NSTableColumn *tableColumn;
    id dataSource;

    
    [configurationMenu release];
    configurationMenu = nil;
    dataSource = [self dataSource];
    if (!dataSource)
        return;

    configurationMenu = [[NSMenu alloc] initWithTitle: @"Configure Columns"];
        
    // Add items for all the columns.  For columsn that aren't currently displayed, this will be where we store the pointer to the column.
    tableColumnEnum = [[self tableColumns] objectEnumerator];
    while ((tableColumn = [tableColumnEnum nextObject]))
        [self _addItemWithTableColumn:tableColumn dataSource: dataSource];
}

- (void)_addItemWithTableColumn:(NSTableColumn *)column dataSource: (id) dataSource;
{
    NSMenuItem *item;
    NSString *title = nil;
    
    // If we don't allow configuration, don't add the item to the menu
    if (confDataSourceFlags.allowToggle && ![dataSource configurableColumnTableView:self shouldAllowTogglingColumn:column])
        return;
    
    if (confDataSourceFlags.menuString)
        title = [dataSource configurableColumnTableView:self menuStringForColumn:column];
    if (!title)
        title = [[column headerCell] stringValue];
        
    item = [[NSMenuItem alloc] initWithTitle:title action:@selector(_toggleColumn:) keyEquivalent: @""];
    [item setState:[self isTableColumnActive:column]];
    [item setRepresentedObject:column];
    [configurationMenu addItem: item];
    [item release];
    
    if (confDataSourceFlags.addSeparator && [dataSource configurableColumnTableView:self shouldAddSeparatorAfterColumn:column])
        [configurationMenu addItem: [NSMenuItem separatorItem]];
}

- (NSMenuItem *)_itemForTableColumn: (NSTableColumn *) column;
{
    NSArray        *items;
    unsigned int    itemIndex;
    NSMenuItem     *item;
    
    items = [configurationMenu itemArray];
    itemIndex = [items count];
    while (itemIndex--) {
        item = [items objectAtIndex: itemIndex];
        if (column == [item representedObject])
            return item;
    }

    return nil;
}

- (void)_toggleColumn:(id)sender;
{
    NSMenuItem *item;
    
    item = (NSMenuItem *)sender;
    OBASSERT([item isKindOfClass: [NSMenuItem class]]);

    [self toggleTableColumn: [item representedObject]];
}

@end
