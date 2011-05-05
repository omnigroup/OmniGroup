// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorOptionWheelSelectionIndicator.h>

#import "OUIInspectorBackgroundView.h"
#import <OmniBase/OmniBase.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIInspectorOptionWheelSelectionIndicator

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

- (void)dealloc;
{
    [_color release];
    [super dealloc];
}

- (void)updateColor;
{
    OUIInspectorBackgroundView *topBackgroundView = nil;
    
    UIView *ancestor = self;
    while (ancestor) {
        if ([ancestor isKindOfClass:[OUIInspectorBackgroundView class]])
            topBackgroundView = (OUIInspectorBackgroundView *)ancestor;
        ancestor = ancestor.superview;
    }
    
    UIColor *color = [topBackgroundView colorForYPosition:CGRectGetMinY(self.bounds) inView:self];
    if (!color)
        color = [UIColor whiteColor];
    
    if (![_color isEqual:color]) {
        [_color release];
        _color = [color retain];
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
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();

        CGFloat shadowComponents[] = {kOUIInspectorWellInnerShadowGrayAlpha.v, kOUIInspectorWellInnerShadowGrayAlpha.a};
        CGColorRef shadowColor = CGColorCreate(colorSpace, shadowComponents);
        
        CGFloat strokeComponents[] = {kOUIInspectorWellInnerShadowGrayAlpha.v, kOUIInspectorWellInnerShadowGrayAlpha.a};
        CGColorRef strokeColor = CGColorCreate(colorSpace, strokeComponents);
        
        CGColorSpaceRelease(colorSpace);
        
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), kOUIInspectorWellInnerShadowBlur, shadowColor);
        CGColorRelease(shadowColor);
        
        CGContextSetStrokeColorWithColor(ctx, strokeColor);
        CGColorRelease(strokeColor);

        CGContextMoveToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
        CGContextAddLineToPoint(ctx, CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - kOUIInspectorWellInnerShadowBlur - 0.5);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(bounds), CGRectGetMinY(bounds));
        //CGContextAddLineToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
        
        CGContextDrawPath(ctx, kCGPathFillStroke);
    }
    CGContextRestoreGState(ctx);
}

#pragma mark -
#pragma mark UIView (OUIInspectorBackgroundView)

- (void)containingInspectorBackgroundViewColorsChanged;
{
    [super containingInspectorBackgroundViewColorsChanged];
    
    [self updateColor];
}

@end
