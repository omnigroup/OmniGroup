// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIColorAttributeInspectorWell.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/UIView-OUIExtensions.h>

#import <OmniAppKit/OAColor.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");


@interface OUIColorAttributeInspectorWellButton : UIButton
@property (nonatomic,retain) OAColor *color;
@end

@implementation OUIColorAttributeInspectorWellButton

- (id)initWithFrame:(CGRect)frame;
{
    if ((self = [super initWithFrame:frame]) == nil) {
        return nil;
    }
    
    self.userInteractionEnabled = NO;
    
    return self;
}

#pragma mark - API and Properties

- (void)setColor:(OAColor *)color;
{
    if (OFISEQUAL(_color, color))
        return;
    _color = [color copy];
    
    [self setNeedsDisplay];
}

#pragma mark - UIView subclass

- (void)drawRect:(CGRect)rect;
{
    rect = CGRectInset(self.bounds, 0.5f, 0.5f);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:4.0f];
    [path addClip];
    
    // Draw the fill
    OAColor *fillColor = self.color;
    if (fillColor != nil) {
        // Transparency? Draw a checkerboard background
        if ([fillColor alphaComponent] < 1) {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
            
            CGFloat whiteFill[] = {1, 1};
            CGFloat grayFill[] = {0.85, 1};
            CGContextSetFillColorSpace(ctx, colorSpace);
            
            // Simple checkerboard
            CGContextSetFillColor(ctx, whiteFill);
            CGContextFillRect(ctx, rect);
            
            CGFloat midX = floor(CGRectGetMidX(rect));
            CGFloat midY = floor(CGRectGetMidY(rect));
            
            CGContextSetFillColor(ctx, grayFill);
            CGContextFillRect(ctx, CGRectMake(CGRectGetMinX(rect), CGRectGetMinY(rect), midX - CGRectGetMinX(rect), midY - CGRectGetMinY(rect)));
            CGContextFillRect(ctx, CGRectMake(midX, midY, CGRectGetMaxX(rect) - midX, CGRectGetMaxY(rect) - midY)); // lower right

            CGColorSpaceRelease(colorSpace);
        }

        // Draw the fill
        [fillColor set];
        [path fill];
    }
    
    // Draw the border
    [[UIColor systemGrayColor] set];
    [path stroke];
    
    // If necessary, draw the slash (same color as the border)
    if (fillColor == nil) {
        CGRect bounds = CGRectInset(self.bounds, 6.0f, 6.0f);
        path = [UIBezierPath bezierPath];
        [path moveToPoint:(CGPoint){ .x = CGRectGetMinX(bounds), .y = CGRectGetMaxY(bounds), }];
        [path addLineToPoint:(CGPoint){ .x = CGRectGetMaxX(bounds), .y = CGRectGetMinY(bounds), }];
        [path stroke];
        /* circle for circle-with-stroke-through-it
        CGRect ovalRect = CGRectInset(bounds, 3.0f, 3.0f);
        path = [UIBezierPath bezierPathWithOvalInRect:ovalRect];
        [path stroke];
        */
    }
}

@end


@implementation OUIColorAttributeInspectorWell

@synthesize color = _color;
@synthesize singleSwatch;

static id _commonInit(OUIColorAttributeInspectorWell *self)
{
    self.style = OUIInspectorTextWellStyleSeparateLabelAndText;
    self.singleSwatch = NO;
    
    CGRect contentsRect = CGRectMake(0, 0, 1, 30);
    self.rightView = [[OUIColorAttributeInspectorWellButton alloc] initWithFrame:contentsRect];
    [self setNeedsLayout];
    
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

- (void)setColor:(OAColor *)color;
{
    if (OFISEQUAL(_color, color))
        return;
    _color = [color copy];
    
    [(OUIColorAttributeInspectorWellButton *)self.rightView setColor:_color];

    [self setNeedsDisplay];
}

#pragma mark - UIView subclass

- (void)layoutSubviews;
{
    OBPRECONDITION(!self.leftView); // This won't do what you want.
    
    [super layoutSubviews];

    CGRect contentsRect = OUIInspectorWellInnerRect(self.bounds);
    contentsRect.size.width -= self.borderEdgeInsets.right; // To make this align better with other slices.
    contentsRect = CGRectIntegral(contentsRect);
    
    CGRect oldFrame = self.rightView.frame;
    
    // The right view is currently expected to have built-in padding.
    CGRect rightRect;
    CGRectDivide(contentsRect, &rightRect, &contentsRect, CGRectGetHeight(oldFrame), CGRectMaxXEdge);
    
    if (self.singleSwatch) {
        rightRect.origin.x = contentsRect.origin.x;
        rightRect.size.width = contentsRect.size.width + rightRect.size.width;
    }

    rightRect.size.height = CGRectGetHeight(oldFrame);
    rightRect.origin.y = CGRectGetMinY(contentsRect) + (contentsRect.size.height - rightRect.size.height)/2;

    self.rightView.frame = rightRect;
}

#pragma mark - OUIInspectorTextWell subclass

// <bug:///94098> (Remove -drawInteriorFillWithRect: on our controls and subclass in OmniGraffle)
- (void)drawInteriorFillWithRect:(CGRect)rect;
{
    [super drawInteriorFillWithRect:rect];

    if (_color) {
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        
        // well, i think i like a 35% opaque black line separating the main row from the color, followed by a 35% white line on top of the color
        
        static const CGFloat kLineWidth = 1;
        
        CGRect bounds = self.bounds;
        CGRect swatchRect, remainder;
        if (!self.singleSwatch) {
            CGRectDivide(bounds, &swatchRect, &remainder, CGRectGetHeight(bounds) - kLineWidth, CGRectMaxXEdge);
        } else {
            swatchRect = bounds;
        }

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();

        if ([_color alphaComponent] < 1) {            
            CGFloat whiteFill[] = {1, 1};
            CGFloat grayFill[] = {0.85, 1};
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
        
        if (!self.singleSwatch) {
            // Grid dividing the normal gradient background from the color swatch
            CGFloat leftLine[] = {0.0, 0.15};
            CGFloat rightLine[] = {1.0, 0.35};
            CGContextSetFillColorSpace(ctx, colorSpace);

            CGContextSetFillColor(ctx, leftLine);
            CGContextFillRect(ctx, CGRectMake(swatchRect.origin.x, swatchRect.origin.y, kLineWidth, swatchRect.size.height));
            
            CGContextSetFillColor(ctx, rightLine);
            CGContextFillRect(ctx, CGRectMake(swatchRect.origin.x + kLineWidth, swatchRect.origin.y, kLineWidth, swatchRect.size.height));
        }
        CGColorSpaceRelease(colorSpace);
    }
}

@end
