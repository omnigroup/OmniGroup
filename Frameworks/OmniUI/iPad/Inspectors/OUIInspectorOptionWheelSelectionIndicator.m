// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorOptionWheelSelectionIndicator.h>
#import <OmniUI/OUIInspector.h>

#import "OUIInspectorBackgroundView.h"
#import <OmniBase/OmniBase.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIInspectorOptionWheelSelectionIndicator
{
    UIColor *_color;
}

static const CGFloat kIndicatorSize = 20;

- init;
{
    CGRect frame = CGRectMake(0, 0, kIndicatorSize, kIndicatorSize/2 + kOUIInspectorWellInnerShadowBlur);
    
    if (!(self = [self initWithFrame:frame]))
        return nil;
    
    self.opaque = NO;
    self.clearsContextBeforeDrawing = YES;
    
    return self;
}

- (void)updateColor;
{
    UIView *topBackgroundView = nil;
    
    UIView *ancestor = self;
    while (ancestor) {
        if ([ancestor respondsToSelector:@selector(inspectorBackgroundViewColor)])
            topBackgroundView = ancestor;
        ancestor = ancestor.superview;
    }
    
    UIColor *color = [(id)topBackgroundView inspectorBackgroundViewColor];
    if (!color)
        color = [OUIInspector backgroundColor];
    
    if (![_color isEqual:color]) {
        _color = color;
        [self setNeedsDisplay];
    }
}

#pragma mark -
#pragma mark UIView

- (void)drawRect:(CGRect)rect;
{
    [_color set];
    
    CGRect bounds = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState(ctx);
    {
        CGColorRef shadowColor = [OQMakeUIColor(kOUIInspectorWellInnerShadowColor) CGColor];
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 0.5), kOUIInspectorWellInnerShadowBlur, shadowColor);
        
        CGContextMoveToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
        CGContextAddLineToPoint(ctx, CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - kOUIInspectorWellInnerShadowBlur);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(bounds), CGRectGetMinY(bounds));
        
        CGContextDrawPath(ctx, kCGPathFill);
    }
    CGContextRestoreGState(ctx);
    
    CGContextSaveGState(ctx);
    {
        CGColorRef strokeColor = [OQMakeUIColor(kOUIInspectorWellLightBorderGradientStartColor) CGColor];
        CGContextSetStrokeColorWithColor(ctx, strokeColor);
        
        CGContextMoveToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
        CGContextAddLineToPoint(ctx, CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - kOUIInspectorWellInnerShadowBlur);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(bounds), CGRectGetMinY(bounds));
        
        CGContextDrawPath(ctx, kCGPathStroke);
    }
    CGContextRestoreGState(ctx);
}

#pragma mark -
#pragma mark UIView (OUIInspectorBackgroundView)

- (void)containingInspectorBackgroundViewColorChanged;
{
    [super containingInspectorBackgroundViewColorChanged];
    
    [self updateColor];
}

@end
