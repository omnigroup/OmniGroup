// Copyright 2010-2011 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorWell.h>

#import <OmniUI/OUIDrawing.h>
#import <OmniQuartz/OQDrawing.h>
#import <OmniBase/OmniBase.h>
#import <UIKit/UIImage.h>

#import "OUIParameters.h"

RCS_ID("$Id$");

static CGColorRef BorderColor = NULL;
static CGColorRef InnerShadowColor = NULL;
static CGColorRef OuterShadowColor = NULL;

static void OUIInspectorWellInitialize(void)
{
    if (InnerShadowColor)
        return;
    
    CGColorSpaceRef grayColorSpace = CGColorSpaceCreateDeviceGray();
    
    CGFloat innerShadowComponents[] = {kOUIInspectorWellInnerShadowGrayAlpha.v, kOUIInspectorWellInnerShadowGrayAlpha.a};
    InnerShadowColor = CGColorCreate(grayColorSpace, innerShadowComponents);
    
    CGFloat outerShadowComponents[] = {kOUIInspectorWellOuterShadowGrayAlpha.v, kOUIInspectorWellOuterShadowGrayAlpha.a};
    OuterShadowColor = CGColorCreate(grayColorSpace, outerShadowComponents);
    
    CFRelease(grayColorSpace);
}

void OUIInspectorWellAddPath(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    OUIInspectorWellInitialize();
    
    CGRect borderRect = frame;
    borderRect.size.height -= 1; // room for shadow
    
    if (rounded) {
        OQAppendRoundedRect(ctx, borderRect, kOUIInspectorWellCornerRadius);
    } else {
        CGContextAddRect(ctx, borderRect);
    }
    
}

typedef struct {
    UIImage *rounded;
    UIImage *square;
} RoundSquareImageCache;

typedef void (*OUIDrawIntoImageCache)(CGContextRef, CGRect imageRect, BOOL rounded);

// The shadow we want has 1px offset, 0px radius and it just a shifted down path.
static void _OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect imageRect, BOOL rounded)
{
    CGRect shadowRect = imageRect;
    shadowRect.origin.y += 1;
    
    OUIInspectorWellAddPath(ctx, shadowRect, rounded);
    
    CGContextSetFillColorWithColor(ctx, OuterShadowColor);
    CGContextFillPath(ctx);
}

static UIImage *_OUIRoundSquareImageCachedImage(RoundSquareImageCache *cache, OUIDrawIntoImageCache draw, BOOL rounded)
{
    // Cache a 9-part image for rounded and not.
    OUIInspectorWellInitialize();
    
    UIImage **imagep = rounded ? &cache->rounded : &cache->square;
    
    if (!*imagep) {
        // Might be able to get away with just kOUIInspectorWellCornerRadius..
        CGFloat leftCap = kOUIInspectorWellCornerRadius + 1;
        CGFloat topCap = kOUIInspectorWellCornerRadius + 1;
        
        UIImage *image;
        CGSize imageSize = CGSizeMake(2*leftCap + 1, 2*topCap + 1);
        OUIGraphicsBeginImageContext(imageSize);
        {
            CGContextRef ctx = UIGraphicsGetCurrentContext();
            CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
            draw(ctx, imageRect, rounded);
            image = UIGraphicsGetImageFromCurrentImageContext();
        }
        OUIGraphicsEndImageContext();
        
        *imagep = [[image stretchableImageWithLeftCapWidth:leftCap topCapHeight:topCap] retain];
    }
    
    return *imagep;
}

void OUIInspectorWellDrawOuterShadow(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    static RoundSquareImageCache cache;
    UIImage *image = _OUIRoundSquareImageCachedImage(&cache, _OUIInspectorWellDrawOuterShadow, rounded);
    [image drawInRect:frame];
}

