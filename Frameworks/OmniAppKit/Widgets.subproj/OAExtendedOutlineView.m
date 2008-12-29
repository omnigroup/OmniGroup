// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAExtendedOutlineView.h"

#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#import "NSImage-OAExtensions.h"
#import "NSOutlineView-OAExtensions.h"
#import "NSString-OAExtensions.h"
#import "NSView-OAExtensions.h"
// #import "OAInspectorRegistry.h"
#import "OAOutlineViewEnumerator.h"
#import "OATypeAheadSelectionHelper.h"

RCS_ID("$Id$")

@interface OAExtendedOutlineView (Private)
- (void)_initExtendedOutlineView;
- (void)startDrag:(NSEvent *)event;
- (NSImage *)_dragImageForItems:(NSArray *)dragItems;
- (void)registerForDragging;
- (void)updateAutoExpandedItems;
- (NSArray *)selectedItemsWithoutSelectedParents;
- (BOOL)_delegateAllowsEditTableColumn:(NSTableColumn *)tableColumn item:(id)item;
- (NSString *)_labelForRow:(int)row;
@end

#define DISCLOSURE_TRIANGLE_WIDTH 17.0
#define TRANSITION_TIME (0.25)

@implementation OAExtendedOutlineView

- (id)initWithFrame:(NSRect)rect;
{
    if (![super initWithFrame:rect])
        return nil;

    [self _initExtendedOutlineView];
    
    return self;
}

- initWithCoder:(NSCoder *)coder;
{
    if (![super initWithCoder:coder])
        return nil;

    [self _initExtendedOutlineView];
        
    return self;
}

- (void)dealloc;
{
    [autoExpandedItems release];
    [self unregisterDraggedTypes];
    [super dealloc];
}

// API

- (id)parentItemForRow:(int)row child:(unsigned int *)childIndexPointer;
{
    int originalLevel;
    
    originalLevel = [self levelForRow:row];
    return [self parentItemForRow:row indentLevel:originalLevel child:childIndexPointer];
}

- (id)parentItemForRow:(int)row indentLevel:(int)childLevel child:(unsigned int *)childIndexPointer;
{
    unsigned int childIndex;

    childIndex = 0;

    while (row-- >= 0) {
        int currentLevel;
        
        currentLevel = [self levelForRow:row];
        if (currentLevel < childLevel) {
            if (childIndexPointer)
                *childIndexPointer = childIndex;
            return [self itemAtRow:row];
        } else if (currentLevel == childLevel)
            childIndex++;
    }
    if (childIndexPointer)
        *childIndexPointer = childIndex;
    return nil;
}

- (void)setShouldEditNextItemWhenEditingEnds:(BOOL)value;
{
    flags.shouldEditNextItemWhenEditingEnds = value;
}

- (BOOL)shouldEditNextItemWhenEditingEnds;
{
    return flags.shouldEditNextItemWhenEditingEnds;
}

- (void)setTypeAheadSelectionEnabled:(BOOL)newSetting;
{
    flags.allowsTypeAheadSelection = newSetting;
    
    if (flags.allowsTypeAheadSelection) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outlineViewItemDidExpand:) name:NSOutlineViewItemDidExpandNotification object:(id)self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(outlineViewItemDidCollapse:) name:NSOutlineViewItemDidCollapseNotification object:(id)self];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSOutlineViewItemDidExpandNotification object:(id)self];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSOutlineViewItemDidCollapseNotification object:(id)self];
    }
}

- (BOOL)typeAheadSelectionEnabled;
{
    return flags.allowsTypeAheadSelection;
}

- (void)setIndentsWithTabKey:(BOOL)value;
{
    flags.indentWithTabKey = value;
}

- (BOOL)indentsWithTabKey;
{
    return flags.indentWithTabKey;
}

- (void)setCreatesNewItemWithReturnKey:(BOOL)value;
{
    flags.newItemWithReturnKey = value;
}

- (BOOL)createsNewItemWithReturnKey;
{
    return flags.newItemWithReturnKey;
}

- (void)autoExpandItems:(NSArray *)items;
{
    unsigned int itemIndex, itemCount;
    id item;
    
    // First, close any previously auto-expanded items (in reverse order)
    itemIndex = [autoExpandedItems count];
    while (itemIndex--) {
        item = [autoExpandedItems objectAtIndex:itemIndex];
        [self collapseItem:item];
    }
    
    // Then, open up the new items and remember them to auto close later.
    itemCount = [items count];
    [autoExpandedItems release];
    autoExpandedItems = [[NSMutableArray alloc] initWithCapacity:itemCount];

    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        item = [items objectAtIndex:itemIndex];
        if ([self isExpandable:item] && ![self isItemExpanded:item]) {
            [self expandItem:item];
            [autoExpandedItems addObject:item];
        }
    }
}

- (CGFloat)rowOffset:(NSInteger)row;
{
    return 0;
}


// Actions

- (IBAction)expandSelection:(id)sender;
{
    NSArray *selectedItems;
    NSEnumerator *itemEnumerator;
    id item;
        
    selectedItems = [self selectedItems];
    itemEnumerator = [selectedItems objectEnumerator];
    while ((item = [itemEnumerator nextObject]))
        [self expandItemAndChildren:item];
    
    [self setSelectedItems:selectedItems];
}

- (IBAction)contractSelection:(id)sender;
{
    NSArray *selectedItems;
    NSEnumerator *itemEnumerator;
    id item;
    
    selectedItems = [self selectedItems];
    itemEnumerator = [selectedItems reverseObjectEnumerator];
    while ((item = [itemEnumerator nextObject]))
        [self collapseItemAndChildren:item];
    
    [self setSelectedItems:selectedItems];
}

