// Copyright 1997-2005, 2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAMultiColumnListView.h"
#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <AppKit/AppKit.h>

RCS_ID("$Id$")

enum { IndicatorOff, IndicatorOn };
enum { IndicatorNormal, IndicatorOver, IndicatorDown };

#define INDICATOR_SPACING   3.0
#define EDGE_SPACING        1.0
#define SELECTION_CURVATURE 10.0
#define HEIGHT_SPACING      1.0
#define HEADER_GAP          4.0
#define HEADER_INSET        EDGE_SPACING + SELECTION_CURVATURE + 4.0

@interface OAMultiColumnListView (Private)
- (unsigned)_itemAtPoint:(NSPoint)aPoint;
- (NSRect)_rectOfItemAtIndex:(unsigned)itemIndex;
- (unsigned)_indicatorAtPoint:(NSPoint)aPoint inRect:(NSRect)itemRect;
- (void)_drawItem:(unsigned)itemIndex selected:(BOOL)isSelected inRect:(NSRect)rect;
- (void)_releaseIndicatorImages;
@end

@implementation OAMultiColumnListView

- (id)initWithFrame:(NSRect)frame;
{
    [super initWithFrame:frame];
    font = [[NSFont systemFontOfSize:[NSFont smallSystemFontSize]] retain];
    indicatorSize = NSZeroSize;
    indicatorCount = 0;
    itemHeight = 1.0;
    widestItem = 1.0;
    selectedItem = NSNotFound;
    mouseItem = NSNotFound;
    mouseIndicator = NSNotFound;
    mouseDown = NO;
    return self;
}

- (void)dealloc;
{
    [font release];
    [self _releaseIndicatorImages];
    [super dealloc];
}

// API

- (void)setFont:(NSFont *)aFont;
{
    if (font != aFont) {
        [font release];
        font = [aFont retain];
        [self queueSelectorOnce:@selector(reloadData)];
    }
}

- (void)removeIndicators;
{
    if (indicatorCount) {
        [self _releaseIndicatorImages];
        indicatorSize = NSZeroSize;
        indicatorCount = 0;
        [self queueSelectorOnce:@selector(reloadData)];
    }
}

- (void)addSelectableIndicatorOn:(NSImage *)on off:(NSImage *)off downOn:(NSImage *)downOn downOff:(NSImage *)downOff overOn:(NSImage *)overOn overOff:(NSImage *)overOff;
{
    NSSize size = [on size];

    if (size.height > indicatorSize.height)
        indicatorSize.height = size.height;
    indicatorSize.width += size.width + INDICATOR_SPACING;
    
    indicatorSelectable[indicatorCount] = YES;
    indicatorImages[indicatorCount][IndicatorOn][IndicatorNormal] = [on retain];
    indicatorImages[indicatorCount][IndicatorOn][IndicatorOver] = [overOn retain];
    indicatorImages[indicatorCount][IndicatorOn][IndicatorDown] = [downOn retain];
    indicatorImages[indicatorCount][IndicatorOff][IndicatorNormal] = [off retain];
    indicatorImages[indicatorCount][IndicatorOff][IndicatorOver] = [overOff retain];
    indicatorImages[indicatorCount][IndicatorOff][IndicatorDown] = [downOff retain];
    indicatorCount++;
    [self queueSelectorOnce:@selector(reloadData)];
}

- (void)addDraggableIndicator:(NSImage *)image;
{
    NSSize size = [image size];

    if (size.height > indicatorSize.height)
        indicatorSize.height = size.height;
    indicatorSize.width += size.width + INDICATOR_SPACING;
    
    indicatorSelectable[indicatorCount] = NO;
    indicatorImages[indicatorCount][IndicatorOn][IndicatorNormal] = nil;
    indicatorImages[indicatorCount][IndicatorOn][IndicatorOver] = nil;
    indicatorImages[indicatorCount][IndicatorOn][IndicatorDown] = nil;
    indicatorImages[indicatorCount][IndicatorOff][IndicatorNormal] = [image retain];
    indicatorImages[indicatorCount][IndicatorOff][IndicatorOver] = [image retain];
    indicatorImages[indicatorCount][IndicatorOff][IndicatorDown] = [image retain];
    indicatorCount++;
    [self queueSelectorOnce:@selector(reloadData)];
}

- (unsigned)selectedItemIndex;
{
    return selectedItem;
}