// Border and inner shadow
static void _OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect imageRect, BOOL rounded)
{
    OUIInspectorWellAddPath(ctx, imageRect, rounded);
    CGContextClip(ctx);
    CGContextBeginTransparencyLayer(ctx, NULL/*auxiliaryInfo*/);
    {
        OUIInspectorWellAddPath(ctx, CGRectInset(imageRect, 0.5, 0.5), rounded);
        CGContextAddRect(ctx, CGRectInset(imageRect, -20, -20));
        
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, kOUIInspectorWellInnerShadowOffset, kOUIInspectorWellInnerShadowBlur/*blur*/, InnerShadowColor);
        CGContextSetStrokeColorWithColor(ctx, [[UIColor clearColor] CGColor]);
        CGContextDrawPath(ctx, kCGPathEOFillStroke);
        CGContextRestoreGState(ctx);
        
        static CGGradientRef borderGradient = NULL;
        if (!borderGradient) {
            NSArray *colors = [NSArray arrayWithObjects:
                               (id)[[UIColor colorWithWhite:kOUIInspectorWellBorderGradientStartGrayAlpha.v alpha:kOUIInspectorWellBorderGradientStartGrayAlpha.a] CGColor],
                               (id)[[UIColor colorWithWhite:kOUIInspectorWellBorderGradientEndGrayAlpha.v alpha:kOUIInspectorWellBorderGradientEndGrayAlpha.a] CGColor],
                               nil
                               ];
            CGFloat locations[] = {0, 1.0};
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
            borderGradient = CGGradientCreateWithColors(colorSpace, (CFArrayRef)colors, locations);
            CGColorSpaceRelease(colorSpace);
        }    
        
        OUIInspectorWellAddPath(ctx, imageRect, rounded);
        OUIInspectorWellAddPath(ctx, CGRectInset(imageRect, 1.0, 1.0), rounded);
        
        CGPoint startPoint = imageRect.origin;
        CGPoint endPoint = CGPointMake(CGRectGetMinX(imageRect), CGRectGetMaxY(imageRect));
        CGContextSaveGState(ctx);
        CGContextEOClip(ctx);
        CGContextDrawLinearGradient(ctx, borderGradient, startPoint, endPoint, 0);
        CGContextRestoreGState(ctx);
    }
    CGContextEndTransparencyLayer(ctx);
}

void OUIInspectorWellDrawBorderAndInnerShadow(CGContextRef ctx, CGRect frame, BOOL rounded)
{
    static RoundSquareImageCache cache;
    UIImage *image = _OUIRoundSquareImageCachedImage(&cache, _OUIInspectorWellDrawBorderAndInnerShadow, rounded);
    [image drawInRect:frame];
}

CGRect OUIInspectorWellInnerRect(CGRect frame)
{
    CGRect rect = CGRectInset(frame, 1, 1); // border
    rect.size.height -= 1; // shadow
    return rect;
}

void OUIInspectorWellStrokePathWithBorderColor(CGContextRef ctx)
{
    OUIInspectorWellInitialize();

    CGContextSetStrokeColorWithColor(ctx, BorderColor);
    CGContextStrokePath(ctx);
}


@implementation OUIInspectorWell

static CGGradientRef NormalGradient = NULL;
static CGGradientRef HighlightedGradient = NULL;

