// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
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

#import <OmniAppKit/NSImage-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>
#import <OmniAppKit/OAPreferenceClient.h>
#import <OmniAppKit/OAPreferenceClientRecord.h>
#import <OmniAppKit/OAPreferenceController.h>

RCS_ID("$Id$")

@implementation OAPreferencesIconView

static const NSSize buttonSize = {82.0f, 74.0f};
static const NSSize iconSize = {32.0f, 32.0f};
static const CGFloat titleCellHeight = 35;
static const CGFloat iconBaseline = 36;

#define IconNotFound ((NSInteger)(~(NSUInteger)0))

// Init and dealloc

- (id)initWithFrame:(NSRect)rect;
{
    if (!(self = [super initWithFrame:rect]))
        return nil;
    
    [self setBoundsOrigin:NSMakePoint(-4.0f, 0.0f)]; //This matches Apples 4px margin in System Preferences on 10.4

    pressedIconIndex = IconNotFound;
    selectedClientRecord = nil;
    
    preferenceTitleCell = [[NSTextFieldCell alloc] init];
    [preferenceTitleCell setAlignment:NSCenterTextAlignment];
    [preferenceTitleCell setFont:[NSFont toolTipsFontOfSize:11.0f]];
    
    return self;
}

// API

- (void)setPreferenceController:(OAPreferenceController *)newPreferenceController;
{
    preferenceController = newPreferenceController;
    [self setNeedsDisplay:YES];
}

- (void)setPreferenceClientRecords:(NSArray *)newPreferenceClientRecords;
{
    preferenceClientRecords = newPreferenceClientRecords;
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
    // TODO: Should redo this as a collection view ...
    
    BOOL mouseInBounds = NO;
    
    NSPoint eventLocation = [self convertPoint:[event locationInWindow] fromView:nil];

    NSInteger buttonIndex = (NSInteger)(floor(eventLocation.x / buttonSize.width) + floor(eventLocation.y / buttonSize.height) * [self _iconsWide]);
    NSRect buttonRect = [self _boundsForIndex:buttonIndex];
    if (NSWidth(buttonRect) == 0)
        return;
        
    pressedIconIndex = buttonIndex;
    [self setNeedsDisplay:YES];

    while (1) {

        NSEvent *nextEvent = [[NSApplication sharedApplication] nextEventMatchingMask:NSLeftMouseDraggedMask|NSLeftMouseUpMask untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];

        NSPoint nextEventLocation = [self convertPoint:[nextEvent locationInWindow] fromView:nil];
        mouseInBounds = NSMouseInRect(nextEventLocation, buttonRect, [self isFlipped]);

        NSUInteger updatedButtonIndex = mouseInBounds ? buttonIndex : IconNotFound;
        if (pressedIconIndex != updatedButtonIndex) {
            pressedIconIndex = updatedButtonIndex;
            [self setNeedsDisplay:YES];
        }
        
        if ([nextEvent type] == NSLeftMouseUp)
            break;
    }
    
    pressedIconIndex = IconNotFound;
    [self setNeedsDisplay:YES];
    
    if (mouseInBounds)
        [preferenceController iconView:self buttonHitAtIndex:buttonIndex];
}


// NSView subclass

- (void)drawRect:(NSRect)rect;
{
    NSUInteger clientRecordCount = [self _numberOfIcons];
    for (NSUInteger clientRecordIndex = 0; clientRecordIndex < clientRecordCount; clientRecordIndex++)
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
    // TODO: Left over from when we dragged icons -- remove and let drags move the window?
    return NO;
}

@end


@implementation OAPreferencesIconView (Subclasses)

- (NSUInteger)_iconsWide;
{
    return NSMaxX([self bounds]) / buttonSize.width;
}

- (NSUInteger)_numberOfIcons;
{
    return (unsigned int)[[self preferenceClientRecords] count];
}

- (BOOL)_isIconSelectedAtIndex:(NSUInteger)index;
{
    return [[self preferenceClientRecords] objectAtIndex:index] == selectedClientRecord;
}

- (BOOL)_column:(NSUInteger *)column andRow:(NSUInteger *)row forIndex:(NSUInteger)index;
{
    if (index >= [self _numberOfIcons])
        return NO;

    NSUInteger numberOfColumns = [self _iconsWide];
    *column = index / numberOfColumns;
    *row = index % numberOfColumns;
    
    return YES;
}

- (NSRect)_boundsForIndex:(NSUInteger)index;
{
    NSUInteger row, column;

    if (![self _column:&column andRow:&row forIndex:index])
        return NSZeroRect;
        
    return NSMakeRect(row * buttonSize.width, column * buttonSize.height, buttonSize.width, buttonSize.height);
}

- (BOOL)_iconImage:(NSImage **)image andName:(NSString **)name andIdentifier:(NSString **)identifier forIndex:(NSUInteger)index;
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

- (void)_drawIconAtIndex:(NSUInteger)index drawRect:(NSRect)drawRect;
{
    NSImage *image;
    NSString *name;
    NSUInteger row, column;
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
        [[NSColor colorWithWhite:0.8f alpha:0.75f] set];
        NSRectFillUsingOperation(buttonRect, NSCompositeSourceOver);
    }

    // Draw icon, dark if it is currently being pressed
    destinationRect = NSIntegralRect(NSMakeRect(NSMidX(buttonRect) - iconSize.width / 2.0f, NSMaxY(buttonRect) - iconBaseline - iconSize.height, iconSize.width, iconSize.height));
    destinationRect.size = iconSize;
    if (index != pressedIconIndex)
        [image drawFlippedInRect:destinationRect operation:NSCompositeSourceOver fraction:1.0f];
    else {
        NSImage *darkImage;
        NSSize darkImageSize;
        
        darkImage = [image copy];
        darkImageSize = [darkImage size];
        [darkImage lockFocus];
        [[NSColor blackColor] set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, darkImageSize.width, darkImageSize.height), NSCompositeSourceIn);
        [darkImage unlockFocus];
        
        [darkImage drawFlippedInRect:destinationRect operation:NSCompositeSourceOver fraction:1.0f];
        [image drawFlippedInRect:destinationRect operation:NSCompositeSourceOver fraction:0.6666f];
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
    NSRect bounds = self.bounds;
    NSRectFill(NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), 1.0f));
    NSRectFill(NSMakeRect(NSMinX(bounds), NSMaxY(bounds)-1, NSWidth(bounds), 1.0f));
}

- (void)_sizeToFit;
{
    if (![self preferenceClientRecords])
        return;
        
    [self setFrameSize:NSMakeSize(NSWidth(self.bounds), NSMaxY([self _boundsForIndex:[self _numberOfIcons]-1]))];
}

@end
