// Copyright 2000-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAPreferencesIconView.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniBase/OmniBase.h>

#import "NSImage-OAExtensions.h"
#import "NSView-OAExtensions.h"
#import "OAPreferenceClient.h"
#import "OAPreferenceClientRecord.h"
#import "OAPreferenceController.h"

RCS_ID("$Id$")

@implementation OAPreferencesIconView

static const NSSize buttonSize = {82.0, 74.0};
static const NSSize iconSize = {32.0, 32.0};
static const CGFloat titleCellHeight = 35;
static const CGFloat iconBaseline = 36;

#define IconIndexNone (~(unsigned int)0)

// Init and dealloc

- (id)initWithFrame:(NSRect)rect;
{
    if (![super initWithFrame:rect])
        return nil;
    
    [self setBoundsOrigin:NSMakePoint(-4.0, 0.0)]; //This matches Apples 4px margin in System Preferences on 10.4

    pressedIconIndex = IconIndexNone;
    selectedClientRecord = nil;
    
    preferenceTitleCell = [[NSTextFieldCell alloc] init];
    [preferenceTitleCell setAlignment:NSCenterTextAlignment];
    [preferenceTitleCell setFont:[NSFont toolTipsFontOfSize:11.0]];
    
    return self;
}

// API

- (void)setPreferenceController:(OAPreferenceController *)newPreferenceController;
{
    [preferenceController autorelease];
    preferenceController = [newPreferenceController retain];
    [self setNeedsDisplay:YES];
}

- (void)setPreferenceClientRecords:(NSArray *)newPreferenceClientRecords;
{
    [preferenceClientRecords autorelease];
    preferenceClientRecords = [newPreferenceClientRecords retain];
    [self _sizeToFit];
    [self setNeedsDisplay:YES];
}

- (NSArray *)preferenceClientRecords;
{
    return preferenceClientRecords;
}

- (void)setSelectedClientRecord:(OAPreferenceClientRecord *)newSelectedClientRecord;
{
    selectedClientRecord = newSelectedClientRecord;
    [self setNeedsDisplay:YES];
}


// NSResponder

- (void)mouseDown:(NSEvent *)event;
{
    NSPoint eventLocation;
    NSRect slopRect;
    const CGFloat dragSlop = 4.0;
    unsigned int index;
    NSRect buttonRect;
    BOOL mouseInBounds = NO;
    
    eventLocation = [self convertPoint:[event locationInWindow] fromView:nil];
    slopRect = NSInsetRect(NSMakeRect(eventLocation.x, eventLocation.y, 1.0, 1.0), -dragSlop, -dragSlop);

    index = floor(eventLocation.x / buttonSize.width) + floor(eventLocation.y / buttonSize.height) * [self _iconsWide];
    buttonRect = [self _boundsForIndex:index];
    if (NSWidth(buttonRect) == 0)
        return;
        
    pressedIconIndex = index;
    [self setNeedsDisplay:YES];

    while (1) {
        NSEvent *nextEvent;
        NSPoint nextEventLocation;
        unsigned int newPressedIconIndex;

        nextEvent = [NSApp nextEventMatchingMask:NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];

        nextEventLocation = [self convertPoint:[nextEvent locationInWindow] fromView:nil];
        mouseInBounds = NSMouseInRect(nextEventLocation, buttonRect, [self isFlipped]);
        newPressedIconIndex = mouseInBounds ? index : IconIndexNone;
        if (newPressedIconIndex != pressedIconIndex) {
            pressedIconIndex = newPressedIconIndex;
            [self setNeedsDisplay:YES];
        }

        if ([nextEvent type] == NSLeftMouseUp)
            break;
        else if (!NSMouseInRect(nextEventLocation, slopRect, NO)) {
            if ([self _dragIconIndex:index event:nextEvent]) {
                mouseInBounds = NO;
                break;
            }
        }
    }
    
    pressedIconIndex = IconIndexNone;
    [self setNeedsDisplay:YES];
    
    if (mouseInBounds)
        [preferenceController iconView:self buttonHitAtIndex:index];
}


