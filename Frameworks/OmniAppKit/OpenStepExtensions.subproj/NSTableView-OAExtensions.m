// Copyright 1997-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSTableView-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSOutlineView-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>

OBDEPRECATED_METHOD(-tableView:deleteRows:); // Use -tableView:deleteRowsAtIndexes:
OBDEPRECATED_METHOD(-tableView:writeRows:toPasteboard:); // deprecated by the OS, but let's warn if anyone implements it.  Use the indexes version.
OBDEPRECATED_METHOD(-tableViewTypeAheadSelectionColumn:); // NSTableView automagically has this is 10.5 and later (see any number of type select delegate methods in the NSTableView header)

NS_ASSUME_NONNULL_BEGIN

void OATableViewSetFullWidthStyle(NSTableView *tableView)
{
    if (@available(macOS 11.0, *)) {
        tableView.style = NSTableViewStyleFullWidth;
    }
}

@interface NSTableView (OAExtensionsPrivate)
- (BOOL)_canCopyToPasteboard;
- (BOOL)_copyToPasteboard:(NSPasteboard *)pasteboard;
- (BOOL)_canPasteFromPasteboard;
- (void)_pasteFromPasteboard:(NSPasteboard *)pasteboard;
@end

@interface NSTableView (OATableDelegateDataSourceCoverMethods)
- (BOOL)_dataSourceHandlesPaste;
- (BOOL)_dataSourceHandlesContextMenu;
- (NSMenu *)_contextMenuForRow:(NSInteger)row column:(NSInteger)column;
- (BOOL)_shouldShowDragImageForRow:(NSInteger)row;
- (nullable NSArray *)_columnIdentifiersForDragImage;
- (BOOL)_shouldEditNextItemWhenEditingEnds;
@end

@implementation NSTableView (OAExtensions)

static void (*originalTextDidEndEditing)(NSTableView *self, SEL _cmd, NSNotification *note);
static NSImage *(*originalDragImageForRows)(NSTableView *self, SEL _cmd, NSIndexSet *dragRows, NSArray *tableColumns, NSEvent *dragEvent, NSPointPointer dragImageOffset);

static NSIndexSet * _Nullable OATableViewRowsInCurrentDrag = nil;
// you'd think this should be instance-specific, but it doesn't have to be -- only one drag can be happening at a time.


OBDidLoad(^{
    Class self = [NSTableView class];
    originalTextDidEndEditing = (typeof(originalTextDidEndEditing))OBReplaceMethodImplementationWithSelector(self, @selector(textDidEndEditing:), @selector(_replacementTextDidEndEditing:));
    
    originalDragImageForRows = (typeof(originalDragImageForRows))OBReplaceMethodImplementationWithSelector(self, @selector(dragImageForRowsWithIndexes:tableColumns:event:offset:), @selector(_replacement_dragImageForRowsWithIndexes:tableColumns:event:offset:));
});


// NSTableView method replacements

- (void)_replacementTextDidEndEditing:(NSNotification *)notification;
{
    int textMovement = [[[notification userInfo] objectForKey:@"NSTextMovement"] intValue];
    if ((textMovement == NSReturnTextMovement || textMovement == NSTabTextMovement) && ![self _shouldEditNextItemWhenEditingEnds]) {
        // This is ugly, but just about the only way to do it. NSTableView is determined to select and edit something else, even the text field that it just finished editing, unless we mislead it about what key was pressed to end editing.
        NSMutableDictionary *newUserInfo;
        NSNotification *newNotification;

        newUserInfo = [NSMutableDictionary dictionaryWithDictionary:[notification userInfo]];
        [newUserInfo setObject:[NSNumber numberWithInt:NSIllegalTextMovement] forKey:@"NSTextMovement"];
        newNotification = [NSNotification notificationWithName:[notification name] object:[notification object] userInfo:newUserInfo];
        originalTextDidEndEditing(self, _cmd, newNotification);

        // For some reason we lose firstResponder status when we do the above.
        [[self window] makeFirstResponder:self];
    } else {
        originalTextDidEndEditing(self, _cmd, notification);
    }
}