- (IBAction)group:(id)sender;
{
    NSArray *selectedItems;
    NSEnumerator *itemEnumerator;
    id item;
    id groupItem;
    int selectedRow, numberOfRows;
    id parentItem;
    unsigned int childIndex;
    int newItemRow;
    NSArray *tableColumns;
   
    if (![_dataSource respondsToSelector:@selector(outlineView:createNewItemAsChild:ofItem:)] || ![_dataSource respondsToSelector:@selector(outlineView:parentItem:moveChildren:toNewParentItem:)])
        return;

    selectedItems = [self selectedItemsWithoutSelectedParents];
    if (![selectedItems count])
        return;
        
    numberOfRows = [self numberOfRows];
    selectedRow = [self selectedRow];
    parentItem = [self parentItemForRow:selectedRow child:&childIndex];
        
    if ([_dataSource outlineView:self createNewItemAsChild:childIndex ofItem:parentItem]) {
        groupItem = [_dataSource outlineView:self child:childIndex ofItem:parentItem];
        
        itemEnumerator = [selectedItems objectEnumerator];
        while ((item = [itemEnumerator nextObject])) {
            selectedRow = [self rowForItem:item];
            parentItem = [self parentItemForRow:selectedRow child:&childIndex];
            [_dataSource outlineView:self parentItem:parentItem moveChildren:[NSArray arrayWithObject:item] toNewParentItem:groupItem];
            [self reloadData];
        }
        [self expandItem:groupItem];
        newItemRow = [self rowForItem:groupItem];
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newItemRow] byExtendingSelection:NO];
        
        // Edit the first editable column            
        tableColumns = [self tableColumns];
        NSUInteger columnIndex, columnCount = [tableColumns count];
        for (columnIndex = 0; columnIndex < columnCount; columnIndex++) {
            NSTableColumn *column;
            
            column = [tableColumns objectAtIndex:columnIndex];
            if ([column isEditable]) {
                [self editColumn:columnIndex row:newItemRow withEvent:nil select:YES];
                break;
            }
        }
    }

    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Group", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for grouping outline view items")];
}
    
- (IBAction)ungroup:(id)sender;
{
    NSArray *selectedItems;
    NSMutableArray *children;
    NSEnumerator *itemEnumerator;
    id item, parentItem;
    int selectedRow;
    unsigned int groupIndex;
    unsigned int childIndex, childCount;

    if (![_dataSource respondsToSelector:@selector(outlineView:parentItem:moveChildren:toNewParentItem:)])
        return;
        
    selectedItems = [self selectedItems];
    itemEnumerator = [selectedItems reverseObjectEnumerator];
    while ((item = [itemEnumerator nextObject])) {
        selectedRow = [self rowForItem:item];
        parentItem = [self parentItemForRow:selectedRow child:&groupIndex];
        childCount = [_dataSource outlineView:self numberOfChildrenOfItem:item];
        children = [NSMutableArray arrayWithCapacity:childCount];
        for (childIndex = 0; childIndex < childCount; childIndex++) {
            [children addObject:[_dataSource outlineView:self child:childIndex ofItem:item]];
        }
        [_dataSource outlineView:self parentItem:item moveChildren:children toNewParentItem:parentItem beforeIndex:groupIndex+1];
        
        if ([_dataSource respondsToSelector:@selector(outlineView:deleteItems:)] && (![_dataSource respondsToSelector:@selector(outlineView:shouldDeleteItemDuringUngroup:)] || [_dataSource outlineView:self shouldDeleteItemDuringUngroup:item]))
            [_dataSource outlineView:self deleteItems:[NSArray arrayWithObject:item]];
    }
    
    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Ungroup", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for ungrouping outline view items")];

}

- (IBAction)addNewItem:(id)sender;
{
    if ([_dataSource respondsToSelector:@selector(outlineView:createNewItemAsChild:ofItem:)]) {
        int selectedRow, numberOfRows;
        id parentItem;
        unsigned int childIndex;
    
        numberOfRows = [self numberOfRows];
        selectedRow = [self selectedRow];
        if (numberOfRows == 0 || selectedRow == -1) {
            parentItem = nil;
            childIndex = [_dataSource outlineView:self numberOfChildrenOfItem:parentItem];
        } else {
            parentItem = [self parentItemForRow:selectedRow child:&childIndex];
            childIndex++; // Insert after current line
        }

        if ([_dataSource outlineView:self createNewItemAsChild:childIndex ofItem:parentItem]) {
            id item;
            int newItemRow;
            NSArray *tableColumns;
            int columnIndex, columnCount;
        
            [self reloadData];
            item = [_dataSource outlineView:self child:childIndex ofItem:parentItem];
            newItemRow = [self rowForItem:item];
            [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newItemRow] byExtendingSelection:NO];
            
            // Edit the first editable column            
            tableColumns = [self tableColumns];
            columnCount = [tableColumns count];
            for (columnIndex = 0; columnIndex < columnCount; columnIndex++) {
                NSTableColumn *column;
                
                column = [tableColumns objectAtIndex:columnIndex];
                if ([column isEditable] && [self _delegateAllowsEditTableColumn:column item:item]) {
                    [self editColumn:columnIndex row:newItemRow withEvent:nil select:YES];
                    break;
                }
            }
        }
    }
}

// Just like NSText

- (IBAction)copy:(id)sender;
{
    if ([_dataSource respondsToSelector:@selector(outlineView:copyItems:toPasteboard:)])
        [_dataSource outlineView:self copyItems:[self selectedItemsWithoutSelectedParents] toPasteboard:[NSPasteboard generalPasteboard]];
}

- (IBAction)cut:(id)sender;
{
    [self copy:sender];
    [self delete:sender];

    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Cut", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for cutting outline view items")];
}

- (IBAction)delete:(id)sender;
{
    [self deleteBackward:nil];
}

- (IBAction)paste:(id)sender;
{
    if ([_dataSource respondsToSelector:@selector(outlineView:pasteItemsFromPasteboard:parentItem:child:)]) {
        int selectedRow, numberOfRows;
        id parentItem;
        unsigned int childIndex;
    
        numberOfRows = [self numberOfRows];
        selectedRow = [self selectedRow];
        if (numberOfRows == 0 || selectedRow == -1) {
            parentItem = nil;
            childIndex = 0;
        } else {
            parentItem = [self parentItemForRow:selectedRow child:&childIndex];
            childIndex++; // Paste after current line
        }
            
        [_dataSource outlineView:self pasteItemsFromPasteboard:[NSPasteboard generalPasteboard] parentItem:parentItem child:childIndex];
        [self reloadData];
    }
}


// NSResponder

//- (BOOL)becomeFirstResponder;
//{
//    BOOL willBecome;
//
//    willBecome = [super becomeFirstResponder];
//    if (willBecome)
//        [[NSNotificationCenter defaultCenter] postNotificationName:OAInspectorSelectionDidChangeNotification object:(id)self];
//    return willBecome;
//}