// NSView subclass

- (void)drawRect:(NSRect)rect;
{
    unsigned int clientRecordCount = [self _numberOfIcons];
    for (unsigned int clientRecordIndex = 0; clientRecordIndex < clientRecordCount; clientRecordIndex++)
        [self _drawIconAtIndex:clientRecordIndex drawRect:rect];
}

- (BOOL)isFlipped;
{
    return YES;
}

- (BOOL)isOpaque;
{
    return NO;
}

- (BOOL)mouseDownCanMoveWindow;
{
    // Mouse drags should drag our icons, not the window (even though we're not opaque).
    return NO;
}

// NSDraggingSource

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag;
{
    return NSDragOperationMove;
}

- (void)draggedImage:(NSImage *)image endedAt:(NSPoint)screenPoint operation:(NSDragOperation)operation;
{
}

- (BOOL)ignoreModifierKeysWhileDragging;
{
    return YES;
}


@end


@implementation OAPreferencesIconView (Subclasses)

- (unsigned int)_iconsWide;
{
    return NSMaxX([self bounds]) / buttonSize.width;
}

- (unsigned int)_numberOfIcons;
{
    return (unsigned int)[[self preferenceClientRecords] count];
}

- (BOOL)_isIconSelectedAtIndex:(unsigned int)index;
{
    return [[self preferenceClientRecords] objectAtIndex:index] == selectedClientRecord;
}

- (BOOL)_column:(unsigned int *)column andRow:(unsigned int *)row forIndex:(unsigned int)index;
{
    if (index >= [self _numberOfIcons])
        return NO;

    unsigned int numberOfColumns = [self _iconsWide];
    *column = index / numberOfColumns;
    *row = index % numberOfColumns;
    
    return YES;
}

- (NSRect)_boundsForIndex:(unsigned int)index;
{
    unsigned int row, column;

    if (![self _column:&column andRow:&row forIndex:index])
        return NSZeroRect;
        
    return NSMakeRect(row * buttonSize.width, column * buttonSize.height, buttonSize.width, buttonSize.height);
}

- (BOOL)_iconImage:(NSImage **)image andName:(NSString **)name andIdentifier:(NSString **)identifier forIndex:(unsigned int)index;
{
    OAPreferenceClientRecord *clientRecord;
    
    if (index >= [self _numberOfIcons])
        return NO;
    
    clientRecord = [[self preferenceClientRecords] objectAtIndex:index];
    *image = [clientRecord iconImage];
    *name = [clientRecord shortTitle];
    if (identifier)
        *identifier = [clientRecord identifier];

    OBPOSTCONDITION(*image != nil);
    OBPOSTCONDITION(*name != nil);
    OBPOSTCONDITION(identifier == NULL || *identifier != nil);
    
    return YES;
}