- (NSImage *)_replacement_dragImageForRowsWithIndexes:(NSIndexSet *)dragRows tableColumns:(NSArray *)tableColumns event:(NSEvent*)dragEvent offset:(NSPointPointer)dragImageOffset;
{
    OATableViewRowsInCurrentDrag = dragRows; // hang on to these so we can use them in -draggedImage:endedAt:operation:.

    if ([self _columnIdentifiersForDragImage] == nil)
        return originalDragImageForRows(self, _cmd, dragRows, tableColumns, dragEvent, dragImageOffset);
    
    NSImage *dragImage = [[NSImage alloc] initWithSize:[self bounds].size];

    [dragImage lockFocus];
    
    id <NSTableViewDataSource> dataSource = self.dataSource;
    OFForEachIndex(dragRows, row) {
        if ([self _shouldShowDragImageForRow:row]) {
            NSArray *dragColumnIdentifiers = [self _columnIdentifiersForDragImage];
            if (dragColumnIdentifiers == nil || [dragColumnIdentifiers count] == 0)
                dragColumnIdentifiers = [[self tableColumns] arrayByPerformingSelector:@selector(identifier)];

            for (NSString *columnIdentifier in dragColumnIdentifiers) {
                NSTableColumn *tableColumn;
                NSCell *cell;
                NSRect cellRect;
                id objectValue;

                tableColumn = [self tableColumnWithIdentifier:columnIdentifier];
                objectValue = [dataSource tableView:self objectValueForTableColumn:tableColumn row:row];

                cellRect = [self frameOfCellAtColumn:[[self tableColumns] indexOfObject:tableColumn] row:row];
                cellRect.origin.y = NSMaxY([self bounds]) - NSMaxY(cellRect);
                cell = [tableColumn dataCellForRow:row];

                [cell setCellAttribute:NSCellHighlighted to:0];
                [cell setObjectValue:objectValue];
                if ([cell respondsToSelector:@selector(setDrawsBackground:)])
                    [(NSTextFieldCell *)cell setDrawsBackground:0];

                // It isn't clear what the correct value for the view argument is here since we aren't drawing ourselves, but drawing into an image.
                // Really, though, the right solution might be to remove this override entirely.
                // <bug:///117839> (Unassigned: Fix disabled 'nonnull' warning in NSTableView(OAExtensions) row dragging override)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
                [cell drawWithFrame:cellRect inView:nil];
#pragma clang diagnostic pop
            }
        }
    }
    [dragImage unlockFocus];

    NSPoint dragPoint = [self convertPoint:[dragEvent locationInWindow] fromView:nil];
    dragImageOffset->x = NSMidX([self bounds]) - dragPoint.x;
    dragImageOffset->y = dragPoint.y - NSMidY([self bounds]);

    return dragImage;
}


// New API

- (NSRect)rectOfSelectedRows;
{
    NSRect rect = NSZeroRect;    
    OFForEachIndex([self selectedRowIndexes], rowIndex) {
	NSRect rowRect = [self rectOfRow: rowIndex];
	if (NSEqualRects(rect, NSZeroRect))
	    rect = rowRect;
	else
	    rect = NSUnionRect(rect, rowRect);
    }
    
    return rect;
}

- (void)scrollSelectedRowsToVisibility: (OATableViewRowVisibility)visibility;
{
    if (visibility == OATableViewRowVisibilityLeaveUnchanged)
        return;
    
    NSRect selectionRect = [self rectOfSelectedRows];
    if (NSEqualRects(selectionRect, NSZeroRect))
        return;
    
    if (visibility == OATableViewRowVisibilityScrollToVisible)
        [self scrollRectToVisible: selectionRect];
    else if (visibility == OATableViewRowVisibilityScrollToMiddleIfNotVisible) {
        NSRect visibleRect = [self visibleRect];
        if (NSContainsRect(visibleRect, selectionRect))
            return;
        
        CGFloat heightDifference = NSHeight(visibleRect) - NSHeight(selectionRect);
        if (heightDifference > 0) {
            // scroll to a rect equal in height to the visible rect but centered on the selected rect
            selectionRect = NSInsetRect(selectionRect, 0.0f, -(heightDifference / 2.0f));
        } else {
            // force the top of the selectionRect to the top of the view
            selectionRect.size.height = NSHeight(visibleRect);
        }
        [self scrollRectToVisible: selectionRect];
    }
}