//- (BOOL)resignFirstResponder;
//{
//    BOOL willResign;
//
//    willResign = [super resignFirstResponder];
//    if (willResign)
//        [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:OAInspectorSelectionDidChangeNotification object:self] postingStyle:NSPostWhenIdle];
//    return willResign;
//}

- (void)keyDown:(NSEvent *)theEvent;
{
    NSString *characters;
    unichar firstCharacter;
    unsigned int modifierFlags;

    characters = [theEvent characters];
    modifierFlags = [theEvent modifierFlags];
    firstCharacter = [characters characterAtIndex:0];

    // See if there's an item whose title matches what the user is typing.
    // This can only be activated, initially, by typing an alphanumeric character.  This means it's smart enough to know when the user is, say, pressing space to page down, or pressing space separating two search string words. Should this still apply here?
    flags.allowsTypeAheadSelection = ![[NSUserDefaults standardUserDefaults] boolForKey:@"DisableTypeAheadSelection"];
    if (flags.allowsTypeAheadSelection && ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:firstCharacter] || ([typeAheadHelper isProcessing] && ![[NSCharacterSet controlCharacterSet] characterIsMember:firstCharacter]))) {
        if (typeAheadHelper == nil) {
            typeAheadHelper = [[OATypeAheadSelectionHelper alloc] init];
            [typeAheadHelper setDataSource:self];
        }
        
        [typeAheadHelper processKeyDownCharacter:firstCharacter];
        return;
    }
    
    switch (firstCharacter) {
        case ' ': {
            SEL doubleAction;

            // Emulate a double-click
            doubleAction = [self doubleAction];
            if (doubleAction != NULL && [self sendAction:doubleAction to:[self target]])
                return; // We've performed our action
            else
                break; // Do standard key handling
        }
        case 'e': { // not reached if type-ahead selection is turned on
            NSInteger columnIndex, rowIndex;
    
            columnIndex = [[self tableColumns] indexOfObject:[self outlineTableColumn]];
            rowIndex = [self selectedRow];
            [self editColumn:columnIndex row:rowIndex withEvent:nil select:YES];
            return;
        } 
        case 'g': // not reached if type-ahead selection is turned on
            [self group:nil];
            return;
        case 'u': // not reached if type-ahead selection is turned on
            [self ungroup:nil];
            return;
        case '<': {
            NSArray *selectedItems;

            selectedItems = [self selectedItems];
            [self contractAll:nil];
            [self setSelectedItems:selectedItems];
            return;
        }
        case '>': {
            NSArray *selectedItems;

            selectedItems = [self selectedItems];
            [self expandAll:nil];
            [self setSelectedItems:selectedItems];
            return;
        }
        case NSLeftArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask) {
                [self contractSelection:nil];
                return;
            }
            break;
        case NSRightArrowFunctionKey:
            if (modifierFlags & NSAlternateKeyMask) {
                [self expandSelection:nil];
                return;
            }
            break;
        default:
            break;
    }
    [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
}

- (void)deleteForward:(id)sender;
{
    if ([_dataSource respondsToSelector:@selector(outlineView:deleteItems:)]) {
        int selectedRow;    
        
        selectedRow = [self selectedRow];
        if (selectedRow == -1)
            return;
        
        [_dataSource outlineView:self deleteItems:[self selectedItems]];
        [self reloadData];
        
        // Maintain the selection after deletions
        int numberOfRows = [self numberOfRows];
        if (numberOfRows) {
            unsigned newSelection;
            if (selectedRow > (numberOfRows - 1))
                newSelection = numberOfRows - 1;
            else
                newSelection = selectedRow;
            [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newSelection] byExtendingSelection:NO];
        } else
            [self deselectAll:sender];
    }
}

- (void)deleteBackward:(id)sender;
{
    if ([_dataSource respondsToSelector:@selector(outlineView:deleteItems:)]) {
        int selectedRow;    
        
        selectedRow = [self selectedRow];
        if (selectedRow == -1)
            return;
        
        [_dataSource outlineView:self deleteItems:[self selectedItems]];
        [self reloadData];
        
        // Maintain the selection after deletions
        int numberOfRows = [self numberOfRows];
        if (numberOfRows) {
            unsigned newSelection;
            if (selectedRow == 0)
                newSelection = 0;
            else
                newSelection = selectedRow - 1;
            [self selectRowIndexes:[NSIndexSet indexSetWithIndex:newSelection] byExtendingSelection:NO];
        } else
            [self deselectAll:sender];
    }
}

- (void)insertTab:(id)sender;
{
    NSArray *selectedItems;
    id selectedItem;
    int levelOfSelectedItem;
    int itemCount, itemIndex;
    int currentRow;
    int selectedRow;
    
    if (!flags.indentWithTabKey) {
        [[self window] selectNextKeyView:self];
        return;
    }
        
    // We can't do this if they don't implement outlineView:parentItem:moveChildren:toNewParentItem
    if ([_dataSource respondsToSelector:@selector(outlineView:parentItem:moveChildren:toNewParentItem:)] == NO)
        return;
        
    selectedItems = [self selectedItems];
    itemCount = [selectedItems count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        selectedItem = [selectedItems objectAtIndex:itemIndex];
        levelOfSelectedItem = [self levelForItem:selectedItem];
        selectedRow = [self rowForItem:selectedItem];
        
        currentRow = selectedRow - 1;
        while (currentRow >= 0) {
            id potentialParent;
            int levelOfPotentialParent;
            
            potentialParent = [self itemAtRow:currentRow];
            levelOfPotentialParent = [self levelForItem:potentialParent];
            
            if (levelOfPotentialParent == levelOfSelectedItem) {
                NSArray *movingChildren;
                id previousParent;
                unsigned int childIndex;
                
                movingChildren = [NSArray arrayWithObject:selectedItem];
                previousParent = [self parentItemForRow:selectedRow child:&childIndex];
        
                // If you're the zeroth child of your parent, you cannot be indented any more.
                if (childIndex == 0)
                    return;
    
                [_dataSource outlineView:self parentItem:previousParent moveChildren:movingChildren toNewParentItem:potentialParent];
                [self expandItem:potentialParent];
    
                // Reload those items which were affected
                if (previousParent == nil) {
                    [self reloadData];
                } else {
                    [self reloadItem:previousParent reloadChildren:YES];
                    [self reloadItem:potentialParent reloadChildren:YES];
                }
                
    
                break;
            }
            
            // Move upwards through the list
            currentRow--;
        }
    }
    [self setSelectedItems:selectedItems];

    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Indent", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for indenting outline view items")];
}

