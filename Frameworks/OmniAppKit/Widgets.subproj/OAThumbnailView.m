// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
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
#import <OmniBase/macros.h>
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
	labelFont = [NSFont systemFontOfSize:LABEL_FONT_SIZE];
}

- initWithFrame:(NSRect)aFrame;
{
    aFrame.size.height = 0;
    aFrame.size.width = 0;
    if (!(self = [super initWithFrame:aFrame]))
	return nil;

    maximumThumbnailSize = NSMakeSize(-1,-1);
    padding = NSMakeSize(8, 8);
    columnCount = 1;
    
    thumbnailsAreNumbered = YES;
    return self;
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

    columnCount = (NSUInteger)MAX(superBounds.size.width / cellSize.width, 1);
    rowCount = [provider thumbnailCount] / columnCount
        + (([provider thumbnailCount] % columnCount) ? 1 : 0);
    rowCount = MAX(1U, rowCount);
    horizontalMargin = (CGFloat)ceil((superBounds.size.width - columnCount * cellSize.width) / (columnCount+1));

    [super setFrameSize:NSMakeSize(NSWidth(superBounds), rowCount * cellSize.height)];
}

- (void)drawRect:(NSRect)dirtyRect
{
    // We calculate the start row/column by dividing and storing into unsigned.
    OBPRECONDITION(NSMinX(dirtyRect) >= 0);
    OBPRECONDITION(NSMinY(dirtyRect) >= 0);
    
    [[NSColor controlBackgroundColor] set];
    NSRectFill(dirtyRect);

    NSUInteger thumbnailCount = [provider thumbnailCount];
    
    NSUInteger startRow = (NSUInteger)NSMinY(dirtyRect) / cellSize.height;
    NSUInteger endRow = (NSUInteger)MIN(NSMaxY(dirtyRect) / cellSize.height, rowCount);

    for (NSUInteger row = startRow; row <= endRow; row++) {
	CGFloat y = cellSize.height * row;
	for (NSUInteger column = 0; column < columnCount; column++) {
	    NSUInteger thumbnailIndex = row * columnCount + column;
            if (thumbnailIndex >= thumbnailCount)
		return;
		
            NSSize imageSize = [provider thumbnailSizeAtIndex:thumbnailIndex];
    
	    CGFloat x = column * (horizontalMargin + cellSize.width) + horizontalMargin;

	    NSPoint point;
	    point.x = (CGFloat)ceil(x + padding.width + (maximumThumbnailSize.width - imageSize.width) / 2);
	    point.y = (CGFloat)ceil(y + cellSize.height - (padding.height + (maximumThumbnailSize.height - imageSize.height) / 2));
	    if (thumbnailsAreNumbered) {
		point.y -= LABEL_FONT_SIZE + LABEL_PADDING - LABEL_OVERLAP_WITH_BOTTOM_PADDING;
	    }

            NSRect imageRect = NSMakeRect(point.x, point.y - imageSize.height, imageSize.width, imageSize.height);

            BOOL isSelected = [provider isThumbnailSelectedAtIndex:thumbnailIndex];
	    if (isSelected) {
                NSRect rect = NSMakeRect(x, y, cellSize.width, cellSize.height);
                [self drawRoundedRect:rect cornerRadius:12 color:[NSColor selectedControlColor]];
	    }

            NSRect rect = NSInsetRect(imageRect, -1.0f, -1.0f);
	    [[NSColor controlColor] set];
            NSFrameRect(NSOffsetRect(rect, 2.0f, 2.0f));
	    [[NSColor controlShadowColor] set];
            NSFrameRect(NSOffsetRect(rect, 1.0f, 1.0f));
	    [[NSColor controlDarkShadowColor] set];
	    NSFrameRect(rect);
	    
	    if (thumbnailsAreNumbered) {
                rect = NSMakeRect(x, point.y + LABEL_PADDING + LABEL_OVERLAP_WITH_BOTTOM_PADDING - 3, cellSize.width, LABEL_FONT_SIZE);

		[[NSString stringWithFormat:@"%lu", thumbnailIndex + 1] drawWithFont:labelFont color:(isSelected ? [NSColor selectedControlTextColor] : [NSColor controlTextColor]) alignment:NSTextAlignmentCenter rectangle:rect];
	    }
	
            NSImage *image = [provider thumbnailImageAtIndex:thumbnailIndex];
	    if (image) {
                [image drawAtPoint:point fromRect:(NSRect){NSZeroPoint, [image size]} operation:NSCompositingOperationCopy fraction:1.0];
	    } else {
		[self drawMissingThumbnailRect:imageRect];
                [provider missedThumbnailImageInView:self rect:imageRect atIndex:thumbnailIndex];
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
    NSRect selectionRect = NSZeroRect;

    NSUInteger thumbnailCount = [provider thumbnailCount];
    for (NSUInteger thumbnailIndex = 0; thumbnailIndex < thumbnailCount; thumbnailIndex++) {
        if (![provider isThumbnailSelectedAtIndex: thumbnailIndex])
            continue;
	
        NSUInteger row = thumbnailIndex / columnCount;
        NSRect bounds = [self bounds];
        NSRect newRect = NSMakeRect(bounds.origin.x, row*cellSize.height, bounds.size.width, cellSize.height);
        selectionRect = NSUnionRect(newRect, selectionRect);
    }

    [self setNeedsDisplay:YES]; // If selection has changed, we need to redisplay
    [self scrollRectToVisible:selectionRect];
}

- (void)setThumbnailProvider:(NSObject <OAThumbnailProvider> *) newThumbnailsProvider;
{
    if (provider == newThumbnailsProvider)
	return;

    provider = newThumbnailsProvider;

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
    [[NSColor whiteColor] set];
    NSRectFill(rect);
    [[NSColor darkGrayColor] set];
    NSFrameRect(rect);

    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];

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
    if (maximumThumbnailSize.width >= 0)
	return;

    maximumThumbnailSize = NSMakeSize(-1.0f, -1.0f);

    NSUInteger thumbnailIndex, thumbnailCount = [provider thumbnailCount];
    for (thumbnailIndex = 0; thumbnailIndex < thumbnailCount; thumbnailIndex++) {
        NSSize size = [provider thumbnailSizeAtIndex:thumbnailIndex];
	maximumThumbnailSize.width = MAX(maximumThumbnailSize.width, size.width);
	maximumThumbnailSize.height = MAX(maximumThumbnailSize.height, size.height);
    }
}

// Responder subclassed

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent;
{
    return YES;
}

- (void)mouseDown:(NSEvent *)event;
{
    NSPoint mousePoint = [self convertPoint:[event locationInWindow] fromView:nil];
    NSUInteger row = MAX(0, mousePoint.y / cellSize.height);
    NSUInteger column = (mousePoint.x - horizontalMargin/2) / (horizontalMargin + cellSize.width);
    column = CLAMP(column, 0, columnCount-1);
    
    NSUInteger thumbnailIndex = row * columnCount + column;
    if (thumbnailIndex >= [provider thumbnailCount])
	return;

    [provider thumbnailWasSelected:event atIndex:thumbnailIndex];
    [self setNeedsDisplay:YES];
}

@end