- (nullable NSFont *)font;
{
    NSArray *tableColumns = [self tableColumns];
    if ([tableColumns count] > 0)
        return [[(NSTableColumn *)[tableColumns objectAtIndex:0] dataCell] font];
    else
        return nil;
}

- (void)setFont:(NSFont *)font;
{
    for (NSTableColumn *column in self.tableColumns) 
        [[column dataCell] setFont:font];
}


// NSResponder subclass

- (nullable NSMenu *)menuForEvent:(NSEvent *)event;
{
    if (![self _dataSourceHandlesContextMenu])
        return [super menuForEvent:event];
    
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger rowIndex = [self rowAtPoint:point];
    // Christiaan M. Hofman: fixed bug in following line
    NSInteger columnIndex = [self columnAtPoint:point]; 
    if (rowIndex >= 0 && columnIndex >= 0) {
        if (![self isRowSelected:rowIndex])
            [self selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
    }

    return [self _contextMenuForRow:rowIndex column:columnIndex];
}

- (void)moveUp:(nullable id)sender;
{
    NSUInteger firstSelectedRow = [[self selectedRowIndexes] firstIndex];
    if (firstSelectedRow == NSNotFound) { // If nothing was selected
        NSInteger numberOfRows = [self numberOfRows];
        if (numberOfRows > 0) // If there are rows in the table
            firstSelectedRow = numberOfRows - 1; // Select the last row
        else
            return; // There are no rows: do nothing
    } else if (firstSelectedRow > 0) {
        firstSelectedRow--;
    }

    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(tableView:shouldSelectRow:)])
        while (![delegate tableView:self shouldSelectRow:firstSelectedRow]) {
            if (firstSelectedRow == 0)
                return;	// If we never find a selectable row, don't do anything
            firstSelectedRow--;
        }
    
    // If the first row was selected, select only the first row.  This is consistent with the behavior of many Apple apps.
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:firstSelectedRow] byExtendingSelection:NO];
    [self scrollRowToVisible:firstSelectedRow];
}

- (void)moveDown:(nullable id)sender;
{
    NSUInteger lastSelectedRow = [[self selectedRowIndexes] lastIndex];
    
    NSUInteger numberOfRows = [self numberOfRows];
    if (lastSelectedRow == NSNotFound) {
        if (numberOfRows > 0) // If there are rows in the table
            lastSelectedRow = 0; // Select the first row
        else
            return; // There are no rows: do nothing
    } else if (lastSelectedRow < numberOfRows - 1) {
        ++lastSelectedRow;
    }
    
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(tableView:shouldSelectRow:)])
        while (![delegate tableView:self shouldSelectRow:lastSelectedRow])
            if (++lastSelectedRow > numberOfRows - 1)
                return;	// If we never find a selectable row, don't do anything
        
    // If the first row was selected, select only the first row.  This is consistent with the behavior of many Apple apps.
    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:lastSelectedRow] byExtendingSelection:NO];
    [self scrollRowToVisible:lastSelectedRow];
}

