// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAGridView.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

// This puts views in rows and columns, and makes sure they all have the same size.  You can set the left, right, top and bottom margins, and the interrow and intercolumn spacing.

@implementation OAGridView

static NSView *_emptyView = nil;

+ (void)initialize;
{
    OBINITIALIZE;

    _emptyView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
}

- initWithFrame:(NSRect)frameRect;
{
    if ([super initWithFrame:frameRect] == nil)
        return nil;

    interColumnSpace = 5;
    interRowSpace = 5;

    rows = [[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc;
{
    [backgroundColor release];
    [rows release];
    [super dealloc];
}

//
// Accessors
//

- (int)rowCount;
{
    return rowCount;
}

- (void)setRowCount:(int)newRowCount;
{
    NSMutableArray *rowViews;
    int row, column;

    OBASSERT(newRowCount >= 0);

    if (newRowCount > rowCount) {
        for (row = rowCount; row < newRowCount; row++) {
            rowViews = [[NSMutableArray alloc] init];
            for (column = 0; column < columnCount; column++) {
                [rowViews addObject:_emptyView];
            }
            [rows addObject:rowViews];
            [rowViews release];
        }

        rowCount = newRowCount;
        [self tile];
    } else if (newRowCount < rowCount) {
        for (row = rowCount - 1; row >= newRowCount; row--) {
            rowViews = [rows objectAtIndex:row];
            for (column = 0; column < columnCount; column++)
                [[rowViews objectAtIndex:column] removeFromSuperview];
            [rows removeObject:rowViews];
        }

        rowCount = newRowCount;
        [self tile];
    }
}

- (int)columnCount;
{
    return columnCount;
}

- (void)setColumnCount:(int)newColumnCount;
{
    NSMutableArray *rowViews;
    int row, column;

    OBASSERT(newColumnCount >= 0);

    if (newColumnCount > columnCount) {
        for (row = 0; row < rowCount; row++) {
            rowViews = [rows objectAtIndex:row];
            for (column = columnCount; column < newColumnCount; column++) {
                [rowViews addObject:_emptyView];
            }
        }

        columnCount = newColumnCount;
        [self tile];
    } else if (newColumnCount < columnCount) {
        NSView *oldView;
        
        for (row = 0; row < rowCount; row++) {
            rowViews = [rows objectAtIndex:row];
            for (column = columnCount - 1; column >= newColumnCount; column--) {
                oldView = [rowViews objectAtIndex:column];
                [oldView removeFromSuperview];
                [rowViews removeObjectAtIndex:column];
            }
        }

        columnCount = newColumnCount;
        [self tile];
    }
}

- (float)interColumnSpace;
{
    return interColumnSpace;
}

- (void)setInterColumnSpace:(float)newInterColumnSpace;
{
    if (newInterColumnSpace == interColumnSpace)
        return;

    interColumnSpace = newInterColumnSpace;
    [self tile];
}

- (float)interRowSpace;
{
    return interRowSpace;
}

- (void)setInterRowSpace:(float)newInterRowSpace;
{
    if (newInterRowSpace == interRowSpace)
        return;

    interRowSpace = newInterRowSpace;
    [self tile];
}

- (float)leftMargin;
{
    return leftMargin;
}

- (void)setLeftMargin:(float)newLeftMargin;
{
    if (newLeftMargin == leftMargin)
        return;

    leftMargin = newLeftMargin;;
    [self tile];
}

- (float)rightMargin;
{
    return rightMargin;
}

- (void)setRightMargin:(float)newRightMargin;
{
    if (newRightMargin == rightMargin)
        return;

    rightMargin = newRightMargin;
    [self tile];
}

- (float)topMargin;
{
    return topMargin;
}

- (void)setTopMargin:(float)newTopMargin;
{
    if (newTopMargin == topMargin)
        return;

    topMargin = newTopMargin;
    [self tile];
}

- (float)bottomMargin;
{
    return bottomMargin;
}

- (void)setBottomMargin:(float)newBottomMargin;
{
    if (newBottomMargin == bottomMargin)
        return;

    bottomMargin = newBottomMargin;
    [self tile];
}

- (NSView *)viewAtRow:(int)row column:(int)column;
{
    NSArray *rowViews;
    NSView *aView;

    OBASSERT(row >= 0 && row < rowCount);
    OBASSERT(column >= 0 && column < columnCount);

    rowViews = [rows objectAtIndex:row];
    aView = [rowViews objectAtIndex:column];
    if (aView == _emptyView)
        aView = nil;

    return aView;
}

- (void)setView:(NSView *)newView atRow:(int)row column:(int)column;
{
    NSMutableArray *rowViews;
    NSView *oldView;

    OBASSERT(row >= 0 && row < rowCount);
    OBASSERT(column >= 0 && column < columnCount);

    if (newView == nil)
        newView = _emptyView;

    rowViews = [rows objectAtIndex:row];
    oldView = [rowViews objectAtIndex:column];
    [oldView removeFromSuperview];
    [rowViews replaceObjectAtIndex:column withObject:newView];
    if (newView != _emptyView) {
        [self addSubview:newView];
        [self tile];
    }
}

- (void)setView:(NSView *)aView relativeToView:(NSView *)referenceView atRow:(int)row column:(int)column;
{
    OBASSERT(aView != nil && referenceView != nil && [aView superview] != nil);
    
    if (aView == referenceView)
        [self setView:aView atRow:row column:column];
    else {
        NSView *targetView;
    
        targetView = aView;
        while ([targetView superview] != referenceView && [targetView superview] != nil)
            targetView = [targetView superview];

        if ([targetView superview] != referenceView)
            [NSException raise:NSInvalidArgumentException format:@"The provided reference view %@, must be a superview of the view being added to OAGridView: %@", referenceView, aView];
            
        [self setView:targetView atRow:row column:column];
    }
}

- (void)removeAllViews;
{
    NSMutableArray *rowViews;
    NSView *oldView;
    int row, column;

    for (row = 0; row < rowCount; row++) {
        rowViews = [rows objectAtIndex:row];

        for (column = 0; column < columnCount; column++) {
            oldView = [rowViews objectAtIndex:column];
            [oldView removeFromSuperview];
            [rowViews replaceObjectAtIndex:column withObject:_emptyView];
        }
    }
}

- (NSColor *)backgroundColor;
{
    return backgroundColor;
}

- (void)setBackgroundColor:(NSColor *)newBackgroundColor;
{
    if (newBackgroundColor == backgroundColor)
        return;

    [backgroundColor release];
    backgroundColor = [newBackgroundColor retain];
    [self setNeedsDisplay:YES];
}

//
// NSView methods
//

- (void)resizeSubviewsWithOldSize:(NSSize)oldFrameSize;
{
    [super resizeSubviewsWithOldSize:oldFrameSize];
    [self tile];
}

- (void)drawRect:(NSRect)rect;
{
    if (backgroundColor != nil) {
        [backgroundColor set];
        NSRectFill(rect);
    }
    
    [super drawRect:rect];
}

- (void)tile;
{
    NSRect boundsRect, otherRect;
    NSRect viewFrame;
    int row, column;
    NSArray *rowViews;
    NSView *aView;

    if (rowCount == 0 || columnCount == 0)
        return;

    boundsRect = NSIntegralRect([self bounds]);
    NSDivideRect (boundsRect, &otherRect, &boundsRect, leftMargin, NSMinXEdge);
    NSDivideRect (boundsRect, &otherRect, &boundsRect, rightMargin, NSMaxXEdge);
    NSDivideRect (boundsRect, &otherRect, &boundsRect, topMargin, NSMinYEdge);
    NSDivideRect (boundsRect, &otherRect, &boundsRect, bottomMargin, NSMaxYEdge);

    viewFrame.size.width = floor(floor(boundsRect.size.width - (columnCount - 1) * interColumnSpace) / columnCount);
    viewFrame.size.height = floor(floor(boundsRect.size.height - (rowCount - 1) * interRowSpace) / rowCount);

    for (row = 0; row < rowCount; row++) {
        // It looks better to have the upper edge stable
        viewFrame.origin.y = NSMaxY(boundsRect) -  (rowCount - row) * (viewFrame.size.height + interRowSpace) + interRowSpace;
        rowViews = [rows objectAtIndex:row];
        for (column = 0; column < columnCount; column++) {
            viewFrame.origin.x = leftMargin + column * (viewFrame.size.width + interColumnSpace);
            aView = [rowViews objectAtIndex:column];
            [aView setFrame:viewFrame];
            [aView setNeedsDisplay:YES];
        }
    }
}

@end
