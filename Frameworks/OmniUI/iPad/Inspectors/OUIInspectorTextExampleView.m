// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorTextExampleView.h"

#import <OmniUI/OUITextLayout.h>
#import <OmniUI/OUIDrawing.h>
#import <OmniUI/OUIGradientView.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniQuartz/OQColor.h>

RCS_ID("$Id$");

@implementation OUIInspectorTextExampleView

@synthesize styleBackgroundColor = _styleBackgroundColor;
@synthesize attributedString = _attributedString;

static id _commonInit(OUIInspectorTextExampleView *self)
{
    self.opaque = YES; // we fill with the opaque background from OUIDrawTransparentColorBackground() if needed.
    self->_bottomGradientView = [[OUIGradientView horizontalShadow:NO/*top-to-bottom*/] retain];
    [self addSubview:self->_bottomGradientView];
    
    return self;
}

- initWithFrame:(CGRect)frame;
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

- (void)dealloc;
{
    [_styleBackgroundColor release];
    [_textLayout release];
    [_attributedString release];
    [_bottomGradientView release];
    [super dealloc];
}

- (void)setStyleBackgroundColor:(OQColor *)color;
{
    if (OFISEQUAL(_styleBackgroundColor, color))
        return;
    [_styleBackgroundColor release];
    _styleBackgroundColor = [color copy];
    
    [self setNeedsDisplay];
}

- (void)setAttributedString:(NSAttributedString *)attributedString;
{
    if (OFISEQUAL(_attributedString, attributedString))
        return;
    
    [_attributedString release];
    _attributedString = [attributedString copy];
    
    [_textLayout release];
    _textLayout = [[OUITextLayout alloc] initWithAttributedString:_attributedString constraints:CGSizeMake(OUITextLayoutUnlimitedSize, OUITextLayoutUnlimitedSize)];
    
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UIView (OUIExtensions)

- (UIEdgeInsets)borderEdgeInsets;
{
    // Border all the way to the edge.
    return UIEdgeInsetsZero;
}

#pragma mark -
#pragma mark UIView subclass

- (void)layoutSubviews;
{
    CGRect shadowFrame, dummy;
    CGRectDivide(self.bounds, &shadowFrame, &dummy, 4, CGRectMaxYEdge);
    _bottomGradientView.frame = shadowFrame;
}

- (void)drawRect:(CGRect)rect;
{
    OBPRECONDITION(_styleBackgroundColor);
    OBPRECONDITION(_textLayout);
    
    CGRect bounds = self.bounds;
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // TODO: Non component-based background colors (patterns, named colors).
    CGFloat backgroundAlpha = [_styleBackgroundColor alphaComponent];
    
    if (backgroundAlpha == 0) {
        // Clear -- text atop a fully checkerboarded background looks horrible.
        [[UIColor whiteColor] set];
        UIRectFill(rect);
    } else {
        if (backgroundAlpha < 1.0) {
            OUIDrawPatternBackground(ctx, @"OUITransparencyCheckerboardBackground-24", bounds, CGSizeZero);
        }
    
        [[_styleBackgroundColor toColor] set];
        UIRectFillUsingBlendMode(bounds, kCGBlendModeNormal);
    }
    
    CGSize usedSize = _textLayout.usedSize;
    CGRect textRect = OQCenteredIntegralRectInRect(self.bounds, usedSize);
        
    // Make sure that the origin of the text doesn't go off the edge when it gets too big.
    textRect.origin.x = MAX(textRect.origin.x, bounds.origin.x);
    textRect.origin.y = MAX(textRect.origin.y, bounds.origin.y);
    
    [_textLayout drawFlippedInContext:ctx bounds:textRect];
}

@end

