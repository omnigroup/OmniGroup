// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIColorSwatch.h"

#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>

RCS_ID("$Id$");

@implementation OUIColorSwatch

static UIImage *SwatchFrame = nil;
static UIImage *SwatchTranslucentBackground = nil;
static UIImage *ColorPickerSwatch = nil;
static UIImage *NavigationArrow = nil;
static UIImage *SelectedArrow = nil;

+ (void)initialize;
{
    OBINITIALIZE;
    
    SwatchFrame = [[UIImage imageNamed:@"OUIColorSwatchFrame.png"] retain];
    OBASSERT(SwatchFrame);
    
    SwatchTranslucentBackground = [[UIImage imageNamed:@"OUIColorSwatchTranslucentBackground.png"] retain];
    OBASSERT(SwatchTranslucentBackground);
    
    ColorPickerSwatch = [[UIImage imageNamed:@"OUIColorPickerSwatch.png"] retain];
    OBASSERT(ColorPickerSwatch);
    
    NavigationArrow = [[UIImage imageNamed:@"OUINavigationArrow.png"] retain];
    OBASSERT(NavigationArrow);

    SelectedArrow = [[UIImage imageNamed:@"OUIColorInspectorSelected.png"] retain];
    OBASSERT(SelectedArrow);
}

+ (CGSize)swatchSize;
{
    return [SwatchFrame size];
}

static id _commonInit(OUIColorSwatch *self)
{
    self.opaque = NO;
    self.clearsContextBeforeDrawing = YES;
    
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

- initWithColor:(OQColor *)color;
{
    if (!(self = [self initWithFrame:CGRectZero]))
        return nil;
    
    self.showsTouchWhenHighlighted = YES;
    
    _color = [color retain];

    // The navigation swatch has a nil color and shouldn't send -changeColor:
    if (_color)
        [self addTarget:nil action:@selector(changeColor:) forControlEvents:UIControlEventTouchDown];

    return self;
}

- (void)dealloc;
{
    [_color release];
    [super dealloc];
}

#pragma mark -
#pragma mark OUIColorValue

@synthesize color = _color;

- (BOOL)isContinuousColorChange;
{
    return NO;
}

#pragma mark -
#pragma mark UIView

- (CGSize)sizeThatFits:(CGSize)size;
{
    return [SwatchFrame size];
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    
    if (_color) {
        if ([_color alphaComponent] < 1.0) {
            CGContextSaveGState(ctx);
            {
                OQAppendRoundedRect(ctx, CGRectInset(bounds, 0.5, 0.5), 3);
                CGContextClip(ctx);
                [SwatchTranslucentBackground drawInRect:bounds];
            }
            CGContextRestoreGState(ctx);
        }

        [_color.toColor set];
        OQAppendRoundedRect(ctx, CGRectInset(bounds, 0.5, 0.5), 3);
        CGContextFillPath(ctx);
        [SwatchFrame drawInRect:bounds];
        
        if (self.selected) {
            OQFlipVerticallyInRect(ctx, bounds);
            OQDrawImageCenteredInRect(ctx, [SelectedArrow CGImage], bounds);
        }
    } else {
        [ColorPickerSwatch drawInRect:bounds];
        OQDrawImageCenteredInRect(ctx, [NavigationArrow CGImage], bounds);
    }
}

@end

