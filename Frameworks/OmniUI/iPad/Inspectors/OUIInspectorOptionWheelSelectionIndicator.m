// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
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

#pragma mark -
#pragma mark UIView

- (void)drawRect:(CGRect)rect;
{
    [_color set];
    
    CGRect bounds = self.bounds;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSaveGState(ctx);
    {
        CGColorRef strokeColor = [OQMakeUIColor(kOUIInspectorWellLightBorderGradientStartColor) CGColor];
        CGContextSetStrokeColorWithColor(ctx, strokeColor);
        
        CGContextMoveToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds) + 4);
        CGContextAddLineToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - 4);
        CGContextMoveToPoint(ctx, CGRectGetMaxX(bounds), CGRectGetMinY(bounds) + 4);
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds) - 4);
        
        CGContextDrawPath(ctx, kCGPathStroke);
    }
    CGContextRestoreGState(ctx);
}

@end
