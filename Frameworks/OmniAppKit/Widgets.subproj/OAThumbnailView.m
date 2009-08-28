// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAThumbnailView.h>

#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSString-OAExtensions.h>
#import <OmniAppKit/NSView-OAExtensions.h>

RCS_ID("$Id$")

@interface OAThumbnailView (Internal)
- (void)getMaximumThumbnailSize;
@end

@implementation OAThumbnailView

static NSFont *labelFont = nil;

#define LABEL_FONT_SIZE				12
#define LABEL_PADDING 				5
#define LABEL_OVERLAP_WITH_BOTTOM_PADDING 	3

+ (void)initialize;
{
    OBINITIALIZE;
    
    labelFont = [NSFont userFontOfSize:LABEL_FONT_SIZE];
    if (!labelFont)
	labelFont = [NSFont fontWithName:@"Helvetica" size:LABEL_FONT_SIZE];
}

- initWithFrame:(NSRect)aFrame;
{
    aFrame.size.height = 0.0;
    aFrame.size.width = 0.0;
    if (![super initWithFrame:aFrame])
	return nil;

    maximumThumbnailSize = NSMakeSize(-1,-1);
    padding = NSMakeSize(8, 8);
    columnCount = 1;
    
    thumbnailsAreNumbered = YES;
    return self;
}

- (void)dealloc;
{
    [provider release];
    [super dealloc];
}


// NSView subclass

- (void)setFrameSize:(NSSize)_newSize
{
    [self getMaximumThumbnailSize];

    NSRect superBounds = [[self superview] bounds];
     
    cellSize.width = padding.width * 2 + maximumThumbnailSize.width;
    cellSize.height = padding.height * 2 + maximumThumbnailSize.height;
    if (thumbnailsAreNumbered)
	cellSize.height += LABEL_FONT_SIZE + LABEL_PADDING
	                   - LABEL_OVERLAP_WITH_BOTTOM_PADDING;

    columnCount = MAX(superBounds.size.width / cellSize.width, 1);
    rowCount = [provider thumbnailCount] / columnCount
        + (([provider thumbnailCount] % columnCount) ? 1 : 0);
    rowCount = MAX(1U, rowCount);
    horizontalMargin = ceil((superBounds.size.width 
                             - columnCount * cellSize.width)
                            / (columnCount+1.0));

    [super setFrameSize:NSMakeSize(NSWidth(superBounds), rowCount * cellSize.height)];
}

- (void)drawRect:(NSRect)rect
{
    int startRow, endRow, row;
    unsigned int thumbnailCount;

    [[NSColor controlBackgroundColor] set];
    NSRectFill(rect);

    thumbnailCount = [provider thumbnailCount];
    
    startRow = NSMinY(rect) / cellSize.height;
    endRow = MIN(NSMaxY(rect) / cellSize.height, rowCount);

    for (row = startRow; row <= endRow; row++) {
        unsigned int column;
	float	y;
	
	y = cellSize.height * row;
	for (column = 0; column < columnCount; column++) {
	    unsigned int index;
	    NSImage *image;
	    NSSize imageSize;
	    NSRect imageRect;
	    NSRect rect;
	    NSPoint point;
	    float x;
            BOOL isSelected;
    
	    index = row * columnCount + column;
            if (index >= thumbnailCount)
		return;
		
            imageSize = [provider thumbnailSizeAtIndex: index];
    
	    x = column * (horizontalMargin + cellSize.width) + horizontalMargin;
	    point.x = ceil(x + padding.width + (maximumThumbnailSize.width - imageSize.width) / 2);
	    point.y = ceil(y + cellSize.height - (padding.height + (maximumThumbnailSize.height - imageSize.height) / 2));
	    if (thumbnailsAreNumbered) {
		point.y -= LABEL_FONT_SIZE + LABEL_PADDING - LABEL_OVERLAP_WITH_BOTTOM_PADDING;
	    }

            imageRect = NSMakeRect(point.x, point.y - imageSize.height, imageSize.width, imageSize.height);

            isSelected = [provider isThumbnailSelectedAtIndex: index];
	    if (isSelected) {
                rect = NSMakeRect(x, y, cellSize.width, cellSize.height);
                [self drawRoundedRect:rect cornerRadius:12 color:[NSColor selectedControlColor]];
	    }

            rect = NSInsetRect(imageRect, -1.0, -1.0);
	    [[NSColor controlColor] set];
            NSFrameRect(NSOffsetRect(rect, 2.0, 2.0));
	    [[NSColor controlShadowColor] set];
            NSFrameRect(NSOffsetRect(rect, 1.0, 1.0));
	    [[NSColor controlDarkShadowColor] set];
	    NSFrameRect(rect);
	    
	    if (thumbnailsAreNumbered) {
                rect = NSMakeRect(x, point.y + LABEL_PADDING + LABEL_OVERLAP_WITH_BOTTOM_PADDING - 3, cellSize.width, LABEL_FONT_SIZE);

		[[NSString stringWithFormat:@"%d", index + 1] drawWithFont:labelFont color:(isSelected ? [NSColor selectedControlTextColor] : [NSColor controlTextColor]) alignment:NSCenterTextAlignment rectangle:rect];
	    }
	
            image = [provider thumbnailImageAtIndex: index];
	    if (image) {
		[image compositeToPoint:point operation:NSCompositeCopy];
	    } else {
		[self drawMissingThumbnailRect:imageRect];
                [provider missedThumbnailImageInView:self rect:imageRect atIndex: index];
	    }
	}
    }
}

