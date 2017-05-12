// Copyright 2010-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <OmniAppKit/OABoxSeparator.h>
#import <AppKit/NSColor.h>

#import <OmniBase/OmniBase.h>
#import <tgmath.h>

RCS_ID("$Id$")

@implementation OABoxSeparator

- (id)init;
{
    if (!(self = [super init]))
        return nil;
    [self _setDefaultColors];
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder;
{
    if (!(self = [super initWithCoder:aDecoder]))
        return nil;
    [self _setDefaultColors];
    return self;
}

- (id)initWithFrame:(NSRect)frameRect;
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;
    [self _setDefaultColors];
    return self;
}

#pragma mark - Private methods

- (void)_setDefaultColors;
{
    self.boxType = NSBoxSeparator;
    self.lineColor = [NSColor colorWithWhite:0.87f alpha:1.0f];
    self.backgroundColor = [NSColor whiteColor];
}

#pragma mark - NSView subclass

- (void)drawRect:(NSRect)rect
{
    if ([self boxType] != NSBoxSeparator) {
	OBASSERT_NOT_REACHED("This subclass can only draw separators.");
	[super drawRect:rect];
        return;
    }
    
    [self drawLineInRect:rect];
    
    if (self.backgroundStyle == NSBackgroundStyleRaised) {
        [self drawBackgroundInRect:rect];
    }
}

#pragma mark - Public API

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle;
{
    if (_backgroundStyle == backgroundStyle)
        return;
    _backgroundStyle = backgroundStyle;
    [self setNeedsDisplay:YES];
}

- (NSRect)separatorRect;
{
    NSRect bounds = [self bounds];
    
    // If we have an even frame height, we want to shift our 1pt-tall stroke to an integral point boundary, rather than leaving it on a half-point (thus being blurry on non-retina displays) or expanding it to two points (which is what NSIntegralRect would do).
    // We want to perform the same half-point shift in retina, even though drawing a 1pt line at a half-point coordinate would result in pixel-aligned drawing. If we did that, the line would jump around if the window was dragged between a retina and non-retina display.
    // We arbitrarily choose to "round down" the coordinates _in our own coordinate space_, NOT in the coordinate space of the current graphics context. This ensures consistency whether or not we are the currently focused view.
    
    CGFloat y = floor(bounds.size.height / 2);
    NSRect separatorRect = (NSRect){
        .origin = {.x = NSMinX(bounds), .y = y},
        .size = {.width = NSWidth(bounds), .height = 1}
    };
    
    return separatorRect;
}

- (NSRect)embossRect;
{
    // If the background style is raised, then we want to draw a highlight line 1pt below our regular drawing.
    // This line should always be drawn _VISUALLY_ below, so we _do_ want to pay attention to the current context's flippedness here.
    
    NSRect embossRect = self.separatorRect;
    if ([[NSGraphicsContext currentContext] isFlipped])
        embossRect = NSOffsetRect(embossRect, 0, 1);
    else
        embossRect = NSOffsetRect(embossRect, 0, -1);
    
    return embossRect;
}

- (void)drawLineInRect:(NSRect)rect;
{
    [[self lineColor] set];
    NSRectFill(self.separatorRect);
}

- (void)drawBackgroundInRect:(NSRect)rect;
{
    [[self backgroundColor] set];
    NSRectFill(self.embossRect);
}

@end