- (void)reloadData;
{
    itemCount = [dataSource countOfItemsInListView:self];
    widestItem = 0.0;

    if (itemCount == 0) {
        itemHeight = 1.0;
        columnCount = 1;
        return;
    }
    
    // find widths and heights of items
    NSDictionary *drawingAttributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, nil];
    
    unsigned itemIndex;
    for (itemIndex = 0; itemIndex < itemCount; itemIndex++) {
        NSString *title = [dataSource titleOfItemAtIndex:itemIndex inListView:self];
        
        NSSize size = [title sizeWithAttributes:drawingAttributes];
        if (size.width > widestItem) {
            widestItem = size.width;
            itemHeight = size.height;
        }
    }
    headerHeight = itemHeight + HEIGHT_SPACING * 2;
    if (itemHeight < indicatorSize.height)
        itemHeight = indicatorSize.height;
    itemHeight += HEIGHT_SPACING * 2;
    widestItem += indicatorSize.width + EDGE_SPACING * 2 + SELECTION_CURVATURE * 2;
        
    [self resizeWithOldSuperviewSize:NSZeroSize];
}

//
// NSView subclass
//

- (BOOL)isFlipped;
{
    return YES;
}

- (BOOL)isOpaque;
{
    return YES;
}

- (BOOL)acceptsFirstResponder;
{
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event;
{
    return YES;
}

- (void)viewDidMoveToWindow;
{
    [[self window] setAcceptsMouseMovedEvents:YES];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize;
{
    NSRect visible = [[self enclosingScrollView] documentVisibleRect];
    NSSize newSize;
    
    columnCount = floor(NSWidth(visible) / widestItem);
    if (columnCount == 0) {
        newSize.width = 0.0; 
        columnCount = 1;
    } else {
        newSize.width = widestItem;
    }
    rowCount = ((itemCount + columnCount - 1) / columnCount);
    newSize.height = itemHeight * (rowCount + 1) + HEADER_GAP;

    if (NSWidth(visible) > newSize.width)
        newSize.width = NSWidth(visible);
    if (NSHeight(visible) > newSize.height)
        newSize.height = NSHeight(visible);

    [self setFrameSize:newSize];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect;
{
    unsigned columnIndex;
    float columnWidth = floor(_frame.size.width / columnCount);
    unsigned drawSelected;
    NSColor *lightGray = [NSColor colorWithDeviceWhite:0.871 alpha:1.0];
    
    // headers
    if (rect.origin.y < NSMinY(_frame) + headerHeight) {
        NSMutableDictionary *drawingAttributes = [NSMutableDictionary dictionary];
        unsigned longColumns = itemCount % columnCount;
        unsigned firstItem = 0;
        unichar firstChar, nextChar, lastChar;
        BOOL offTheEnd = NO;
        NSString *title;
        
        [drawingAttributes setObject:font forKey:NSFontAttributeName];
        [drawingAttributes setObject:[NSColor controlTextColor] forKey:NSForegroundColorAttributeName];

        // header background
        [lightGray set];
        NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(_frame), NSWidth(rect), headerHeight));
        
        // header dividers
        [[NSColor colorWithDeviceWhite:0.759 alpha:1.0] set];
        for (columnIndex = 1; columnIndex < columnCount; columnIndex++) 
            NSRectFill(NSMakeRect(NSMinX(_frame) + columnWidth * columnIndex, NSMinY(_frame), 1.0, headerHeight));
        
        // header text
        firstChar = nextChar = lastChar = 'A';
        for (columnIndex = 0; columnIndex < columnCount && !offTheEnd; columnIndex++) {
            firstItem += rowCount;
            if (longColumns && columnIndex >= longColumns)
                firstItem--;
                
            if (firstItem >= itemCount) {
                lastChar = 'Z';
                offTheEnd = YES;
            } else {
                nextChar = [[dataSource titleOfItemAtIndex:firstItem inListView:self] characterAtIndex:0];
                if (firstItem) {
                    lastChar = [[dataSource titleOfItemAtIndex:firstItem-1 inListView:self] characterAtIndex:0];
                    if (lastChar != nextChar)
                        lastChar = nextChar - 1;
                }
            }
            if (firstChar == lastChar)
                title = [NSString stringWithFormat:@"%C", firstChar];
            else
                title = [NSString stringWithFormat:@"%C-%C", firstChar, lastChar];
            [title drawAtPoint:NSMakePoint(NSMinX(_frame) + columnWidth * columnIndex + HEADER_INSET, NSMinY(_frame) + HEIGHT_SPACING) withAttributes:drawingAttributes];
            firstChar = nextChar;
        }
        rect.origin.y = _frame.origin.y + headerHeight;
    }
    
    // background
    [[NSColor whiteColor] set];
    NSRectFill(rect);
    
    // column dividers
    [lightGray set];
    for (columnIndex = 1; columnIndex < columnCount; columnIndex++) 
        NSRectFill(NSMakeRect(NSMinX(_frame) + columnWidth * columnIndex, rect.origin.y, 1.0, rect.size.height));
    
    // items    
    // stupid way to do it, should be optimized later
    drawSelected = mouseDown ? mouseItem : selectedItem;
    for (columnIndex = 0; columnIndex < itemCount; columnIndex++) {
        NSRect itemRect = [self _rectOfItemAtIndex:columnIndex];
        
        if (NSIntersectsRect(rect, itemRect))
            [self _drawItem:columnIndex selected:(drawSelected == columnIndex) inRect:itemRect];
    }    
}

- (void)mouseDown:(NSEvent *)event;
{
    mouseDown = YES;
    [self mouseMoved:event];
    [self setNeedsDisplay:YES];
}

- (void)mouseMoved:(NSEvent *)event;
{
    NSPoint aPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect itemRect;
    unsigned itemIndex, indicatorIndex;

    itemIndex = [self _itemAtPoint:aPoint];
    if (itemIndex == NSNotFound) {
        itemRect = NSZeroRect;
        indicatorIndex = NSNotFound;
    } else {
        itemRect = [self _rectOfItemAtIndex:itemIndex];
        indicatorIndex = [self _indicatorAtPoint:aPoint inRect:itemRect];
        if (indicatorIndex == NSNotFound) {
            // is it over the text?
            NSString *title = [dataSource titleOfItemAtIndex:itemIndex inListView:self];
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, nil];
            if (aPoint.x > (itemRect.origin.x + EDGE_SPACING + SELECTION_CURVATURE + indicatorSize.width + [title sizeWithAttributes:attributes].width)) {
                itemIndex = NSNotFound;
            }
        }
    }
    
    if (itemIndex != mouseItem || indicatorIndex != mouseIndicator) {
        if (mouseItem != NSNotFound)
            itemRect = NSUnionRect(itemRect, [self _rectOfItemAtIndex:mouseItem]);
        mouseItem = itemIndex;
        mouseIndicator = indicatorIndex;
                
        [self setNeedsDisplayInRect:itemRect];
    }
}

