// Copyright 2005-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OITabMatrix.h>

#import <OmniAppKit/OmniAppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorTabController.h>
#import <OmniInspector/OITabCell.h>

RCS_ID("$Id$");

@implementation OITabMatrix
{
    NSArray *oldSelection;
    
    OITabMatrixHighlightStyle highlightStyle;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;
    
    _allowPinning = YES;
    
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    
    _allowPinning = YES;

    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    self.allowPinning = YES;
    //default to allow pinning, you can explicitly turn it off after loading the view
}

- (void)setTabMatrixHighlightStyle:(enum OITabMatrixHighlightStyle)newHighlightStyle;
{
    if (newHighlightStyle != highlightStyle) {
        highlightStyle = newHighlightStyle;
        [self setNeedsDisplay];
    }
}

- (enum OITabMatrixHighlightStyle)tabMatrixHighlightStyle;
{
    return highlightStyle;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (NSArray *)pinnedCells;
{
    NSMutableArray *pinnedCells = [NSMutableArray array];
    
    for (OITabCell *cell in [self cells])
        if ([cell isPinned])
            [pinnedCells addObject:cell];
    
    return pinnedCells;
}

- (NSArray *)selectedCells;
{
    // NSMatrix doesn't know about pinned cells, and thus the matrix's idea of what cells are selected doesn't necessarily include the pinned cells. Overriding -selectedCells to make sure the result includes the pinned cells.
    NSMutableArray *selectedCells = [NSMutableArray arrayWithArray:[super selectedCells]];
    for (OITabCell *cell in [self cells])
        if ([cell isPinned] && ([selectedCells indexOfObjectIdenticalTo:cell] == NSNotFound))
            [selectedCells addObject:cell];

    return selectedCells;
}

- (BOOL)sendAction;
{
    // If only one tab is currently selected, and the user clicked on it, deselect it (unless it's pinned or we are in single-selection mode)
    if (oldSelection && [self mode] != NSRadioModeMatrix) {
        NSArray *newSelection = [self selectedCells];

        NSMutableArray *oldUnpinnedSelection = [NSMutableArray array];
        NSMutableArray *newUnpinnedSelection = [NSMutableArray array];
        
        for (OITabCell *cell in oldSelection)
            if (![cell isPinned])
                [oldUnpinnedSelection addObject:cell];

        for (OITabCell *cell in newSelection)
            if (![cell isPinned])
                [newUnpinnedSelection addObject:cell];

        if ([oldUnpinnedSelection count] == 1 && [newUnpinnedSelection count] == 1) {
            if ([oldUnpinnedSelection objectAtIndex:0] == [newUnpinnedSelection objectAtIndex:0]) {
                [self deselectAllCells];
            }
        }
    } else if ([oldSelection count] > 0 && [self mode] == NSRadioModeMatrix) {
        // Even in radio mode, we were getting zero cells selected if you clicked and then dragged out of one of the tabs.
        // In any case, do some extra work to avoid empty selection whenever possible.
        if ([[self selectedCells] count] == 0) {
            [self selectCell:[oldSelection objectAtIndex:0]];
        }
    }
    return [super sendAction];
}

- (void)mouseDown:(NSEvent *)event;
{
    [self setAllowsEmptySelection:YES];
    [self setNeedsDisplay:YES];
    oldSelection = [self selectedCells];
    NSArray *allCells = [self cells];
    [allCells makeObjectsPerformSelector:@selector(saveState)];

    if (self.allowPinning) {
        // PBS 13 Sep 2016: switching between tabs is logy because of the double-click delay for pinning.
        // So, instead, allow pinning — but only when double-clicking on a selected cell.
        
        OITabCell *clickedCell = nil;
        NSInteger row, column;
        if ([self getRow:&row column:&column forPoint:[self convertPoint:[event locationInWindow] fromView:nil]]) {
            clickedCell = [self cellAtRow:row column:column];
        }
        BOOL didClickSelectedCell = (clickedCell && [oldSelection containsObjectIdenticalTo:clickedCell]);

        // Wait to see if this is a double-click before proceeding
        if (didClickSelectedCell && [event clickCount] == 1) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            float doubleClickTime = 0.25f;  // Wait a maximum of a quarter of a second to see if it's a double-click
            id object = [defaults objectForKey: @"com.apple.mouse.doubleClickThreshold"];
            if (object && [object floatValue] < 0.25f)
                doubleClickTime = [object floatValue];
            NSEvent *nextEvent = [[self window] nextEventMatchingMask:NSLeftMouseDownMask untilDate:[NSDate dateWithTimeIntervalSinceNow:doubleClickTime] inMode:NSEventTrackingRunLoopMode dequeue:YES];
            if (nextEvent)
                event = nextEvent;
        }
        if (clickedCell) {
            if ([event clickCount] == 2) {  // double-click pins/unpins an inspector
                [clickedCell setIsPinned:![clickedCell isPinned]];  // The action method is responsible for checking the pinnedness of the tabs and making sure that attribute gets propagated to the inspector tab controllers as appropriate
            }
            if ([self mode] == NSRadioModeMatrix) { // If we're in single-selection mode, clear the pinnedness of any other tab cells
                for (OITabCell *tabCell in allCells) {
                    if (tabCell != clickedCell) {
                        [tabCell setIsPinned:NO];
                    }
                }
            }
        }
    }
    
    @try {
        // <bug:///71831> (Exception Crash after after moving the inspectors [no repro])
        // mouseDown can throw and we don't want OmniPlan to crash.
        [super mouseDown:event];
    } @catch (NSException *exception) {
        NSLog(@"Exception raised in -[%@ %@]: %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd), exception);
    } 
    [allCells makeObjectsPerformSelector:@selector(clearState)];
    [self setNeedsDisplay:YES];
    oldSelection = nil;
}

- (void)drawRect:(NSRect)dirtyRect;
{
    NSArray *tabCells = [self cells];
    NSUInteger cellCount = [tabCells count];

    if (highlightStyle == OITabMatrixYosemiteHighlightStyle) {
        NSUInteger cellIndex;
        [[NSColor colorWithWhite:0 alpha:0.07f] set];
        for(cellIndex=0; cellIndex<cellCount; cellIndex++) {
            if ([[tabCells objectAtIndex:cellIndex] drawState]) {
                NSRect rect = [self cellFrameAtRow:0 column:cellIndex];
                rect.size.height -= 2;
                rect.origin.y += 2;
                rect = NSInsetRect(rect, 1, 0);
                NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRectangle:rect byRoundingCorners:OFRectCornerMinXMaxY|OFRectCornerMaxXMaxY withRadius:4];
                [path fill];
            }
        }
    } else if (highlightStyle == OITabMatrixCellsHighlightStyle) {
        // Used to be done by OITabCell; now we draw all the backgrounds first before drawing any cells, and all the foregrounds after drawing all cells
        NSUInteger cellIndex;
        [[NSColor colorWithWhite:.85f alpha:1.0f] set];
        for(cellIndex=0; cellIndex<cellCount; cellIndex++) {
            if ([[tabCells objectAtIndex:cellIndex] drawState]) {
                NSRectFill([self cellFrameAtRow:0 column:cellIndex]);
            }
        }
    }
    
    [super drawRect:dirtyRect];
    
    if (highlightStyle == OITabMatrixCellsHighlightStyle) {
        /* Simply draw a frame around each selected cell */
        NSUInteger cellIndex;
        for(cellIndex=0; cellIndex<cellCount; cellIndex++) {
            if ([[tabCells objectAtIndex:cellIndex] drawState]) {
                NSRect cellFrame = [self cellFrameAtRow:0 column:cellIndex];
                [[NSColor lightGrayColor] set];
                NSRect foo = cellFrame;
                foo.size.width = 1;
                NSFrameRect(foo);
                foo.origin.x = NSMaxX(cellFrame) - 1;
                NSFrameRect(foo);
            }
        }
    }
    
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent;
{
    if ([theEvent type] != NSKeyDown)
        return NO;
    
    NSString *fullString = [NSString stringForKeyEquivalent:[theEvent charactersIgnoringModifiers] andModifierMask:[theEvent modifierFlags]];
    for (OITabCell *cell in [self cells]) {
        NSString *keyEquivalent = [cell keyEquivalent];        
        if ([keyEquivalent isEqualToString:fullString]) {
            [self selectCell:cell];
            [self performClick:nil];
            return YES;
        }
    }
    
    return NO;
}

@end