- (void)insertBacktab:(id)sender;
{
    if (!flags.indentWithTabKey) {
        [[self window] selectPreviousKeyView:self];
        return;
    }
        
// Determine if the dataSource supports the required extension methods for this feature, and if so, determine if this operation is valid for the current selection
    if ([_dataSource respondsToSelector:@selector(outlineView:parentItem:moveChildren:toNewParentItem:beforeIndex:)] == NO)
        return;
    
    NSArray *selectedItems = [self selectedItems];
    unsigned int itemIndex, itemCount = [selectedItems count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        id selectedItem = [selectedItems objectAtIndex:itemIndex];
        int selectedRow = [self rowForItem:selectedItem];
        int levelOfSelectedItem = [self levelForItem:selectedItem];

        if (levelOfSelectedItem == 0)
            continue;

        unsigned int peerIndex;
        id parent = [self parentItemForRow:selectedRow child:&peerIndex];
        unsigned int parentChildrenCount = [_dataSource outlineView:self numberOfChildrenOfItem:parent];
        NSMutableArray *peersAfterSelectedItem = [NSMutableArray array];
        
        // The peers of the selection which come after it will become children of the selected item
        for (peerIndex += 1; peerIndex < parentChildrenCount; peerIndex++) {
            id peer;
            
            peer = [_dataSource outlineView:self child:peerIndex ofItem:parent];
            [peersAfterSelectedItem addObject:peer];
        }
    
        // If there were any peers after the selection, move them to the end of the selected item's list of children
        if ([peersAfterSelectedItem count] > 0) {
            [_dataSource outlineView:self parentItem:parent moveChildren:peersAfterSelectedItem toNewParentItem:selectedItem beforeIndex:-1];
        
            // Make sure the selected item is expanded
            if ([_dataSource outlineView:self isItemExpandable:selectedItem])
                [self expandItem:selectedItem];
        }
    
        unsigned int parentIndex;
        id parentsParent = [self parentItemForRow:[self rowForItem:parent] child:&parentIndex];
    
        // Make the selection become a peer of its parent
        [_dataSource outlineView:self parentItem:parent moveChildren:[NSArray arrayWithObject:selectedItem] toNewParentItem:parentsParent beforeIndex:(parentIndex + 1)];
    }
    
    [self reloadData];

    // Reselect since, in some situations, NSOutlineView gets confused with regards to what should be selected
    [self setSelectedItems:selectedItems];

    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Unindent", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for unindenting outline view items")];
}

- (void)insertNewline:(id)sender;
{
    if (!flags.newItemWithReturnKey) {
        NSInteger columnIndex, rowIndex;

        columnIndex = [[self tableColumns] indexOfObject:[self outlineTableColumn]];
        rowIndex = [self selectedRow];
        [self editColumn:columnIndex row:rowIndex withEvent:nil select:YES];
        return;
    }
        
    [self addNewItem:sender];
}

- (void)moveUp:(id)sender;
{
    NSIndexSet *selection = [self selectedRowIndexes];
    if (![selection count])
        return;
    unsigned rowIndex = [selection firstIndex];
    if (rowIndex == 0)
        return;
    
    rowIndex --;
    
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
    [self scrollRowToVisible:rowIndex];
}

- (void)moveDown:(id)sender;
{
    NSIndexSet *selection = [self selectedRowIndexes];
    if (![selection count])
        return;
    int rowIndex = [selection lastIndex];
    if (rowIndex >= [self numberOfRows] - 1)
        return;
    
    rowIndex ++;
    
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
    [self scrollRowToVisible:rowIndex];
}

- (void)moveLeft:(id)sender
{
    id selectedItem;
    int selectedRow;

    selectedRow = [self selectedRow];
    selectedItem = [self itemAtRow:selectedRow];

    if ([_dataSource outlineView:self isItemExpandable:selectedItem] ||
        [self isItemExpanded:selectedItem])
        [self collapseItem:selectedItem];
}

- (void)moveRight:(id)sender;
{
    id selectedItem;
    int selectedRow;

    selectedRow = [self selectedRow];
    selectedItem = [self itemAtRow:selectedRow];

    if ([_dataSource outlineView:self isItemExpandable:selectedItem])
        [self expandItem:selectedItem];
}

- (NSMenu *)menuForEvent:(NSEvent *)event;
{
    NSPoint point;
    int rowIndex;
    id item;
    
    if (![_dataSource respondsToSelector:@selector(outlineView:contextMenuForItem:)])
        return nil;

    point = [self convertPoint:[event locationInWindow] fromView:nil];
    rowIndex = [self rowAtPoint:point];
    if (rowIndex == -1) {
        item = nil;
        if ([self allowsEmptySelection])
            [self deselectAll: nil];
    } else {
        item = [self itemAtRow:rowIndex];
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
    }
    
    return [_dataSource outlineView:self contextMenuForItem:item];
}

// NSView

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (BOOL)shouldDelayWindowOrderingForEvent:(NSEvent *)anEvent 
{
    return YES;
}

- (void)setFrameSize:(NSSize)newSize;
{
    NSRect contentViewFrame;

    // Normally, our frame size is exactly tall enough to fit all of our rows. However, this causes a problem when the outline view is shorter than the scroll view's content view (when there are not enough rows to fill up the whole area). When we drag to the bottom of the outline, the drag image gets clipped to the last row. To fix this problem, we force ourself to always be at least as tall as the scroll view's content view.
    contentViewFrame = [[[self enclosingScrollView] contentView] frame];
    newSize.height = MAX(newSize.height, contentViewFrame.size.height);

    [super setFrameSize:newSize];
}

