// Copyright 2010-2011 The Omni Group. All rights reserved.
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
static UIImage *SelectedArrow = nil;

static UIImage *_navigationArrowImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorSwatchNavigationArrow.png"];
    OBASSERT(image);
    return image;
}

static UIImage *_translucentBackgroundImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorSwatchTranslucentBackground.png"];
    OBASSERT(image);
    return image;
}

static UIImage *_nilColorImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorSwatchNone.png"];
    OBASSERT(image);
    return image;
}

+ (void)initialize;
{
    OBINITIALIZE;
    
    SwatchFrame = [[[UIImage imageNamed:@"OUIColorSwatchFrame.png"] stretchableImageWithLeftCapWidth:6 topCapHeight:5] retain];
    OBASSERT(SwatchFrame);
        
    SelectedArrow = [[UIImage imageNamed:@"OUIColorInspectorSelected.png"] retain];
    OBASSERT(SelectedArrow);
}

+ (CGSize)swatchSize;
{
    return [SwatchFrame size];
}

// Caller expected to set up the target/action on this.
+ (UIButton *)navigateToColorPickerButton;
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.opaque = NO;
    button.showsTouchWhenHighlighted = YES;
    
    UIImage *backgroundImage = [UIImage imageNamed:@"OUIColorPickerSwatch.png"];
    OBASSERT(backgroundImage);
    [button setBackgroundImage:backgroundImage forState:UIControlStateNormal];
    
    [button setImage:_navigationArrowImage() forState:UIControlStateNormal];
    
    return button;
}

static id _commonInit(OUIColorSwatch *self)
{
    self.opaque = NO;
    self.clearsContextBeforeDrawing = YES;
    self.showsTouchWhenHighlighted = YES;

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
    
    _color = [color retain];

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

@synthesize singleSwatch = _singleSwatch;
- (void)setSingleSwatch:(BOOL)singleSwatch;
{
    if (_singleSwatch == singleSwatch)
        return;
    _singleSwatch = singleSwatch;
    [self setNeedsDisplay];
}

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

static void _appendSwatchPath(CGContextRef ctx, CGRect bounds)
{
    OQAppendRoundedRect(ctx, CGRectInset(bounds, 1, 2), 4);
}

static void _drawSwatchImage(CGContextRef ctx, CGRect bounds, UIImage *image)
{
    CGContextSaveGState(ctx);
    {
        _appendSwatchPath(ctx, bounds);
        CGContextClip(ctx);
        [image drawInRect:bounds];
    }
    CGContextRestoreGState(ctx);
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    
    if (_color) {
        if ([_color alphaComponent] < 1.0) {
            _drawSwatchImage(ctx, bounds, _translucentBackgroundImage());
        }

        [_color.toColor set];
        _appendSwatchPath(ctx, bounds);
        CGContextFillPath(ctx);
        [SwatchFrame drawInRect:bounds];
    } else {
        _drawSwatchImage(ctx, bounds, _nilColorImage());
        [SwatchFrame drawInRect:bounds];
    }
    
    if (self.selected && !_singleSwatch) {
        OQFlipVerticallyInRect(ctx, bounds);
        OQDrawImageCenteredInRect(ctx, SelectedArrow, bounds);
    }

    if (_singleSwatch) {
        // Hard coded to match the navigation arrow in OUIInspectorTextWells.
        CGFloat inset = 32;
        
        CGRect swatchRect, dummy;
        CGRectDivide(bounds, &swatchRect, &dummy, inset, CGRectMaxXEdge);
        OQDrawImageCenteredInRect(ctx, _navigationArrowImage(), swatchRect);
    }
}

@end