+ (void)initialize;
{
    OBINITIALIZE;
    
    {
        UIColor *topColor = OQPlatformColorFromHSV(kOUIInspectorTextWellNormalGradientTopColor);
        UIColor *bottomColor = OQPlatformColorFromHSV(kOUIInspectorTextWellNormalGradientBottomColor);
        NormalGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
    {
        UIColor *topColor = OQPlatformColorFromHSV(kOUIInspectorTextWellHighlightedGradientTopColor);
        UIColor *bottomColor = OQPlatformColorFromHSV(kOUIInspectorTextWellHighlightedGradientBottomColor);
        HighlightedGradient = CGGradientCreateWithColors(NULL/*colorSpace*/, (CFArrayRef)[NSArray arrayWithObjects:(id)[topColor CGColor], (id)[bottomColor CGColor], nil], NULL);
    }
    
}

+ (CGFloat)fontSize;
{
    return [UIFont labelFontSize];
}

+ (UIFont *)italicFormatFont;
{
    return [UIFont fontWithName:@"HoeflerText-Italic" size:[self fontSize]];
}

+ (UIColor *)textColor;
{
    return OQPlatformColorFromHSV(kOUIInspectorTextWellTextColor);
}

+ (UIColor *)highlightedTextColor;
{
    return OQPlatformColorFromHSV(kOUIInspectorTextWellHighlightedTextColor);
}

@synthesize rounded = _rounded;
- (void)setRounded:(BOOL)rounded;
{
    if (rounded == _rounded)
        return;
    _rounded = rounded;
    [self setNeedsDisplay];
}

- (BOOL)shouldDrawHighlighted;
{
    return !self.enabled || (self.highlighted && ([self allControlEvents] != 0));
}

- (CGRect)contentsRect;
{
    CGRect contentsRect = self.bounds;
    
    static const CGFloat edgeInset = 8;
    
    UIEdgeInsets edgeInsets = UIEdgeInsetsMake(edgeInset, edgeInset, edgeInset, edgeInset);
    
    if (_showNavigationArrow) {
        CGRect arrowRect;
        CGRectDivide(contentsRect, &arrowRect, &contentsRect, CGRectGetHeight(contentsRect), CGRectMaxXEdge);

        edgeInsets.right = 0; // The image will have some built-in padding from centering w/in this rect. Don't chop off any more.
    }
    
    return UIEdgeInsetsInsetRect(contentsRect, edgeInsets);
}

- (UIImage *)navigationArrowImage;
{
    return [UIImage imageNamed:@"OUINavigationArrow.png"];
}

@synthesize showNavigationArrow = _showNavigationArrow;
- (void)setShowNavigationArrow:(BOOL)showNavigationArrow;
{
    if (_showNavigationArrow == showNavigationArrow)
        return;
    _showNavigationArrow = showNavigationArrow;
    [self setNeedsDisplay];
}

- (void)setNavigationTarget:(id)target action:(SEL)action;
{
    // OBPRECONDITION(target); nil OK for sending up the responder chain
    OBPRECONDITION(action);

    self.showNavigationArrow = YES;
    [self addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
}

- (UIColor *)textColor;
{
    return self.shouldDrawHighlighted ? [[self class] highlightedTextColor] : [[self class] textColor];
}

- (void)drawInteriorFillWithRect:(CGRect)rect; // Draws the interior gradient
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGGradientRef gradient = self.shouldDrawHighlighted ? HighlightedGradient : NormalGradient;
    CGContextDrawLinearGradient(ctx, gradient, rect.origin, CGPointMake(rect.origin.x, CGRectGetMaxY(rect)), 0);
}

- (CGFloat)buttonHeight;
// Graffle subclasses this in GPImageTextWell
{
    return kOUIInspectorWellHeight;
}

#pragma mark -
#pragma mark UIControl subclass

- (void)setHighlighted:(BOOL)highlighted;
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

#pragma mark -
#pragma mark UIView (OUIExtensions)

- (UIEdgeInsets)borderEdgeInsets
{
    // 1px white shadow at the bottom.
    return UIEdgeInsetsMake(0/*top*/, 0/*left*/, 1/*bottom*/, 0/*right*/);
}

#pragma mark -
#pragma mark UIView subclass

- (void)drawRect:(CGRect)rect;
{
    CGRect bounds = self.bounds;
    
    OBASSERT(bounds.size.height == [self buttonHeight]);
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    OUIInspectorWellDrawOuterShadow(ctx, bounds, _rounded);
    
    // Fill the gradient
    CGContextSaveGState(ctx);
    {
        OUIInspectorWellAddPath(ctx, bounds, _rounded);
        CGContextClip(ctx);
        
        [self drawInteriorFillWithRect:bounds];
    }
    CGContextRestoreGState(ctx);
    
    OUIInspectorWellDrawBorderAndInnerShadow(ctx, bounds, _rounded);
    
    if (_showNavigationArrow) {
        UIImage *arrowImage = [self navigationArrowImage];
        CGRect arrowRect, remainder;
        CGRectDivide(bounds, &arrowRect, &remainder, CGRectGetHeight(bounds), CGRectMaxXEdge);
        
        OQDrawImageCenteredInRect(ctx, arrowImage, arrowRect);
    }
}

@end

