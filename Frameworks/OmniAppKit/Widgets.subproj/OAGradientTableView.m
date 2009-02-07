// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAGradientTableView.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@interface OAGradientTableView (Private)
@end

/*
    CoreGraphics gradient helpers
*/

typedef struct {
    CGFloat red1, green1, blue1, alpha1;
    CGFloat red2, green2, blue2, alpha2;
} _twoColorsType;

static void linearColorBlendFunction(void *info, const CGFloat *in, CGFloat *out)
{
    _twoColorsType *twoColors = info;
    
    out[0] = (1.0 - *in) * twoColors->red1 + *in * twoColors->red2;
    out[1] = (1.0 - *in) * twoColors->green1 + *in * twoColors->green2;
    out[2] = (1.0 - *in) * twoColors->blue1 + *in * twoColors->blue2;
    out[3] = (1.0 - *in) * twoColors->alpha1 + *in * twoColors->alpha2;
}

static void linearColorReleaseInfoFunction(void *info)
{
    free(info);
}

static const CGFunctionCallbacks linearFunctionCallbacks = {0, &linearColorBlendFunction, &linearColorReleaseInfoFunction};

/*
    End CoreGraphics gradient helpers
*/

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
        return [NSApp isActive];
        
    return [super acceptsFirstMouse:theEvent];
}

// NSTableView subclass

- (id)_highlightColorForCell:(NSCell *)cell;
{
    return nil;
}

- (void)highlightSelectionInClipRect:(NSRect)rect;
{
    // Take the color apart
    NSColor *alternateSelectedControlColor = [NSColor alternateSelectedControlColor];
    CGFloat hue, saturation, brightness, alpha;
    [[alternateSelectedControlColor colorUsingColorSpaceName:NSDeviceRGBColorSpace] getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

    // Create synthetic darker and lighter versions
    // NSColor *lighterColor = [NSColor colorWithDeviceHue:hue - (1.0/120.0) saturation:MAX(0.0, saturation-0.12) brightness:MIN(1.0, brightness+0.045) alpha:alpha];
    NSColor *lighterColor = [NSColor colorWithDeviceHue:hue saturation:MAX(0.0, saturation-.12) brightness:MIN(1.0, brightness+0.30) alpha:alpha];
    NSColor *darkerColor = [NSColor colorWithDeviceHue:hue saturation:MIN(1.0, (saturation > .04) ? saturation+0.12 : 0.0) brightness:MAX(0.0, brightness-0.045) alpha:alpha];
    
    // If this view isn't key, use the gray version of the dark color. Note that this varies from the standard gray version that NSCell returns as its highlightColorWithFrame: when the cell is not in a key view, in that this is a lot darker. Mike and I think this is justified for this kind of view -- if you're using the dark selection color to show the selected status, it makes sense to leave it dark.
    if ([[self window] firstResponder] != self || ![[self window] isKeyWindow]) {
        alternateSelectedControlColor = [[alternateSelectedControlColor colorUsingColorSpaceName:NSDeviceWhiteColorSpace] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
        lighterColor = [[lighterColor colorUsingColorSpaceName:NSDeviceWhiteColorSpace] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
        darkerColor = [[darkerColor colorUsingColorSpaceName:NSDeviceWhiteColorSpace] colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    }
    
    // Set up the helper function for drawing washes
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    _twoColorsType *twoColors = malloc(sizeof(_twoColorsType)); // We malloc() the helper data because we may draw this wash during printing, in which case it won't necessarily be evaluated immediately. We need for all the data the shading function needs to draw to potentially outlive us.
    [lighterColor getRed:&twoColors->red1 green:&twoColors->green1 blue:&twoColors->blue1 alpha:&twoColors->alpha1];
    [darkerColor getRed:&twoColors->red2 green:&twoColors->green2 blue:&twoColors->blue2 alpha:&twoColors->alpha2];
    static const CGFloat domainAndRange[8] = {0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0};
    CGFunctionRef linearBlendFunctionRef = CGFunctionCreate(twoColors, 1, domainAndRange, 4, domainAndRange, &linearFunctionCallbacks);
    
    NSIndexSet *selectedRowIndexes = [self selectedRowIndexes];
    NSUInteger rowIndex = [selectedRowIndexes firstIndex];

    while (rowIndex != NSNotFound) {
        unsigned int endOfCurrentRunRowIndex, newRowIndex = rowIndex;
        do {
            endOfCurrentRunRowIndex = newRowIndex;
            newRowIndex = [selectedRowIndexes indexGreaterThanIndex:endOfCurrentRunRowIndex];
        } while (newRowIndex == endOfCurrentRunRowIndex + 1);
            
        NSRect rowRect = NSUnionRect([self rectOfRow:rowIndex], [self rectOfRow:endOfCurrentRunRowIndex]);
        
        NSRect topBar, washRect;
        NSDivideRect(rowRect, &topBar, &washRect, 1.0, NSMinYEdge);
        
        // Draw the top line of pixels of the selected row in the alternateSelectedControlColor
        [alternateSelectedControlColor set];
        NSRectFill(topBar);

        // Draw a soft wash underneath it
        CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextSaveGState(context); {
            CGContextClipToRect(context, (CGRect){{NSMinX(washRect), NSMinY(washRect)}, {NSWidth(washRect), NSHeight(washRect)}});
            CGShadingRef cgShading = CGShadingCreateAxial(colorSpace, CGPointMake(0, NSMinY(washRect)), CGPointMake(0, NSMaxY(washRect)), linearBlendFunctionRef, NO, NO);
            CGContextDrawShading(context, cgShading);
            CGShadingRelease(cgShading);
        } CGContextRestoreGState(context);

        rowIndex = newRowIndex;
    }

    
    CGFunctionRelease(linearBlendFunctionRef);
    CGColorSpaceRelease(colorSpace);
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