- (void)drawRect:(NSRect)rect;
{
    NSRect rowFrame;

    [super drawRect:rect];

/* Commenting this out since it's ugly, blinky, and makes it difficult to see the drag destination indicator.
    if (draggingSourceItem && (!flags.isDraggingDestination || flags.isDraggingDestinationAcceptable)) {
        rowFrame = [self rectOfRow:dragSourceRow];
        [[NSColor colorWithDeviceRed:0.2 green:0.2 blue:0.4 alpha:0.8] set];
        NSRectFillUsingOperation(rowFrame, NSCompositeSourceOver);
    } */

    if (flags.isDraggingDestination && flags.isDraggingDestinationAcceptable) {
        NSRect outlineTableColumnRect;
        NSPoint insertionPoint;
        NSBezierPath *path;
        
        if (dragDestinationRow >= [self numberOfRows]) {
            rowFrame = [self rectOfRow:dragDestinationRow-1];
            rowFrame.origin.y = NSMaxY(rowFrame);
        } else
            rowFrame = [self rectOfRow:dragDestinationRow];
        
        outlineTableColumnRect = [self rectOfColumn:[[self tableColumns] indexOfObject:[self outlineTableColumn]]];
        
        insertionPoint.x = NSMinX(outlineTableColumnRect) + [self indentationPerLevel] * dragDestinationLevel + DISCLOSURE_TRIANGLE_WIDTH;
        insertionPoint.y = rowFrame.origin.y;

        path = [NSBezierPath bezierPath];
        [path appendBezierPathWithArcWithCenter:insertionPoint radius:4.5 startAngle:0 endAngle:360];
        [[NSColor whiteColor] set];
        [path fill];

        path = [NSBezierPath bezierPath];
        [path appendBezierPathWithArcWithCenter:insertionPoint radius:2.5 startAngle:0 endAngle:360];
        [path setLineWidth:1.5];
        [[NSColor blackColor] set];
        [path stroke];
        
        path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(insertionPoint.x + 2, insertionPoint.y)];
        [path relativeLineToPoint:NSMakePoint(NSMaxX(rowFrame), 0)];
        [path setLineWidth:2.0];
        [path stroke];
    }
}

// NSControl