- (void)deleteForward:(nullable id)sender;
{
    id <OAExtendedTableViewDataSource> dataSource = (id)self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    if ([dataSource respondsToSelector:@selector(tableView:deleteRowsAtIndexes:)]) {
        NSInteger selectedRow = [self selectedRow]; // last selected row if there's a multiple selection -- that's ok.
        if (selectedRow == -1)
            return;

        NSInteger originalNumberOfRows = [self numberOfRows];
        [dataSource tableView:self deleteRowsAtIndexes:[self selectedRowIndexes]];
        [self reloadData];

        // Maintain an appropriate selection after deletions
        NSInteger numberOfRows = [self numberOfRows];
        selectedRow -= originalNumberOfRows - numberOfRows;
        selectedRow = MIN(selectedRow + 1, numberOfRows - 1);

        if (numberOfRows > 0)
            [self selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
    } else if ([delegate respondsToSelector:@selector(deleteForward:)]) {
        [(id)delegate deleteForward:sender];
    }
}

- (void)deleteBackward:(nullable id)sender;
{
    id <OAExtendedTableViewDataSource> dataSource = (id)self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    if ([dataSource respondsToSelector:@selector(tableView:deleteRowsAtIndexes:)]) {
        if ([self numberOfSelectedRows] == 0)
            return;

        // -selectedRow is last row of multiple selection, no good for trying to select the row before the selection.
        NSInteger selectedRow = [[self selectedRowIndexes] firstIndex];
        NSInteger originalNumberOfRows = [self numberOfRows];
        [dataSource tableView:self deleteRowsAtIndexes:[self selectedRowIndexes]];
        [self reloadData];
        NSInteger newNumberOfRows = [self numberOfRows];
        
        // Maintain an appropriate selection after deletions
        if (originalNumberOfRows != newNumberOfRows) {
            if (selectedRow == 0) {
                if ([delegate respondsToSelector:@selector(tableView:shouldSelectRow:)]) {
                    if ([delegate tableView:self shouldSelectRow:0])
                        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                    else
                        [self moveDown:nil];
                } else {
                    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
                }
            } else {
                // Don't try to go past the new # of rows
                selectedRow = MIN(selectedRow - 1, newNumberOfRows - 1);
                
                // Skip all unselectable rows if the delegate responds to -tableView:shouldSelectRow:
                if ([delegate respondsToSelector:@selector(tableView:shouldSelectRow:)]) {
                    while (selectedRow > 0 && ![delegate tableView:self shouldSelectRow:selectedRow])
                        selectedRow--;
                }
                
                // If nothing was selected, move down (so that the top row is selected)
                if (selectedRow < 0)
                    [self moveDown:nil];
                else
                    [self selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
            }
        }
    } else if ([delegate respondsToSelector:@selector(deleteBackward:)]) {
        [(id)delegate deleteBackward:sender];
    }
}

- (void)insertNewline:(nullable id)sender;
{
    id <OAExtendedTableViewDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:insertNewline:)])
        [dataSource tableView:self insertNewline:sender];
}

- (void)insertTab:(nullable id)sender;
{
    [[self window] selectNextKeyView:nil];
}

- (void)insertBacktab:(nullable id)sender;
{
    [[self window] selectPreviousKeyView:nil];
}

// NSResponder subclass

- (void)scrollPageDown:(nullable id)sender
{
    [self scrollDownByPages:1.0f];
}

- (void)scrollPageUp:(nullable id)sender
{
    [self scrollDownByPages:-1.0f];
}

- (void)scrollLineDown:(nullable id)sender
{
    [self scrollDownByLines:1.0f];
}

- (void)scrollLineUp:(nullable id)sender
{
    [self scrollDownByLines:-1.0f];
}

- (void)scrollToBeginningOfDocument:(nullable id)sender
{
    [self scrollToTop];
}

- (void)scrollToEndOfDocument:(nullable id)sender
{
    [self scrollToEnd];
}

// Actions

- (IBAction)delete:(nullable id)sender;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    
    if ([dataSource respondsToSelector:@selector(delete:)])
        [(id)dataSource delete:sender];
    else if ([delegate respondsToSelector:@selector(delete:)])
        [(id)delegate delete:sender];
    else
        [self deleteBackward:sender];
}

- (IBAction)cut:(nullable id)sender;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    if ([dataSource respondsToSelector:@selector(cut:)]) {
        [(id)dataSource cut:sender];
    } else if ([delegate respondsToSelector:@selector(cut:)]) {
        [(id)delegate cut:sender];
    } else {
        if ([self _copyToPasteboard:[NSPasteboard generalPasteboard]]) {
            [self delete:sender];
        } else {
            NSBeep(); // Give feedback that this operation failed
        }
    }
}

