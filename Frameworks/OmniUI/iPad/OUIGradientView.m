// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIGradientView.h>

#import <QuartzCore/CAGradientLayer.h>
#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIGradientView

+ (CGFloat)dropShadowThickness;
{
    return kOUIShadowEdgeThickness;
}

+ (OUIGradientView *)horizontalShadow:(BOOL)bottomToTop NS_RETURNS_RETAINED;
{
    OUIGradientView *instance = [[self alloc] init];
    
    UIColor *bottomColor = [UIColor colorWithWhite:0.0 alpha:kOUIShadowEdgeMaximumAlpha];
    UIColor *topColor = [UIColor colorWithWhite:0.0 alpha:0.0];
    
    if (!bottomToTop)
        SWAP(bottomColor, topColor);
    
    [instance fadeVerticallyFromColor:bottomColor toColor:topColor];
    return instance;
}

+ (OUIGradientView *)verticalShadow:(BOOL)leftToRight NS_RETURNS_RETAINED;
{
    OUIGradientView *instance = [[self alloc] init];
    
    UIColor *leftColor = [UIColor colorWithWhite:0.0 alpha:kOUIShadowEdgeMaximumAlpha];
    UIColor *rightColor = [UIColor colorWithWhite:0.0 alpha:0.0];
    
    if (!leftToRight)
        SWAP(leftColor, rightColor);
    
    [instance fadeHorizontallyFromColor:leftColor toColor:rightColor];
    return instance;
}

static id _commonInit(OUIGradientView *self)
{
    self.userInteractionEnabled = NO;
    return self;
}

- (id)initWithFrame:(CGRect)frame;
{
    if (!(self = [super initWithFrame:frame]))
        return nil;
    return _commonInit(self);
}

- (id)initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    return _commonInit(self);
}

- (void)fadeHorizontallyFromColor:(UIColor *)leftColor toColor:(UIColor *)rightColor;
{
    OBPRECONDITION(leftColor);
    OBPRECONDITION(rightColor);
    
    // Needed, at least, for transitioning between the highlighted state when in row-marking mode.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    {
        CAGradientLayer *layer = (CAGradientLayer *)self.layer;
        layer.colors = [NSArray arrayWithObjects:(id)[leftColor CGColor], (id)[rightColor CGColor], nil];
        
        layer.startPoint = CGPointMake(0.0, 0.5);
        layer.endPoint = CGPointMake(1.0, 0.5);
        layer.type = kCAGradientLayerAxial;
    }
    [CATransaction commit];
}

- (void)fadeVerticallyFromColor:(UIColor *)bottomColor toColor:(UIColor *)topColor; // where 'bottom' == min y
{
    OBPRECONDITION(bottomColor);
    OBPRECONDITION(topColor);
    
    // Needed, at least, for transitioning between the highlighted state when in row-marking mode.
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    {
        CAGradientLayer *layer = (CAGradientLayer *)self.layer;
        layer.colors = [NSArray arrayWithObjects:(id)[bottomColor CGColor], (id)[topColor CGColor], nil];
        
        layer.startPoint = CGPointMake(0.5, 0.0);
        layer.endPoint = CGPointMake(0.5, 1.0);
        layer.type = kCAGradientLayerAxial;
    }
    [CATransaction commit];
}

#pragma mark -
#pragma mark UIView subclass

+ (Class)layerClass;
{
    return [CAGradientLayer class];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
{
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self)
        return nil;
    return hitView;
}

@end