- (void)mouseDragged:(NSEvent *)event;
{
    [self mouseMoved:event];
}

- (void)mouseUp:(NSEvent *)event;
{
    if (mouseIndicator != NSNotFound && indicatorSelectable[mouseIndicator]) {
        if ([delegate respondsToSelector:@selector(listView:didToggleIndicator:forItemAtIndex:)])
            [delegate listView:self didToggleIndicator:mouseIndicator forItemAtIndex:mouseItem];
    } 
    if (mouseItem != selectedItem) {
        selectedItem = mouseItem;
        if ([delegate respondsToSelector:@selector(listViewDidChangeSelection:)])
            [delegate listViewDidChangeSelection:self];
    }
    mouseDown = NO;
    mouseItem = NSNotFound;
    mouseIndicator = NSNotFound;
    [self setNeedsDisplay:YES];
}

@end

@implementation OAMultiColumnListView (Private)

- (unsigned)_itemAtPoint:(NSPoint)aPoint;
{
    unsigned result, x, y;
    unsigned longColumns = itemCount % columnCount;
    
    aPoint.x -= _frame.origin.x;
    aPoint.y -= (_frame.origin.y + headerHeight + HEADER_GAP);
    if (aPoint.y <= 0.0)
        return NSNotFound;
        
    x = (unsigned)floor(aPoint.x / floor(_frame.size.width / columnCount));
    y = (unsigned)floor(aPoint.y / itemHeight);
    result = x * rowCount + y;
    if (longColumns && x > longColumns) {
        result -= (x - longColumns);
        if (y >= rowCount - 1)
            return NSNotFound;
    } else if (y >= rowCount)
        return NSNotFound;        
    
    if (result >= itemCount)
        return NSNotFound;
    else
        return result;
}

- (NSRect)_rectOfItemAtIndex:(unsigned)itemIndex;
{
    NSRect result;
    unsigned x, y;
    unsigned longColumns = itemCount % columnCount;

    if (longColumns && itemIndex > longColumns * rowCount) {
        unsigned remaining = itemIndex - longColumns * rowCount;

        x = remaining / (rowCount-1) + longColumns;
        y = remaining % (rowCount-1);
    } else {
        x = itemIndex / rowCount;
        y = itemIndex % rowCount;
    }
    
    result.size.width = floor(_frame.size.width / columnCount);    
    result.size.height = itemHeight;
    result.origin.x = _frame.origin.x + result.size.width * x;
    result.origin.y = _frame.origin.y + headerHeight + HEADER_GAP + result.size.height * y;
    return result;
}