- (IBAction)copy:(nullable id)sender;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    
    if ([dataSource respondsToSelector:@selector(copy:)]) {
        [(id)dataSource copy:sender];
    } else if ([delegate respondsToSelector:@selector(copy:)]) {
        [(id)delegate copy:sender];
    } else {
        if (![self _copyToPasteboard:[NSPasteboard generalPasteboard]]) {
            NSBeep(); // Give feedback that this operation failed
        }
    }
}

- (IBAction)paste:(nullable id)sender;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    
    if ([dataSource respondsToSelector:@selector(paste:)]) {
        [(id)dataSource paste:sender];
    } else if ([delegate respondsToSelector:@selector(paste:)]) {
        [(id)delegate paste:sender];
    } else {
        if ([self _dataSourceHandlesPaste])
            [self _pasteFromPasteboard:[NSPasteboard generalPasteboard]];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    BOOL (^delegatesActionForMenuItem)(NSMenuItem *item) = ^BOOL(NSMenuItem *menuItem) {
        SEL action = menuItem.action;
        
        if ([self.dataSource respondsToSelector:action]) {
            return YES;
        }

        if ([self.delegate respondsToSelector:action]) {
            return YES;
        }
        
        return NO;
    };

    BOOL (^validateMenuItem)(NSMenuItem *item) = ^BOOL(NSMenuItem *menuItem) {
        SEL action = menuItem.action;
        id<NSTableViewDataSource> dataSource = self.dataSource;
        id<NSTableViewDelegate> delegate = self.delegate;

        if ([dataSource respondsToSelector:action]) {
            if ([dataSource respondsToSelector:@selector(validateMenuItem:)]) {
                return [(id)dataSource validateMenuItem:menuItem];
            } else {
                return YES;
            }
        }
        
        if ([delegate respondsToSelector:action] && [delegate respondsToSelector:@selector(validateMenuItem:)]) {
            if ([dataSource respondsToSelector:@selector(validateMenuItem:)]) {
                return [(id)delegate validateMenuItem:menuItem];
            } else {
                return YES;
            }
        }
        
        OBASSERT_NOT_REACHED("Unreachable.");
        return NO;
    };
    
    BOOL hasSelection = self.numberOfSelectedRows > 0;

    if (item.action == @selector(cut:)) {
        if (delegatesActionForMenuItem(item)) {
            return hasSelection && validateMenuItem(item);
        } else {
            return hasSelection;
        }
    }

    if (item.action == @selector(copy:)) {
        if (delegatesActionForMenuItem(item)) {
            return hasSelection && validateMenuItem(item);
        } else {
            return hasSelection && [self _canCopyToPasteboard];
        }
    }

    if (item.action == @selector(paste:)) {
        if (delegatesActionForMenuItem(item)) {
            return validateMenuItem(item);
        } else {
            return [self _canPasteFromPasteboard];
        }
    }

    if (item.action == @selector(duplicate:) && delegatesActionForMenuItem(item)) {
        return hasSelection && validateMenuItem(item);
    }

    if (item.action == @selector(delete:) && delegatesActionForMenuItem(item)) {
        return hasSelection && validateMenuItem(item);
    }

    return [super validateMenuItem:item];
}

- (IBAction)duplicate:(nullable id)sender; // duplicate == copy + paste (but it doesn't use the general pasteboard)
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    id<NSTableViewDelegate> delegate = self.delegate;
    
    if ([dataSource respondsToSelector:@selector(duplicate:)]) {
        [(id)dataSource duplicate:sender];
    } else if ([delegate respondsToSelector:@selector(duplicate:)]) {
        [(id)delegate duplicate:sender];
    } else {
        NSPasteboard *tempPasteboard = [NSPasteboard pasteboardWithUniqueName];
        if ([self _copyToPasteboard:tempPasteboard] && [self _dataSourceHandlesPaste])
            [self _pasteFromPasteboard:tempPasteboard];
        
        [tempPasteboard clearContents];
        [tempPasteboard releaseGlobally]; // Otherwise, the unique named pasteboard will hang out forever.
    }
}


