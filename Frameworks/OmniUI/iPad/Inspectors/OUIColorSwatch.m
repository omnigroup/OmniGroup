// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIColorSwatch.h"

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspectorWell.h>
#import <OmniAppKit/OAColor.h>
#import <OmniQuartz/OQDrawing.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

@implementation OUIColorSwatch
{
    OAColor *_color;
    BOOL _showNavigationArrow;
}

static UIImage *_navigationArrowImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorSwatchNavigationArrow" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    return image;
}

static UIImage *_translucentBackgroundImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorSwatchTranslucentBackground" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    return image;
}

static UIImage *_selectedImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorInspectorSelected" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    return image;
}

static UIImage *_colorPickerImage(void)
{
    UIImage *image = [UIImage imageNamed:@"OUIColorPickerSwatch" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil];
    OBASSERT(image);
    return image;
}

static UIColor *_borderColor(void)
{
    return [UIColor colorWithWhite:0.65f alpha:0.3f];
}

+ (CGSize)swatchSize;
{
    return CGSizeMake(kOUIInspectorWellHeight, kOUIInspectorWellHeight);
}

// Caller expected to set up the target/action on this.
+ (OUIColorSwatch *)navigateToColorPickerSwatch;
{
    OUIColorSwatch *swatch = [[self alloc] initWithFrame:CGRectZero];
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

- initWithColor:(OAColor *)color;
{
    if (!(self = [self initWithFrame:CGRectZero]))
        return nil;
    
    _color = color;

    return self;
}

#pragma mark - OUIColorValue

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
    CGRect bounds = self.bounds;
    bounds = CGRectInset(bounds, 2.0f, 2.0f); // Inset a bit to give some more space between us and our neighbors. (Would probably be better to accomplish this by actually positioning the color swatches further apart.)
    CGRect interiorRect;
    CGFloat cornerRadius = 4.0f;
    UIBezierPath *path;
    
    if (self.selected) {
        // If selected, inset a little bit so we don't overwhelm / look larger our neighbors (but inset enough that it doesn't look like a mistake)
        interiorRect = CGRectInset(bounds, 2.0f, 2.0f);
    } else {
        // If not selected, the fill is inset from an outer border
        interiorRect = CGRectInset(bounds, 6.0f, 6.0f);
    }
    
    // If we're not selected, draw an outer border
    if (!self.selected) {
        CGRect borderRect = CGRectInset(bounds, 0.5f, 0.5f);
        [_borderColor() set];
        path = [UIBezierPath bezierPathWithRoundedRect:borderRect cornerRadius:cornerRadius];
        [path stroke];
    }
    
    // Draw the fill
    path = [UIBezierPath bezierPathWithRoundedRect:interiorRect cornerRadius:cornerRadius];
    [path addClip];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (_color != nil) {
        // If we have transparency, draw that
        if ([_color alphaComponent] < 1.0) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationNone); // Don't blur the edges between the checkers if this does happen to get stretched.
            [_translucentBackgroundImage() drawInRect:interiorRect];
        }
        
        [_color set];
        [path fill];
        
    } else if (_showNavigationArrow) {
        OBASSERT_NOT_REACHED("I don't think this really fits anymore, but I'm not positive if I can remove it");
        [_colorPickerImage() drawInRect:interiorRect];
        
    } else {
        [_borderColor() set];
        path = [UIBezierPath bezierPath];
        CGRect noColorRect = CGRectInset(interiorRect, 5.0f, 5.0f);
        [path moveToPoint:(CGPoint){ .x = MAX(0.0f, CGRectGetMinX(noColorRect)), .y = MAX(0.0, CGRectGetMaxY(noColorRect)), }];
        [path addLineToPoint:(CGPoint){ .x = CGRectGetMaxX(noColorRect), .y = CGRectGetMinY(noColorRect), }];
        [path stroke];
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
}

@end