- (unsigned)_indicatorAtPoint:(NSPoint)aPoint inRect:(NSRect)rect;
{
    unsigned indicatorIndex;
    float pointX = aPoint.x - (rect.origin.x + EDGE_SPACING + SELECTION_CURVATURE);
    
    if (pointX < 0.0)
        return NSNotFound;
    
    for (indicatorIndex = 0; indicatorIndex < indicatorCount; indicatorIndex++) {
        NSImage *image = indicatorImages[indicatorIndex][0][0];
        NSSize imageSize = [image size];
        
        if (pointX < imageSize.width)
            return indicatorIndex;
        pointX -= imageSize.width;
    }
    return NSNotFound;
}

- (void)_drawItem:(unsigned)itemIndex selected:(BOOL)isSelected inRect:(NSRect)rect;
{
    unsigned indicatorState = (mouseItem == itemIndex ? (mouseDown ? IndicatorDown : IndicatorOver) : IndicatorNormal);
    NSMutableDictionary *drawingAttributes = [NSMutableDictionary dictionary];
    NSString *title = [dataSource titleOfItemAtIndex:itemIndex inListView:self];
    NSSize titleSize;
    float xPosition;
    unsigned indicatorIndex;
    
    [drawingAttributes setObject:font forKey:NSFontAttributeName];
    titleSize = [title sizeWithAttributes:drawingAttributes];
    
    if (isSelected) {
        NSBezierPath *selectionPath = [NSBezierPath bezierPath];
        float beginX = NSMinX(rect) + EDGE_SPACING + SELECTION_CURVATURE;
        float endX = beginX + indicatorSize.width + titleSize.width;
        
        [selectionPath moveToPoint:NSMakePoint(endX, NSMinY(rect))];
        [selectionPath curveToPoint:NSMakePoint(endX, NSMaxY(rect)) controlPoint1:NSMakePoint(endX + SELECTION_CURVATURE, NSMinY(rect)) controlPoint2:NSMakePoint(endX + SELECTION_CURVATURE, NSMaxY(rect))];
        [selectionPath lineToPoint:NSMakePoint(beginX, NSMaxY(rect))];
        [selectionPath curveToPoint:NSMakePoint(beginX, NSMinY(rect)) controlPoint1:NSMakePoint(beginX - SELECTION_CURVATURE, NSMaxY(rect)) controlPoint2:NSMakePoint(beginX - SELECTION_CURVATURE, NSMinY(rect))];
        [selectionPath closePath];
        
        [[NSColor colorWithDeviceRed:0.26 green:0.42 blue:0.84 alpha:1.0] set];
        [selectionPath fill];
        [drawingAttributes setObject:[NSColor selectedMenuItemTextColor] forKey:NSForegroundColorAttributeName];
    } else 
        [drawingAttributes setObject:[NSColor controlTextColor] forKey:NSForegroundColorAttributeName];
    
    xPosition = rect.origin.x + EDGE_SPACING + SELECTION_CURVATURE;
    for (indicatorIndex = 0; indicatorIndex < indicatorCount; indicatorIndex++) {
        int selected = indicatorSelectable[indicatorIndex] && [dataSource indicatorState:indicatorIndex forItemAtIndex:itemIndex inListView:self];
        NSImage *image = indicatorImages[indicatorIndex][selected][indicatorIndex == mouseIndicator ? indicatorState : IndicatorNormal];
        NSSize imageSize = [image size];
        
        [image compositeToPoint:NSMakePoint(xPosition, NSMaxY(rect) - (NSHeight(rect) - imageSize.height) / 2.0) operation:NSCompositeSourceOver];
        xPosition += imageSize.width + INDICATOR_SPACING;
    }
    
    [title drawAtPoint:NSMakePoint(xPosition, NSMinY(rect) + (NSHeight(rect) - titleSize.height) / 2.0) withAttributes:drawingAttributes];
}

- (void)_releaseIndicatorImages;
{
    unsigned indicatorIndex, on, state;
    
    for (indicatorIndex = 0; indicatorIndex < indicatorCount; indicatorIndex++) 
        for (on = 0; on < 2; on++)
            for (state = 0; state < 3; state++)
                [indicatorImages[indicatorIndex][on][state] release];
}

@end