// NSDraggingSource

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation;
{
    // We get NSDragOperationDelete now for dragging to the Trash.
    if (operation == NSDragOperationDelete && OATableViewRowsInCurrentDrag != nil) {
        id<NSTableViewDataSource> dataSource = self.dataSource;
        if ([dataSource respondsToSelector:@selector(tableView:deleteRowsAtIndexes:)]) {
            [(id <OAExtendedTableViewDataSource>)dataSource tableView:self deleteRowsAtIndexes:OATableViewRowsInCurrentDrag];
            [self reloadData];
        }
    }
            
    OATableViewRowsInCurrentDrag = nil;
}


// Informal OmniFindControllerAware protocol

- (nullable id <OAFindControllerTarget>)omniFindControllerTarget;
{
    if (![self.dataSource respondsToSelector:@selector(tableView:itemAtRow:matchesPattern:)])
        return nil;
    return self;
}

// OAFindControllerTarget protocol

- (BOOL)findPattern:(id <OAFindPattern>)pattern backwards:(BOOL)backwards wrap:(BOOL)wrap;
{
    // Can't search an empty table
    if ([self numberOfRows] == 0)
        return NO;
    
    // Start at the first selected item, if any.  If not, start at the first item, if any
    NSInteger rowIndex;
    if ([self numberOfSelectedRows])
        rowIndex = [self selectedRow];
    else {
        if (backwards)
            rowIndex = [self numberOfRows] - 1;
        else
            rowIndex = 0;
    }
        
    id <OAExtendedTableViewDataSource> dataSource = (id)self.dataSource;
    BOOL hasWrapped = NO;
    while (YES) {
        if (rowIndex != [self selectedRow] && [dataSource tableView:self itemAtRow:rowIndex matchesPattern:pattern]) {
            [self selectRowIndexes:[NSIndexSet indexSetWithIndex:rowIndex] byExtendingSelection:NO];
            [self scrollRowToVisible:rowIndex];
            return YES;
        }

        if (backwards)
            rowIndex--;
        else
            rowIndex++;

        if (rowIndex < 0 || rowIndex >= [self numberOfRows]) {
            if (wrap && !hasWrapped) {
                hasWrapped = YES;
                if (backwards)
                    rowIndex = [self numberOfRows] - 1;
                else
                    rowIndex = 0;
            } else {
                break;
            }
        }
    }
    
    return NO;
}

@end

@implementation NSTableView (OAExtensionsPrivate)

