// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorAttributeInspectorWell.h>

#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@implementation OUIColorAttributeInspectorWell

@synthesize color = _color;

static id _commonInit(OUIColorAttributeInspectorWell *self)
{
    self.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    self.showNavigationArrow = YES;
    
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)dealloc
{
    [_color release];
    [super dealloc];
}

- (void)setColor:(OQColor *)color;
{
    if (OFISEQUAL(_color, color))
        return;
    [_color release];
    _color = [color copy];
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark OUIInspectorWell subclass

- (void)drawInteriorFillWithRect:(CGRect)rect;
{
    [super drawInteriorFillWithRect:rect];

    if (_color) {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        // well, i think i like a 35% opaque black line separating the main row from the color, followed by a 35% white line on top of the color
        
        static const CGFloat kLineWidth = 1;
        
        CGRect bounds = self.bounds;
        CGRect swatchRect, remainder;
        CGRectDivide(bounds, &swatchRect, &remainder, CGRectGetHeight(bounds) - kLineWidth, CGRectMaxXEdge);

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();

        if ([_color alphaComponent] < 1) {            
            float whiteFill[] = {1, 1};
            float grayFill[] = {0.85, 1};
            CGContextSetFillColorSpace(ctx, colorSpace);

            // Simple checkerboard
            CGContextSetFillColor(ctx, whiteFill);
            CGContextFillRect(ctx, swatchRect);
            
            CGFloat midX = floor(CGRectGetMidX(swatchRect));
            CGFloat midY = floor(CGRectGetMidY(swatchRect));
            
            CGContextSetFillColor(ctx, grayFill);
            CGContextFillRect(ctx, CGRectMake(CGRectGetMinX(swatchRect), CGRectGetMinY(swatchRect), midX - CGRectGetMinX(swatchRect), midY - CGRectGetMinY(swatchRect)));
            CGContextFillRect(ctx, CGRectMake(midX, midY, CGRectGetMaxX(swatchRect) - midX, CGRectGetMaxY(swatchRect) - midY)); // lower right
        }
        
        [_color set];
        CGContextFillRect(ctx, swatchRect);
        
        // Grid dividing the normal gradient background from the color swatch

        float leftLine[] = {0.0, 0.35};
        float rightLine[] = {1.0, 0.35};
        CGContextSetFillColorSpace(ctx, colorSpace);

        CGContextSetFillColor(ctx, leftLine);
        CGContextFillRect(ctx, CGRectMake(swatchRect.origin.x, swatchRect.origin.y, kLineWidth, swatchRect.size.height));
        
        CGContextSetFillColor(ctx, rightLine);
        CGContextFillRect(ctx, CGRectMake(swatchRect.origin.x + kLineWidth, swatchRect.origin.y, kLineWidth, swatchRect.size.height));
        CGColorSpaceRelease(colorSpace);
    }
}

@end
