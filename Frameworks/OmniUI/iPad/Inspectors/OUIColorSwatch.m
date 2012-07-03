// Copyright 2010-2012 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIColorSwatch.h"

#import <OmniUI/OUIInspectorWell.h>
#import <OmniQuartz/OQColor.h>
#import <OmniQuartz/OQDrawing.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIColorSwatch
{
    OQColor *_color;
    BOOL _showNavigationArrow;
}

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

static UIImage *_selectedImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorInspectorSelected.png"];
    OBASSERT(image);
    return image;
}

static UIImage *_colorPickerImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorPickerSwatch.png"];
    OBASSERT(image);
    return image;
}

+ (CGSize)swatchSize;
{
    // Hacky: kOUIInspectorWellHeight includes 1 for the highlight on the bottom. Add code to superclass to deal with this?
    // TODO: This used to have the top edge of the border 1px off the edge of the pre-computed frame. Still need that?
    return CGSizeMake(kOUIInspectorWellHeight - 1, kOUIInspectorWellHeight);
}

// Caller expected to set up the target/action on this.
+ (OUIColorSwatch *)navigateToColorPickerSwatch;
{
    OUIColorSwatch *swatch = [[[self alloc] initWithFrame:CGRectZero] autorelease];
    swatch.showNavigationArrow = YES;
    return swatch;
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

@synthesize showNavigationArrow = _showNavigationArrow;
- (void)setShowNavigationArrow:(BOOL)showNavigationArrow;
{
    if (_showNavigationArrow == showNavigationArrow)
        return;
    _showNavigationArrow = showNavigationArrow;
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
    return [[self class] swatchSize];
}

- (void)drawRect:(CGRect)rect;
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    OUIInspectorWellDraw(ctx, self.bounds,
                         OUIInspectorWellCornerTypeSmallRadius, OUIInspectorWellBorderTypeDark, YES/*innerShadow*/,
                         ^(CGRect interiorRect){
        if (_color) {
            if ([_color alphaComponent] < 1.0) {
                CGContextSetInterpolationQuality(ctx, kCGInterpolationNone); // Don't blur the edges between the checkers if this does happen to get stretched.
                [_translucentBackgroundImage() drawInRect:interiorRect];
            }
            
            [_color.toColor set];
            CGContextFillRect(ctx, interiorRect);
        } else if (_showNavigationArrow) {
            [_colorPickerImage() drawInRect:interiorRect];
        } else {
            [_nilColorImage() drawInRect:interiorRect];
        }
        
        if (self.selected && !_showNavigationArrow) {
            OQFlipVerticallyInRect(ctx, interiorRect);
            OQDrawImageCenteredInRect(ctx, _selectedImage(), interiorRect);
        }
        
        if (_showNavigationArrow) {
            CGRect swatchRect = interiorRect;
            
            // If we are "wide", then stick the navigation error on the right edge, matching the navigation arrow in OUIInspectorTextWells.
            if (interiorRect.size.width - interiorRect.size.height > 4) {
                CGFloat inset = 32;
                CGRect dummy;
                CGRectDivide(interiorRect, &swatchRect, &dummy, inset, CGRectMaxXEdge);
            }
            
            OQDrawImageCenteredInRect(ctx, _navigationArrowImage(), swatchRect);
        }
    });
}

@end

