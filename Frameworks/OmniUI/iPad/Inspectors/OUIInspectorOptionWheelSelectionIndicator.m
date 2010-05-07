// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorOptionWheelSelectionIndicator.h>
#import <UIKit/UIKit.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIInspectorOptionWheelSelectionIndicator

static const CGFloat kIndicatorSize = 20;
static const CGFloat kShadowRadius = 1;

- init;
{
    CGRect frame = CGRectMake(0, 0, kIndicatorSize, kIndicatorSize/2 + kShadowRadius);
    
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

@synthesize color = _color;
- (void)setColor:(UIColor *)color;
{
    if ([_color isEqual:color])
        return;
    
    [_color release];
    _color = [color retain];
    [self setNeedsDisplay];
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
        CGContextSetShadow(ctx, CGSizeMake(0, kShadowRadius), kShadowRadius);
        
        CGContextMoveToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
        CGContextAddLineToPoint(ctx, CGRectGetMaxX(bounds), CGRectGetMinY(bounds));
        CGContextAddLineToPoint(ctx, CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - kShadowRadius);
        CGContextAddLineToPoint(ctx, CGRectGetMinX(bounds), CGRectGetMinY(bounds));
        
        CGContextFillPath(ctx);
    }
    CGContextRestoreGState(ctx);
}

@end