- (void)_drawIconAtIndex:(unsigned int)index drawRect:(NSRect)drawRect;
{
    NSImage *image;
    NSString *name;
    unsigned int row, column;
    NSRect buttonRect, destinationRect;
    
    buttonRect = [self _boundsForIndex:index];
    if (!NSIntersectsRect(buttonRect, drawRect))
        return;

    if (![self _iconImage:&image andName:&name andIdentifier:NULL forIndex:index])
        return;
    
    if (![self _column:&column andRow:&row forIndex:index])
        return;

    // Draw dark gray rectangle around currently selected icon (for MultipleIconView)
    if ([self _isIconSelectedAtIndex:index]) {
        [[NSColor colorWithCalibratedWhite:0.8 alpha:0.75] set];
        NSRectFillUsingOperation(buttonRect, NSCompositeSourceOver);
    }

    // Draw icon, dark if it is currently being pressed
    destinationRect = NSIntegralRect(NSMakeRect(NSMidX(buttonRect) - iconSize.width / 2.0, NSMaxY(buttonRect) - iconBaseline - iconSize.height, iconSize.width, iconSize.height));
    destinationRect.size = iconSize;
    if (index != pressedIconIndex)
        [image drawFlippedInRect:destinationRect operation:NSCompositeSourceOver fraction:1.0];
    else {
        NSImage *darkImage;
        NSSize darkImageSize;
        
        darkImage = [image copy];
        darkImageSize = [darkImage size];
        [darkImage lockFocus];
        [[NSColor blackColor] set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, darkImageSize.width, darkImageSize.height), NSCompositeSourceIn);
        [darkImage unlockFocus];
        
        [darkImage drawFlippedInRect:destinationRect operation:NSCompositeSourceOver fraction:1.0];
        [image drawFlippedInRect:destinationRect operation:NSCompositeSourceOver fraction:0.6666];
        [darkImage release];
    }
    
    // Draw text
    [preferenceTitleCell setStringValue:name];
    [preferenceTitleCell drawWithFrame:NSMakeRect(NSMinX(buttonRect), NSMaxY(buttonRect) - titleCellHeight, buttonSize.width, titleCellHeight) inView:self];
}

- (void)_drawBackgroundForRect:(NSRect)rect;
{
    [[NSColor controlLightHighlightColor] set];
    NSRectFill(rect);
    [[NSColor windowFrameColor] set];
    NSRectFill(NSMakeRect(NSMinX(_bounds), NSMinY(_bounds), NSWidth(_bounds), 1.0));
    NSRectFill(NSMakeRect(NSMinX(_bounds), NSMaxY(_bounds)-1, NSWidth(_bounds), 1.0));
}

- (void)_sizeToFit;
{
    if (![self preferenceClientRecords])
        return;
        
    [self setFrameSize:NSMakeSize(NSWidth(_bounds), NSMaxY([self _boundsForIndex:[self _numberOfIcons]-1]))];
}

- (BOOL)_dragIconIndex:(unsigned int)index event:(NSEvent *)event;
{
    NSImage *iconImage;
    NSString *name;
    NSString *identifier;
    
    if (![self _iconImage:&iconImage andName:&name andIdentifier:&identifier forIndex:index])
        return YES; // Yes, I handled your stinky bad call.
    
    return [self _dragIconImage:iconImage andName:name andIdentifier:identifier event:event];
}

- (BOOL)_dragIconImage:(NSImage *)iconImage andName:(NSString *)name event:(NSEvent *)event;
{
    return [self _dragIconImage:iconImage andName:name andIdentifier:name event:event];
}

- (BOOL)_dragIconImage:(NSImage *)iconImage andName:(NSString *)name andIdentifier:(NSString *)identifier event:(NSEvent *)event;
{
    NSImage *dragImage;
    NSPasteboard *pasteboard;
    NSPoint dragPoint, startPoint;

    dragImage = [[NSImage alloc] initWithSize:buttonSize];
    [dragImage lockFocus]; {
        [iconImage drawInRect:NSMakeRect(buttonSize.width / 2.0 - iconSize.width / 2.0, iconBaseline, iconSize.width, iconSize.height) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
        
        [preferenceTitleCell setStringValue:name];
        [preferenceTitleCell drawWithFrame:NSMakeRect(0, 0, buttonSize.width, titleCellHeight) inView:self];
    } [dragImage unlockFocus];
       
    pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:@"NSToolbarIndividualItemDragType"] owner:nil];
    [pasteboard setString:identifier forType:@"NSToolbarItemIdentifierPboardType"];
    [pasteboard setString:identifier forType:@"NSToolbarItemIdentiferPboardType"]; // Apple misspelled this type in 10.1
    
    dragPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    startPoint = NSMakePoint(dragPoint.x - buttonSize.width / 2.0, dragPoint.y + buttonSize.height / 2.0);
    [self dragImage:dragImage at:startPoint offset:NSZeroSize event:event pasteboard:pasteboard source:self slideBack:NO];
    
    return YES;
}


@end
