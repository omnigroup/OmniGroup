// Copyright 2003-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAGradientTableView.h>

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OAGradientTableView

// API

- (void)setAcceptsFirstMouse:(BOOL)flag;
{
    flags.acceptsFirstMouse = flag;
}

// NSView subclass

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
    if (flags.acceptsFirstMouse)
        return [[NSApplication sharedApplication] isActive];
        
    return [super acceptsFirstMouse:theEvent];
}

// NSTableView subclass

- (id)_highlightColorForCell:(NSCell *)cell;
{
    return nil;
}

- (void)highlightSelectionInClipRect:(NSRect)rect;
{
    NSColorSpace *rgb = [NSColorSpace genericRGBColorSpace];

    // Take the color apart
    NSColor *alternateSelectedControlColor = [NSColor selectedContentBackgroundColor];
    CGFloat hue, saturation, brightness, alpha;
    [[alternateSelectedControlColor colorUsingColorSpace:rgb] getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

    // Create synthetic darker and lighter versions
    // NSColor *lighterColor = [NSColor colorWithDeviceHue:hue - (1.0/120.0) saturation:MAX(0.0, saturation-0.12) brightness:MIN(1.0, brightness+0.045) alpha:alpha];
    NSColor *lighterColor = [NSColor colorWithDeviceHue:hue saturation:MAX(0.0f, saturation-.12f) brightness:MIN(1.0f, brightness+0.30f) alpha:alpha];
    NSColor *darkerColor = [NSColor colorWithDeviceHue:hue saturation:MIN(1.0f, (saturation > .04f) ? saturation+0.12f : 0.0f) brightness:MAX(0.0f, brightness-0.045f) alpha:alpha];
    
    // If this view isn't key, use the gray version of the dark color. Note that this varies from the standard gray version that NSCell returns as its highlightColorWithFrame: when the cell is not in a key view, in that this is a lot darker. Mike and I think this is justified for this kind of view -- if you're using the dark selection color to show the selected status, it makes sense to leave it dark.
    if ([[self window] firstResponder] != self || ![[self window] isKeyWindow]) {
        NSColorSpace *gray = [NSColorSpace genericGrayColorSpace];

        alternateSelectedControlColor = [[alternateSelectedControlColor colorUsingColorSpace:gray] colorUsingColorSpace:rgb];
        lighterColor = [[lighterColor colorUsingColorSpace:gray] colorUsingColorSpace:rgb];
        darkerColor = [[darkerColor colorUsingColorSpace:gray] colorUsingColorSpace:rgb];
    }

    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[lighterColor, darkerColor]];

    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    NSUInteger rowIndex = [selectedRowIndexes firstIndex];

    while (rowIndex != NSNotFound) {
        NSUInteger endOfCurrentRunRowIndex, newRowIndex = rowIndex;
        do {
            endOfCurrentRunRowIndex = newRowIndex;
            newRowIndex = [selectedRowIndexes indexGreaterThanIndex:endOfCurrentRunRowIndex];
        } while (newRowIndex == endOfCurrentRunRowIndex + 1);
            
        NSRect rowRect = NSUnionRect([self rectOfRow:rowIndex], [self rectOfRow:endOfCurrentRunRowIndex]);
        
        NSRect topBar, washRect;
        NSDivideRect(rowRect, &topBar, &washRect, 1.0f, NSMinYEdge);
        
        // Draw the top line of pixels of the selected row in the alternateSelectedControlColor
        [alternateSelectedControlColor set];
        NSRectFill(topBar);

        // Draw a soft wash underneath it
        [gradient drawInRect:washRect angle:90];

        rowIndex = newRowIndex;
    }
}

- (void)selectRowIndexes:(NSIndexSet *)indexes byExtendingSelection:(BOOL)extend;
{
    [super selectRowIndexes:indexes byExtendingSelection:extend];
    [self setNeedsDisplay:YES]; // we display extra because we draw multiple contiguous selected rows differently, so changing one row's selection can change how others draw.
}

- (void)deselectRow:(NSInteger)row;
{
    [super deselectRow:row];
    [self setNeedsDisplay:YES]; // we display extra because we draw multiple contiguous selected rows differently, so changing one row's selection can change how others draw.
}

@end