- (BOOL) isOpaque;
{
    return YES;
}

- (BOOL) isFlipped;
{
    return YES;
}


// Public interface

- (void)scrollSelectionToVisible;
{
    int			row;
    int			thumbnailIndex, thumbnailCount;
    NSRect		selectionRect = NSZeroRect;

    thumbnailCount = [provider thumbnailCount];
    for (thumbnailIndex = 0; thumbnailIndex < thumbnailCount;
         thumbnailIndex++) {
        NSRect		newRect, bounds;
	
        if (![provider isThumbnailSelectedAtIndex: thumbnailIndex])
            continue;
	
        row = thumbnailIndex / columnCount;
        bounds = [self bounds];
        newRect = NSMakeRect(bounds.origin.x, row*cellSize.height,
                             bounds.size.width, cellSize.height);
        selectionRect = NSUnionRect(newRect, selectionRect);
    }

    [self setNeedsDisplay:YES]; // If selection has changed, we need to redisplay
    [self scrollRectToVisible:selectionRect];
}

- (void)setThumbnailProvider:(NSObject <OAThumbnailProvider> *) newThumbnailsProvider;
{
    if (provider == newThumbnailsProvider)
	return;

    [provider autorelease];
    provider = [newThumbnailsProvider retain];

    [self sizeToFit];  
    [self scrollSelectionToVisible];
    [self setNeedsDisplay:YES];
}

- (NSObject <OAThumbnailProvider> *)thumbnailProvider;
{
    return provider;
}

- (void)sizeToFit;
{
    maximumThumbnailSize = NSMakeSize(-1,-1);
    [self setFrameSize:NSMakeSize(0, 0)];
}

- (void)setThumbnailsNumbered:(BOOL)newThumbnailsAreNumbered;
{
    thumbnailsAreNumbered = newThumbnailsAreNumbered;
    [self sizeToFit];
}
- (BOOL)thumbnailsAreNumbered;
{
    return thumbnailsAreNumbered;
}


- (void)drawMissingThumbnailRect:(NSRect)rect;
{
    CGContextRef context;

    [[NSColor whiteColor] set];
    NSRectFill(rect);
    [[NSColor darkGrayColor] set];
    NSFrameRect(rect);

    context = [[NSGraphicsContext currentContext] graphicsPort];

    CGContextBeginPath(context);
    CGContextMoveToPoint(context, NSMinX(rect), NSMinY(rect));
    CGContextAddLineToPoint(context, NSMaxX(rect), NSMaxY(rect));
    CGContextMoveToPoint(context, NSMinX(rect), NSMaxY(rect));
    CGContextAddLineToPoint(context, NSMaxX(rect), NSMinY(rect));
    CGContextStrokePath(context);
}

// Private interface

- (void)getMaximumThumbnailSize;
{
    unsigned int index, count;

    if (maximumThumbnailSize.width >= 0)
	return;

    maximumThumbnailSize = NSMakeSize(-1.0, -1.0);

    count = [provider thumbnailCount];
    for (index=0; index < count; index++) {
	NSSize				size;
	
        size = [provider thumbnailSizeAtIndex: index];
	maximumThumbnailSize.width = MAX(maximumThumbnailSize.width,
	                                 size.width);
	maximumThumbnailSize.height = MAX(maximumThumbnailSize.height,
	                                 size.height);
    }
}

// Responder subclassed

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (void)mouseDown:(NSEvent *)event;
{
    NSPoint mousePoint;
    unsigned int row, column, index;

    mousePoint = [self convertPoint:[event locationInWindow] fromView:nil];
    row = MAX(0, mousePoint.y / cellSize.height);
    column = (mousePoint.x - horizontalMargin/2)
                   / (horizontalMargin + cellSize.width);
    column = MIN(MAX(0U, column), columnCount-1);
    
    index = row * columnCount + column;
    if (index >= [provider thumbnailCount])
	return;

    [provider thumbnailWasSelected:event atIndex: index];
    [self setNeedsDisplay:YES];
}

@end