- (void)mouseDown:(NSEvent *)event;
{
    NSPoint eventLocationInWindow, eventLocation;
    int columnIndex, rowIndex;
    NSRect slopRect;
    const int dragSlop = 4;
    NSEvent *mouseDragCurrentEvent;

    // How do we keep from changing the selection on the first click of a double-click, so that you can double-click a multiple selection? Filed as Apple bug #2774089.
    
    if (![_dataSource respondsToSelector:@selector(outlineView:copyItems:toPasteboard:)]) {
        [super mouseDown:event];
        return;
    }

    eventLocationInWindow = [event locationInWindow];
    eventLocation = [self convertPoint:eventLocationInWindow fromView:nil];
    columnIndex = [self columnAtPoint:eventLocation];
    rowIndex = [self rowAtPoint:eventLocation];
    if (rowIndex == -1 || columnIndex == -1) {
        [super mouseDown:event];
        return;
    }

    // Did user click on disclose triangle?
    if ([[self tableColumns] objectAtIndex:columnIndex] == [self outlineTableColumn]) {
        NSRect cellRect;
        
        cellRect = [self frameOfCellAtColumn:columnIndex row:rowIndex];
        if (eventLocation.x < NSMinX(cellRect)) {
            [super mouseDown:event];
            return;
        }
    }

    // Is user starting a drag?
    slopRect = NSInsetRect(NSMakeRect(eventLocationInWindow.x, eventLocationInWindow.y, 0.0, 0.0), -dragSlop, -dragSlop);
    while (1) {
        NSEvent *nextEvent;

        nextEvent = [NSApp nextEventMatchingMask:NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];
        mouseDragCurrentEvent = nextEvent;

        if ([nextEvent type] == NSLeftMouseUp) {
            break;
        } else {
            [NSApp nextEventMatchingMask:NSLeftMouseDraggedMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
            if (!NSMouseInRect([nextEvent locationInWindow], slopRect, NO)) {
                [self startDrag:event];
                return;
            }
        }
    }
    
    // Handle non-drag clicks...
    if ([event clickCount] >= 3) { // Workaround for bug in Public Beta where triple-click aborts double-click's edit session
        NSTableColumn *column;
        id item;

        column = [[self tableColumns] objectAtIndex:columnIndex];
        item = [self itemAtRow:rowIndex];
        if ([column isEditable])
            [self editColumn:columnIndex row:rowIndex withEvent:nil select:YES];

        return;
    }
    
    // Is user doing a second single-click on an item? As opposed to a double-click, a second single-click requires a pause between clicks, so you can start editing on items which normally fire an action on double-click.
    if ([event clickCount] == 1 && [self numberOfSelectedRows] == 1 && [self isRowSelected:rowIndex]) {
        NSTableColumn *column;
        id item;

        column = [[self tableColumns] objectAtIndex:columnIndex];
        item = [self itemAtRow:rowIndex];
        // NOTE: We do NOT check to see if the column isEditable, because the programmer has normally set this to NO so that double-click will call an action.  We instead let the client return YES or NO based on the -outlineView:shouldEdit... delegate method.
        if ([self _delegateAllowsEditTableColumn:column item:item]) {
            [self editColumn:columnIndex row:rowIndex withEvent:event select:YES];
            return;
        }
    }

    // Handle normal clicks, then
    [super mouseDown:event];
}

// NSTableView

- (void)setDataSource:(id)aSource;
{
    [super setDataSource:aSource];
    
    [self registerForDragging];
}

- (void)textDidEndEditing:(NSNotification *)notification;
{
    if (flags.shouldEditNextItemWhenEditingEnds == NO) {
        // This is ugly, but just about the only way to do it. NSTableView is determined to select and edit something else, even the text field that it just finished editing, unless we mislead it about what key was pressed to end editing.
        NSMutableDictionary *newUserInfo;
        NSNotification *newNotification;
        
        newUserInfo = [NSMutableDictionary dictionaryWithDictionary:[notification userInfo]];
        [newUserInfo setObject:[NSNumber numberWithInt:0] forKey:@"NSTextMovement"];
        newNotification = [NSNotification notificationWithName:[notification name] object:[notification object] userInfo:newUserInfo];
        [super textDidEndEditing:newNotification];

        // For some reason we lose firstResponder status when when we do the above.
        [[self window] makeFirstResponder:self];
    } else {
        [super textDidEndEditing:notification];
    }
}

- (void)reloadData;
{
    [super reloadData];
    [self updateAutoExpandedItems];
    [typeAheadHelper rebuildTypeAheadSearchCache];
}

- (void)noteNumberOfRowsChanged;
{
    [super noteNumberOfRowsChanged];
    [self updateAutoExpandedItems];
    [typeAheadHelper rebuildTypeAheadSearchCache];
}


//

@class OATextWithIconCell;

- (void)editColumn:(NSInteger)columnIndex row:(NSInteger)rowIndex withEvent:(NSEvent *)theEvent select:(BOOL)select;
{
    NSTableColumn *tableColumn;
    id item;
    id dataCell;

    tableColumn = [[self tableColumns] objectAtIndex:columnIndex];
    item = [self itemAtRow:rowIndex];
    if (item == nil || ![self _delegateAllowsEditTableColumn:tableColumn item:item]) {
        NSBeep();
        return;
    }

    [super editColumn:columnIndex row:rowIndex withEvent:theEvent select:select];
    
    dataCell = [tableColumn dataCellForRow:rowIndex];
    if ([dataCell respondsToSelector:@selector(modifyFieldEditor:forOutlineView:column:row:)]) {
        NSResponder *firstResponder;

        firstResponder = [[self window] firstResponder]; // This should be the field editor
        if ([firstResponder isKindOfClass:[NSText class]]) // ...but let's just double-check
            [dataCell modifyFieldEditor:(NSText *)firstResponder forOutlineView:self column:columnIndex row:rowIndex];
    }
}


//
// NSOutlineView
//

- (void)reloadItem:(id)item reloadChildren:(BOOL)reloadChildren;
{
    [super reloadItem:item reloadChildren:reloadChildren];
    [self updateAutoExpandedItems];
}


// NSOutlineView notifications
- (void)outlineViewItemDidExpand:(NSNotification *)notification;
{
    [typeAheadHelper rebuildTypeAheadSearchCache];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification;
{
    [typeAheadHelper rebuildTypeAheadSearchCache];
}


//
// NSDraggingDestination
//

- (unsigned int)draggingEntered:(id <NSDraggingInfo>)sender;
{
    flags.isDraggingDestination = YES;
    dragDestinationRow = NSNotFound;
    return [self draggingUpdated:sender];
}

- (unsigned int)draggingUpdated:(id <NSDraggingInfo>)sender;
{
    NSPoint draggedImageLocation;
    int requestedRow;
    int maximumLevel, minimumLevel, requestedLevel;
    BOOL allowDrag;
    
    draggedImageLocation = [self convertPoint:[sender draggedImageLocation] fromView:nil];
    draggedImageLocation.x -= DISCLOSURE_TRIANGLE_WIDTH + NSMinX([self rectOfColumn:[[self tableColumns] indexOfObject:[self outlineTableColumn]]]);

    // Figure out the row at which this drag would drop
    requestedRow = [self rowAtPoint:draggedImageLocation];
    if (requestedRow == -1)
        requestedRow = [self numberOfRows];
    
    // Figure out the indention level at which this drag would drop
    if (requestedRow == 0) {
        requestedLevel = 0;
        minimumLevel = 0;
    } else {
        maximumLevel = [self levelForRow:requestedRow - 1] + 1;
        
        if (flags.isDraggingSource && [self isRowSelected:requestedRow]) {
            if (requestedRow >= [self numberOfRows] - 1)
                minimumLevel = 0;
            else
                minimumLevel = MAX([self levelForRow:requestedRow + 1], 0);
        } else {
            if (requestedRow == [self numberOfRows])
                minimumLevel = 0;
            else
                minimumLevel = MAX([self levelForRow:requestedRow], 0);
        }
        requestedLevel = MAX(MIN(rint((draggedImageLocation.x - [self rowOffset:requestedRow]) / [self indentationPerLevel]), maximumLevel), minimumLevel);
    }
    
    // Can't drag to be a child of any selected item if we are the source (you can't put something inside itself)
    if (flags.isDraggingSource && requestedRow != 0) {
        int checkRow;
        int checkLevel;
        
        checkRow = requestedRow - 1;
        checkLevel = requestedLevel;
        while (checkRow && checkLevel >= 0) {
            if ([self levelForRow:checkRow] <= checkLevel) {
                if ([self isRowSelected:checkRow]) {
                    requestedLevel = checkLevel;
                    if (requestedLevel < minimumLevel) {
                        flags.isDraggingDestinationAcceptable = NO;
                        [self setNeedsDisplay:YES];
                        return NSDragOperationNone;
                    }
                }
                checkLevel--;
            } else
                checkRow--;
        }
    }
    
    // Give the dataSource a chance to change or deny which indention level we'll drop to.
    do {
        id parentItem;
        unsigned int childIndex;
        
        // Is it OK to drop where we are right now?
        parentItem = [self parentItemForRow:requestedRow indentLevel:requestedLevel child:&childIndex];
        allowDrag = [_dataSource outlineView:self allowPasteItemsFromPasteboard:[sender draggingPasteboard] parentItem:parentItem child:childIndex];

        if (!allowDrag) {
            int normalDestinationLevel;
            
            normalDestinationLevel = [self levelForRow:requestedRow];
            if (requestedLevel == normalDestinationLevel) {
                flags.isDraggingDestinationAcceptable = NO;
                [self setNeedsDisplay:YES];
                return NSDragOperationNone;
            }
            requestedLevel = normalDestinationLevel;
        }
    } while (!allowDrag);
    
    // The drag is allowable (collapse drawing so we don't flicker if we've already this state)!
    if (requestedRow != dragDestinationRow || requestedLevel != dragDestinationLevel) {
        dragDestinationLevel = requestedLevel;
        dragDestinationRow = requestedRow;
        flags.isDraggingDestinationAcceptable = YES;    
        [self setNeedsDisplay:YES];
    }
    
    if (flags.isDraggingDestinationAcceptable)
        return [sender draggingSourceOperationMask];
    else
        return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender;
{
    flags.isDraggingDestination = NO;
    [self setNeedsDisplay:YES];
}

//- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
{
    id parentItem;
    unsigned int childIndex;
    NSArray *newItems;
    
    if (!flags.isDraggingDestinationAcceptable)
        return NO;

    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] beginUndoGrouping];

    // If we are the drag source, we paste the item in the new position and later delete it in the old position. We don't want the intermediate step to be displayed, so we turn off the window updating until we're finished.
    if (flags.isDraggingSource)
        [[self window] setAutodisplay:NO];
        
    parentItem = [self parentItemForRow:dragDestinationRow indentLevel:dragDestinationLevel child:&childIndex];
    newItems = [_dataSource outlineView:self pasteItemsFromPasteboard:[sender draggingPasteboard] parentItem:parentItem child:childIndex];
    [self reloadData];
    if (flags.isDraggingSource)
        [self setSelectedItems:newItems]; 
    
    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)]) {
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Drag Operation", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for drag operations in outline view")];
        [[_dataSource undoManagerForOutlineView:self] endUndoGrouping];
    }

    flags.justAcceptedDrag = YES;
    return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;
{
    flags.isDraggingDestination = NO;
    if (flags.isDraggingSource) {
        // We're the source of the drag:  we'll draw ourselves after we delete the source items.
    } else {
        [self setNeedsDisplay:YES];
    }
}


