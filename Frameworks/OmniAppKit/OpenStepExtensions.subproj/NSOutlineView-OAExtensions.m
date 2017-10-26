// Copyright 1999-2017 Omni Development, Inc. All rights reserved.
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

NS_ASSUME_NONNULL_BEGIN

@interface NSTableView (OAKeyDownExtensions)
- (BOOL)_processKeyDownCharacter:(unichar)character;
@end

@implementation NSOutlineView (OAExtensions)

- (nullable id)selectedItem;
{
    if ([self numberOfSelectedRows] != 1)
        return nil;

    return [self itemAtRow: [self selectedRow]];
}

- (void)setSelectedItem:(nullable id)item;
{
    [self setSelectedItem: item visibility: OATableViewRowVisibilityLeaveUnchanged];
}

- (void)setSelectedItem:(nullable id)item visibility:(OATableViewRowVisibility)visibility;
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

- (void)setSelectedItems:(nullable NSArray *)items visibility:(OATableViewRowVisibility)visibility;
{
    NSUInteger itemCount = [items count];
    if (!itemCount)
        return;
        
    // Build a hash table of the objects to select to avoid a O(N^2) loop.
    // This also uniques the list of objects nicely, should it not already be.
    NSHashTable *itemTable = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, itemCount);
    
    for (id item in items)
        NSHashInsert(itemTable, item);
    
    // Now, do a O(N) search through all of the rows and select any for which we have objects
    NSMutableIndexSet *rowIndices = [[NSMutableIndexSet alloc] init];

    NSInteger rowCount = [self numberOfRows];
    for (NSInteger rowIndex = 0; rowIndex < rowCount; rowIndex++) {
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

- (void)setSelectedItems:(nullable NSArray *)items;
{
    [self setSelectedItems: items visibility: OATableViewRowVisibilityLeaveUnchanged];
}

- (nullable id)firstItem;
{
    id <NSOutlineViewDataSource> dataSource = self.dataSource;
    NSInteger count = [dataSource outlineView:self numberOfChildrenOfItem:nil];
    if (!count)
        return nil;
    return [dataSource outlineView:self child:0 ofItem:nil];
}

- (void)expandAllItemsAtLevel:(NSInteger)level;
{
    NSInteger rowCount = [self numberOfRows];
    for (NSInteger rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        if ([self levelForRow: rowIndex] == level) {
            id item = [self itemAtRow: rowIndex];
            if ([self isExpandable: item] && ![self isItemExpanded: item]) {
                [self expandItem: item];
                rowCount = [self numberOfRows];
            }
        }
    }
}

- (void)expandItemAndChildren:(nullable id)item;
{
    id <NSOutlineViewDataSource> dataSource = self.dataSource;
    if (item == nil || [dataSource outlineView:self isItemExpandable:item]) {
        if (item != nil)
            [self expandItem:item];
    
        NSInteger childCount = [dataSource outlineView:self numberOfChildrenOfItem:item];
        for (NSInteger childIndex = 0; childIndex < childCount; childIndex++)
            [self expandItemAndChildren:[dataSource outlineView:self child:childIndex ofItem:item]];
    }
}

- (void)collapseItemAndChildren:(nullable id)item;
{
    id <NSOutlineViewDataSource> dataSource = self.dataSource;
    if (item == nil || [dataSource outlineView:self isItemExpandable:item]) {

        // Collapse starting from the bottom.  This makes it feasible to have the smooth scrolling on when doing this (since most of the collapsing then happens off screen and thus doesn't get animated).
        NSInteger childIndex = [dataSource outlineView:self numberOfChildrenOfItem:item];
        while (childIndex--)
            [self collapseItemAndChildren:[dataSource outlineView:self child:childIndex ofItem:item]];
            
        if (item != nil)
            [self collapseItem:item];
    }
}

//
// NSResponder subclass
//

- (void)moveLeft:(nullable id)sender
{
    [self _collapseItems:[self selectedItems] andChildren:NO];
}

- (void)moveRight:(nullable id)sender;
{
    [self _expandItems:[self selectedItems] andChildren:NO];
}

//
// NSTableView subclass (OAExtensions)
//

- (BOOL)_processKeyDownCharacter:(unichar)character;
{
    NSUInteger modifierFlags = [[[NSApplication sharedApplication] currentEvent] modifierFlags];
    
    switch (character) {
        case NSLeftArrowFunctionKey:
            if (modifierFlags & NSEventModifierFlagOption) {
                [self _collapseItems:[self selectedItems] andChildren:YES];
                return YES;
            }
            break;
        case NSRightArrowFunctionKey:
            if (modifierFlags & NSEventModifierFlagOption) {
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

- (IBAction)expandAll:(nullable id)sender;
{
    NSArray *selectedItems = [self selectedItems];
    [self expandItemAndChildren:nil];
    [self setSelectedItems:selectedItems];
}

- (IBAction)contractAll:(nullable id)sender;
{
    NSArray *selectedItems = [self selectedItems];
    [self collapseItemAndChildren:nil];
    [self setSelectedItems:selectedItems];
}

#pragma mark - Private

- (void)_expandItems:(nullable NSArray *)items andChildren:(BOOL)andChildren;
{
    id <NSOutlineViewDataSource> dataSource = self.dataSource;
    NSInteger itemCount = [items count];
    for (NSInteger itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        id selectedItem = [items objectAtIndex:itemIndex];
        if ([dataSource outlineView:self isItemExpandable:selectedItem]) {
            if (andChildren)
                [self expandItemAndChildren:selectedItem];
            else
                [self expandItem:selectedItem];
        }
    }
}

- (void)_collapseItems:(nullable NSArray *)items andChildren:(BOOL)andChildren;
{
    id <NSOutlineViewDataSource> dataSource = self.dataSource;
    NSInteger itemCount = [items count];
    for (NSInteger itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        id selectedItem = [items objectAtIndex:itemIndex];
        if ([dataSource outlineView:self isItemExpandable:selectedItem]) {
            if (andChildren)
                [self collapseItemAndChildren:selectedItem];
            else
                [self collapseItem:selectedItem];
        }
    }
}

@end

NS_ASSUME_NONNULL_END
