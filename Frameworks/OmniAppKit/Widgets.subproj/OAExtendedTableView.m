// Copyright 2001-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAExtendedTableView.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@interface OAExtendedTableView (Private)
- (void)_initExtendedTableView;
@end

@implementation OAExtendedTableView

// Init and dealloc

- (id)initWithFrame:(NSRect)rect;
{
    if (![super initWithFrame:rect])
        return nil;

    [self _initExtendedTableView];
    
    return self;
}

- initWithCoder:(NSCoder *)coder;
{
    if (![super initWithCoder:coder])
        return nil;

    [self _initExtendedTableView];
        
    return self;
}

- (void)dealloc;
{
    [super dealloc];
}


// API

- (NSRange)columnRangeForDragImage;
{
    return _dragColumnRange;
}

- (void)setColumnRangeForDragImage:(NSRange)newRange;
{
    _dragColumnRange = newRange;
}

// NSTableView subclass

- (NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)dragRows tableColumns:(NSArray *)tableColumns event:(NSEvent *)dragEvent dragImageOffset:(NSPointPointer)dragImageOffset;
{
    NSImage *dragImage;
    unsigned int row;
    NSCachedImageRep *cachedImageRep;
    NSView *contentView;
    NSPoint dragPoint;
    
    cachedImageRep = [[NSCachedImageRep alloc] initWithSize:[self bounds].size depth:[[NSScreen mainScreen] depth] separate:YES alpha:YES];
    contentView = [[cachedImageRep window] contentView];
    
    [contentView lockFocus];
    for(row = [dragRows firstIndex]; row != NSNotFound; row = [dragRows indexGreaterThanIndex:row]) {
        BOOL shouldDrag = YES;
        
        if ([_dataSource respondsToSelector:@selector(tableView:shouldShowDragImageForRow:)])
            shouldDrag = [_dataSource tableView:self shouldShowDragImageForRow:row];
            
        if (shouldDrag) {
            int columnIndex, startColumn, endColumn;
            
            if (_dragColumnRange.length) {
                startColumn = _dragColumnRange.location;
                endColumn = _dragColumnRange.location + _dragColumnRange.length;
            } else {
                startColumn = 0;
                endColumn = [self numberOfColumns];
            }
            
            for (columnIndex = startColumn; columnIndex < endColumn; columnIndex++) {
                NSTableColumn *tableColumn;
                NSCell *cell;
                NSRect cellRect;
                id objectValue;
                
                tableColumn = [[self tableColumns] objectAtIndex:columnIndex];
                objectValue = [_dataSource tableView:self objectValueForTableColumn:tableColumn row:row];
    
                cellRect = [self frameOfCellAtColumn:columnIndex row:row];
                cellRect.origin.y = NSMaxY([self bounds]) - NSMaxY(cellRect);
                cell = [tableColumn dataCellForRow:row];
                
                [cell setCellAttribute:NSCellHighlighted to:0];
                [cell setObjectValue:objectValue];
                if ([cell respondsToSelector:@selector(setDrawsBackground:)])
                    [(NSTextFieldCell *)cell setDrawsBackground:0];
                [cell drawWithFrame:cellRect inView:contentView];
            }
        }
    }
    [contentView unlockFocus];
    
    dragPoint = [self convertPoint:[dragEvent locationInWindow] fromView:nil];
    dragImageOffset->x = NSMidX([self bounds]) - dragPoint.x;
    dragImageOffset->y = dragPoint.y - NSMidY([self bounds]);

    dragImage = [[NSImage alloc] init];
    [dragImage addRepresentation:cachedImageRep];
    [cachedImageRep release];
    
    return dragImage;
}

- (void)editColumn:(int)column row:(int)row withEvent:(NSEvent *)theEvent select:(BOOL)select;
{
    NSTableColumn *tableColumn;
    id dataCell;

    [super editColumn:column row:row withEvent:theEvent select:select];
    
    tableColumn = [[self tableColumns] objectAtIndex:column];
    dataCell = [tableColumn dataCellForRow:row];
    if ([dataCell respondsToSelector:@selector(modifyFieldEditor:forTableView:column:row:)]) {
        NSResponder *firstResponder;

        firstResponder = [[self window] firstResponder]; // This should be the field editor
        if ([firstResponder isKindOfClass:[NSText class]]) // ...but let's just double-check
            [dataCell modifyFieldEditor:(NSText *)firstResponder forTableView:self column:column row:row];
    }
}

@end

@implementation OAExtendedTableView (Private)

- (void)_initExtendedTableView;
{
    _dragColumnRange = NSMakeRange(0, 0);
}

@end