// NSDraggingSource

- (unsigned int)draggingSourceOperationMaskForLocal:(BOOL)isLocal;
{
    if (isLocal)
        return NSDragOperationGeneric;
    else
        return NSDragOperationCopy;
}

//- (void)draggedImage:(NSImage *)image beganAt:(NSPoint)screenPoint;
//- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation;
//- (BOOL)ignoreModifierKeysWhileDragging;

//
// Informal OmniFindControllerAware protocol
//

- (id <OAFindControllerTarget>)omniFindControllerTarget;
{
    if (![_dataSource respondsToSelector:@selector(outlineView:item:matchesPattern:)])
        return nil;
    return self;
}

//
// OAFindControllerTarget protocol
//

- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards wrap:(BOOL)wrap;
{
    NSArray *selectedItems, *path;
    id item;
    OAOutlineViewEnumerator *outlineEnum;
    BOOL hasWrapped = NO;
    
    // Start at the first selected item, if any.  If not, start at the first item, if any
    selectedItems = [self selectedItems];
    if ([selectedItems count])
        item = [selectedItems objectAtIndex:0];
    else {
        item = [self firstItem];
        if (!item)
            // Nothing to find...
            return NO;
    }

    outlineEnum = [[[OAOutlineViewEnumerator alloc] initWithOutlineView:self visibleItem:item] autorelease];
    // If we have a selected item, the enumerator will return it first, but we don't want to consider it in a find operation.
    if ([selectedItems count]) {
        if (backwards)
            [outlineEnum previousPath];
        else
            [outlineEnum nextPath];
    } else {
        // If we had nothing selected and we are going backwards, then set the enumerator to the end
        [outlineEnum resetToEnd];
    }
    
    while (YES) {
        if (backwards)
            path = [outlineEnum previousPath];
        else
            path = [outlineEnum nextPath];
            
        if (!path) {
            if (wrap && !hasWrapped) {
                hasWrapped = YES;
                if (backwards)
                    [outlineEnum resetToEnd];
                else
                    [outlineEnum resetToBeginning];
            } else {
                break;
            }
        }
        
        item = [path lastObject];
        
        if ([_dataSource outlineView:self item:item matchesPattern:pattern]) {
            NSMutableArray *ancestors;
            
            // Don't open the last item (the one that got found)
            ancestors = [[[NSMutableArray alloc] initWithArray:path] autorelease];
            OBASSERT([ancestors count]); // we found something, dammit
            [ancestors removeObjectAtIndex:[ancestors count] - 1];
            
            [self autoExpandItems:ancestors];
            [self setSelectedItem:item];
            [self scrollRowToVisible:[self rowForItem:item]];
            return YES;
        }
    }
    
    return NO;
}


// OATypeAheadSelectionDataSource

- (NSArray *)typeAheadSelectionItems;
{
    NSMutableArray *visibleItemLabels;
    int row;
    
    visibleItemLabels = [NSMutableArray arrayWithCapacity:[self numberOfRows]];
    for (row = 0; row < [self numberOfRows]; row++) {
        [visibleItemLabels addObject:[self _labelForRow:row]];
    }
    
    return [NSArray arrayWithArray:visibleItemLabels] ;
}

- (NSString *)currentlySelectedItem;
{
    if ([self numberOfSelectedRows] != 1)
        return nil;
    else
        return [self _labelForRow:[self selectedRow]];
}

- (void)typeAheadSelectItemAtIndex:(NSUInteger)itemIndex;
{
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:itemIndex] byExtendingSelection:NO];
    [self scrollRowToVisible:itemIndex];
}

@end

@implementation OAExtendedOutlineView (Private)

- (void)_initExtendedOutlineView;
{
    flags.shouldEditNextItemWhenEditingEnds = YES;
    [self setAllowsMultipleSelection:YES];
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DisableTypeAheadSelection"])
        [self setTypeAheadSelectionEnabled:YES];
}

