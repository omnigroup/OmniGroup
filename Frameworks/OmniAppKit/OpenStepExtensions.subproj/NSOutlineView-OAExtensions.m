// Copyright 1999-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniAppKit/NSOutlineView-OAExtensions.h>

#import <OmniAppKit/NSTableView-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@interface NSTableView (OAKeyDownExtensions)
- (BOOL)_processKeyDownCharacter:(unichar)character;
@end

@interface NSOutlineView (OAExtensionsPrivate)
- (void)_expandItems:(NSArray *)items andChildren:(BOOL)andChildren;
- (void)_collapseItems:(NSArray *)items andChildren:(BOOL)andChildren;
@end

@implementation NSOutlineView (OAExtensions)

- (id)selectedItem;
{
    if ([self numberOfSelectedRows] != 1)
        return nil;

    return [self itemAtRow: [self selectedRow]];
}

- (void)setSelectedItem:(id)item;
{
    [self setSelectedItem: item visibility: OATableViewRowVisibilityLeaveUnchanged];
}

- (void)setSelectedItem:(id)item visibility:(OATableViewRowVisibility)visibility;
{
    if (item == nil) {
        [self deselectAll:nil];
        return;
    }
        
    [self setSelectedItems:[NSArray arrayWithObject:item] visibility:visibility];
}


- (NSArray *)selectedItems;
{
    NSIndexSet *rowIndices = [self selectedRowIndexes];
    
    if (![rowIndices count])
        return [NSArray array];
    
    NSMutableArray *items = [[NSMutableArray alloc] initWithCapacity:[rowIndices count]];
    [items autorelease];
    OFForEachIndex(rowIndices, anIndex) {
        // Apple bug #2854415.  An empty outline will return an enumerator that returns row==0 and itemAtRow: will return nil, causing  us to try to insert nil into the array.
        id item = [self itemAtRow:anIndex];
        if (item)
            [items addObject:item];
    }

    return items;
}

- (void)setSelectedItems:(NSArray *)items visibility:(OATableViewRowVisibility)visibility;
{
    NSHashTable *itemTable;
    unsigned int itemIndex, itemCount, rowIndex, rowCount;
    
    itemCount = [items count];
    if (!itemCount)
        return;
        
    // Build a hash table of the objects to select to avoid a O(N^2) loop.
    // This also uniques the list of objects nicely, should it not already be.
    itemTable = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, itemCount);
    itemIndex = itemCount;
    while (itemIndex--)
        NSHashInsert(itemTable, [items objectAtIndex:itemIndex]);
    
    // Now, do a O(N) search through all of the rows and select any for which we have objects
    NSMutableIndexSet *rowIndices = [[NSMutableIndexSet alloc] init];
    rowCount = [self numberOfRows];
    for (rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        id item = [self itemAtRow:rowIndex];
        if (NSHashGet(itemTable, item)) {
            // We should be able to always extend the selection, since we deselected everything above. However, as of OS X DP4, if we do that, it sometimes triggers an assertion and NSLog in NSTableView. (Usually that happens after dragging an item.)
            [rowIndices addIndex:rowIndex];
        }
    }

    NSFreeHashTable(itemTable);
    
    [self selectRowIndexes:rowIndices byExtendingSelection:NO];
    [rowIndices release];
     
    [self scrollSelectedRowsToVisibility: visibility];
}

- (void)setSelectedItems:(NSArray *)items;
{
    [self setSelectedItems: items visibility: OATableViewRowVisibilityLeaveUnchanged];
}

- (id)firstItem;
{
    unsigned int count;
    
    count = [_dataSource outlineView: self numberOfChildrenOfItem: nil];
    if (!count)
        return nil;
    return [_dataSource outlineView: self child: 0 ofItem: nil];
}

- (void)expandAllItemsAtLevel:(unsigned int)level;
{
    unsigned int rowCount, rowIndex;
    
    rowCount = [self numberOfRows];
    for (rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        if ((unsigned)[self levelForRow: rowIndex] == level) {
            id item;
            
            item = [self itemAtRow: rowIndex];
            if ([self isExpandable: item] && ![self isItemExpanded: item]) {
                [self expandItem: item];
                rowCount = [self numberOfRows];
            }
        }
    }
}

- (void)expandItemAndChildren:(id)item;
{
    if (item == nil || [_dataSource outlineView:self isItemExpandable:item]) {
        unsigned int childIndex, childCount;

        if (item != nil)
            [self expandItem:item];
    
        childCount = [_dataSource outlineView:self numberOfChildrenOfItem:item];
        for (childIndex = 0; childIndex < childCount; childIndex++)
            [self expandItemAndChildren:[_dataSource outlineView:self child:childIndex ofItem:item]];
    }
}

- (void)collapseItemAndChildren:(id)item;
{
    if (item == nil || [_dataSource outlineView:self isItemExpandable:item]) {
        unsigned int childIndex;

        // Collapse starting from the bottom.  This makes it feasible to have the smooth scrolling on when doing this (since most of the collapsing then happens off screen and thus doesn't get animated).
        childIndex = [_dataSource outlineView:self numberOfChildrenOfItem:item];
        while (childIndex--)
            [self collapseItemAndChildren:[_dataSource outlineView:self child:childIndex ofItem:item]];
            
        if (item != nil)
            [self collapseItem:item];
    }
}

//
// NSResponder subclass
//

- (void)moveLeft:(id)sender
{
    [self _collapseItems:[self selectedItems] andChildren:NO];
}

- (void)moveRight:(id)sender;
{
    [self _expandItems:[self selectedItems] andChildren:NO];
}

//
// NSTableView subclass (OAExtensions)
//

- (BOOL)_processKeyDownCharacter:(unichar)character;
{
    unsigned int modifierFlags = [[NSApp currentEvent] modifierFlags];
    
    switch (character) {
        case NSLeftArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask) {
                [self _collapseItems:[self selectedItems] andChildren:YES];
                return YES;
            }
            break;
        case NSRightArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask) {
                [self _expandItems:[self selectedItems] andChildren:YES];
                return YES;
            }
            break;
        default:
            break;
    }
    
    return [super _processKeyDownCharacter:character];
}

//
// Actions
//

- (IBAction)expandAll:(id)sender;
{
    NSArray *selectedItems;

    selectedItems = [self selectedItems];
    [self expandItemAndChildren:nil];
    [self setSelectedItems:selectedItems];
}

- (IBAction)contractAll:(id)sender;
{
    NSArray *selectedItems;

    selectedItems = [self selectedItems];
    [self collapseItemAndChildren:nil];
    [self setSelectedItems:selectedItems];
}

@end

@implementation NSOutlineView (OAExtensionsPrivate)

- (void)_expandItems:(NSArray *)items andChildren:(BOOL)andChildren;
{
    unsigned int itemCount, itemIndex;
    
    itemCount = [items count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        id selectedItem;
        
        selectedItem = [items objectAtIndex:itemIndex];
        if ([_dataSource outlineView:self isItemExpandable:selectedItem]) {
            if (andChildren)
                [self expandItemAndChildren:selectedItem];
            else
                [self expandItem:selectedItem];
        }
    }
}

- (void)_collapseItems:(NSArray *)items andChildren:(BOOL)andChildren;
{
    unsigned int itemCount, itemIndex;
    
    itemCount = [items count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        id selectedItem;
        
        selectedItem = [items objectAtIndex:itemIndex];
        if ([_dataSource outlineView:self isItemExpandable:selectedItem]) {
            if (andChildren)
                [self collapseItemAndChildren:selectedItem];
            else
                [self collapseItem:selectedItem];
        }
    }
}

@end