- (BOOL)_canCopyToPasteboard;
{
    if (self.numberOfSelectedRows == 0) {
        return NO;
    }

    if ([self isKindOfClass:[NSOutlineView class]]) {
        NSOutlineView *outlineView = (id)self;
        id <NSOutlineViewDataSource> dataSource = outlineView.dataSource;
        if ([dataSource respondsToSelector:@selector(outlineView:pasteboardWriterForItem:)]) {
            return YES;
        }
        if ([dataSource respondsToSelector:@selector(outlineView:writeItems:toPasteboard:)]) {
            return YES;
        }
    } else {
        id <NSTableViewDataSource> dataSource = self.dataSource;
        if ([dataSource respondsToSelector:@selector(tableView:pasteboardWriterForRow:)]) {
            return YES;
        }
        if ([dataSource respondsToSelector:@selector(tableView:writeRowsWithIndexes:toPasteboard:)]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)_copyToPasteboard:(NSPasteboard *)pasteboard;
{
    if ([self isKindOfClass:[NSOutlineView class]]) {
        NSOutlineView *outlineView = (id)self;
        id <NSOutlineViewDataSource> dataSource = outlineView.dataSource;
        if (self.numberOfSelectedRows == 0) {
            return NO;
        }
        if ([dataSource respondsToSelector:@selector(outlineView:pasteboardWriterForItem:)]) {
            NSMutableArray *items = [NSMutableArray array];
            [[outlineView selectedItems] enumerateObjectsUsingBlock:^(id item, NSUInteger idx, BOOL * _Nonnull stop) {
                id <NSPasteboardWriting> writing = [dataSource outlineView:outlineView pasteboardWriterForItem:item];
                if (writing) {
                    [items addObject:writing];
                }
            }];
            if ([items count] == 0) {
                return NO;
            }
            [pasteboard prepareForNewContentsWithOptions:0];
            return [pasteboard writeObjects:items];
        }
        if ([dataSource respondsToSelector:@selector(outlineView:writeItems:toPasteboard:)]) {
            return [dataSource outlineView:outlineView writeItems:[outlineView selectedItems] toPasteboard:pasteboard];
        }
        return NO;
    } else {
        id <NSTableViewDataSource> dataSource = self.dataSource;
        if (self.numberOfSelectedRows == 0) {
            return NO;
        }
        if ([dataSource respondsToSelector:@selector(tableView:pasteboardWriterForRow:)]) {
            NSMutableArray *items = [NSMutableArray array];
            [[self selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger row, BOOL * _Nonnull stop) {
                id <NSPasteboardWriting> writing = [dataSource tableView:self pasteboardWriterForRow:row];
                if (writing) {
                    [items addObject:writing];
                }
            }];
            if ([items count] == 0) {
                return NO;
            }
            [pasteboard prepareForNewContentsWithOptions:0];
            return [pasteboard writeObjects:items];
        }
        if ([dataSource respondsToSelector:@selector(tableView:writeRowsWithIndexes:toPasteboard:)]) {
            return [dataSource tableView:self writeRowsWithIndexes:[self selectedRowIndexes] toPasteboard:pasteboard];
        }
        return NO;
    }
}

- (BOOL)_canPasteFromPasteboard;
{
    id <OAExtendedTableViewDataSource> dataSource = (id)self.dataSource;
    return [dataSource respondsToSelector:@selector(tableView:addItemsFromPasteboard:)];
}

- (void)_pasteFromPasteboard:(NSPasteboard *)pasteboard;
{
    id <OAExtendedTableViewDataSource> dataSource = (id)self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:addItemsFromPasteboard:)]) {
        [dataSource tableView:self addItemsFromPasteboard:pasteboard];
    }
}

@end

@implementation NSTableView (OATableDelegateDataSourceCoverMethods)

- (BOOL)_dataSourceHandlesPaste;
{
    // This is an override point so that OutlineView can get our implementation for free but provide item-based datasource API
    return [self.dataSource respondsToSelector:@selector(tableView:addItemsFromPasteboard:)];
}

- (BOOL)_dataSourceHandlesContextMenu;
{
    // This is an override point so that OutlineView can get our implementation for free but provide item-based datasource API
    return [self.dataSource respondsToSelector:@selector(tableView:contextMenuForRow:column:)];
}

- (NSMenu *)_contextMenuForRow:(NSInteger)row column:(NSInteger)column;
{
    // This is an override point so that OutlineView can get our implementation for free but provide item-based datasource API
    OBASSERT([self _dataSourceHandlesContextMenu]); // should already know this by the time we get here
    return [(id <OAExtendedTableViewDataSource>)self.dataSource tableView:self contextMenuForRow:row column:column];
}

- (BOOL)_shouldShowDragImageForRow:(NSInteger)row;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableView:shouldShowDragImageForRow:)])
        return [(id <OAExtendedTableViewDataSource>)dataSource tableView:self shouldShowDragImageForRow:row];
    else
        return YES;
}

- (nullable NSArray *)_columnIdentifiersForDragImage;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableViewColumnIdentifiersForDragImage:)]) {
        NSArray *identifiers = [(id <OAExtendedTableViewDataSource>)dataSource tableViewColumnIdentifiersForDragImage:self];
        if ([identifiers count] < 1)
            [NSException raise:NSInvalidArgumentException format:@"-tableViewColumnIdentifiersForDragImage: must return at least one valid column identifier"];
        else
            return identifiers;
    }

    return nil; 
}

- (BOOL)_shouldEditNextItemWhenEditingEnds;
{
    id<NSTableViewDataSource> dataSource = self.dataSource;
    if ([dataSource respondsToSelector:@selector(tableViewShouldEditNextItemWhenEditingEnds:)])
        return [(id <OAExtendedTableViewDataSource>)dataSource tableViewShouldEditNextItemWhenEditingEnds:self];
    else
        return YES;
}


@end

NS_ASSUME_NONNULL_END