- (void)startDrag:(NSEvent *)event;
{
    int outlineTableColumnIndex;
    NSRect rowFrame;
    double xOffsetOfFirstColumn;
    NSPoint eventLocation;
    NSPasteboard *pasteboard;
    NSArray *originalItems;
    id item;
    int dragSourceRow, dragSourceLevel;
    NSImage *dragImage = nil;
    NSRect bounds;
    NSPoint dragPoint;
    NSSize dragOffset;
    
    eventLocation = [self convertPoint:[event locationInWindow] fromView:nil];
    dragSourceRow = [self rowAtPoint:eventLocation];
    dragSourceLevel = [self levelForRow:dragSourceRow];

    item = [self itemAtRow:dragSourceRow];
    if (![self isRowSelected:dragSourceRow])
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:dragSourceRow] byExtendingSelection:NO];
    
    outlineTableColumnIndex = [[self tableColumns] indexOfObject:[self outlineTableColumn]];
    xOffsetOfFirstColumn = [self frameOfCellAtColumn:outlineTableColumnIndex row:dragSourceRow].origin.x;
    rowFrame = [self rectOfRow:dragSourceRow];

    originalItems = [self selectedItemsWithoutSelectedParents];
    
    if ([_dataSource respondsToSelector:@selector(outlineView:dragImageForItem:)])
        dragImage = [[_dataSource outlineView:self dragImageForItem:item] retain];
    
    if (dragImage == nil) 
        dragImage = [self _dragImageForItems:originalItems];
        
    // Let's start the drag.
    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)])
        [[_dataSource undoManagerForOutlineView:self] beginUndoGrouping];
        

    flags.isDraggingSource = YES;
    flags.justAcceptedDrag = NO;
    pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];

    [_dataSource outlineView:self copyItems:originalItems toPasteboard:pasteboard];
    
    bounds = [self bounds];
    dragPoint = NSMakePoint(NSMinX(bounds), NSMaxY(bounds));
    dragOffset.width = dragPoint.x + eventLocation.x;
    dragOffset.height = dragPoint.y - eventLocation.y;
    [self dragImage:dragImage at:dragPoint offset:dragOffset event:event pasteboard:pasteboard source:self slideBack:YES];
    [self setNeedsDisplay:YES];

    [dragImage release];
    
    // Only delete if the drag was accepted in THIS outlineView
    if (flags.justAcceptedDrag) {
        NSArray *selectedItems;

        selectedItems = [self selectedItems];
        [_dataSource outlineView:self deleteItems:originalItems];
        [self reloadData];
        [self setSelectedItems:selectedItems];

        // NOW we can display again.
        [[self window] setAutodisplay:YES];
        [self setNeedsDisplay:YES];
    }
                
    if ([_dataSource respondsToSelector:@selector(undoManagerForOutlineView:)]) {
        [[_dataSource undoManagerForOutlineView:self] setActionName:NSLocalizedStringFromTableInBundle(@"Drag Operation", @"OmniAppKit", [OAExtendedOutlineView bundle], "undo action name for drag operations in outline view")];
        [[_dataSource undoManagerForOutlineView:self] endUndoGrouping];
    }

    flags.justAcceptedDrag = NO;
    flags.isDraggingSource = NO;
}

- (NSImage *)_dragImageForItems:(NSArray *)dragItems;
{
    NSImage *dragImage;
    NSEnumerator *enumerator;
    id item;
    NSCachedImageRep *cachedImageRep;
    NSView *contentView;
    
    cachedImageRep = [[NSCachedImageRep alloc] initWithSize:[self bounds].size depth:[[NSScreen mainScreen] depth] separate:YES alpha:YES];
    contentView = [[cachedImageRep window] contentView];

    [contentView lockFocus];
    enumerator = [dragItems objectEnumerator];
    while ((item = [enumerator nextObject])) {
        int row = [self rowForItem:item];
        BOOL shouldDrag = YES;
        
        if ([_dataSource respondsToSelector:@selector(outlineView:shouldShowDragImageForItem:)])
            shouldDrag = [_dataSource outlineView:self shouldShowDragImageForItem:item];
            
        if (shouldDrag) {
            NSTableColumn *outlineColumn;
            NSCell *cell;
            NSRect cellRect;
            id objectValue;
            NSInteger columnIndex;
            
            outlineColumn = [self outlineTableColumn];
            columnIndex = [[self tableColumns] indexOfObject:outlineColumn];
            objectValue = [_dataSource outlineView:self objectValueForTableColumn:outlineColumn byItem:item];

            cellRect = [self frameOfCellAtColumn:columnIndex row:row];
            cellRect.origin.y = NSMaxY([self bounds]) - NSMaxY(cellRect);
            cell = [outlineColumn dataCellForRow:row];
            
            [cell setCellAttribute:NSCellHighlighted to:0];
            [cell setObjectValue:objectValue];
            if ([cell respondsToSelector:@selector(setDrawsBackground:)])
                [(NSTextFieldCell *)cell setDrawsBackground:0];
            if ([_delegate respondsToSelector:@selector(outlineView:willDisplayCell:forTableColumn:item:)])
                [_delegate outlineView:self willDisplayCell:cell forTableColumn:outlineColumn item:item];
            [cell drawWithFrame:cellRect inView:contentView];
        }
    }
    [contentView unlockFocus];

    dragImage = [[NSImage alloc] init];
    [dragImage addRepresentation:cachedImageRep];
    [cachedImageRep release];
    
    return dragImage;
}

- (void)registerForDragging;
{
    if ([_dataSource respondsToSelector:@selector(outlineViewAcceptedPasteboardTypes:)])
        [self registerForDraggedTypes:[_dataSource outlineViewAcceptedPasteboardTypes:self]];
}

- (void)updateAutoExpandedItems;
{
    // If any of the autoExpandedItems are no longer in the outline view, then we assume that some significant editing has happened, and we can no longer trust that any of the items are still around. So, throw them all away.
    unsigned int itemIndex, itemCount;

    itemCount = [autoExpandedItems count];
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++)
    {
        if ([self rowForItem:[autoExpandedItems objectAtIndex:itemIndex]] == NSNotFound) {
            [autoExpandedItems release];
            autoExpandedItems = nil;
            break;
        }    
    }
}

- (NSArray *)selectedItemsWithoutSelectedParents;
{
    NSIndexSet *selection = [self selectedRowIndexes];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[selection count]];
    
    OFForEachIndex(selection, selectedRow) {
        NSInteger level = [self levelForRow:selectedRow];
        NSUInteger row;
        
        while (--level >= 0) {
            row = selectedRow;
            while (row--) {
                if ([self levelForRow:row] == level)
                    break;
            }
            if ([selection containsIndex:row])
                break;
        }
        if (level == -1)
            [result addObject:[self itemAtRow:selectedRow]];
    }
    return result;
}

- (BOOL)_delegateAllowsEditTableColumn:(NSTableColumn *)tableColumn item:(id)item;
{
    id delegate;
    
    delegate = [self delegate];
    if (![delegate respondsToSelector:@selector(outlineView:shouldEditTableColumn:item:)])
        return NO;
        
    return [delegate outlineView:self shouldEditTableColumn:tableColumn item:item];
}

- (NSString *)_labelForRow:(int)row;
{
    id cellValue;
    
    cellValue = [[self dataSource] outlineView:self objectValueForTableColumn:[self outlineTableColumn] byItem:[self itemAtRow:row]];
    if ([cellValue isKindOfClass:[NSString class]])
         return cellValue;
    else if ([cellValue respondsToSelector:@selector(stringValue)])
        return [cellValue stringValue];
    else
        [NSException raise:NSInternalInconsistencyException format:@"%@ is not a string and doesn't respond to -stringValue; this is required for type-ahead selection", cellValue];
        
    return nil; // not reached
}

@end
